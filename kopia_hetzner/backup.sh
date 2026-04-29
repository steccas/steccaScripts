#!/bin/bash
#
# kopia_hetzner/backup.sh
#
# Run a Kopia snapshot of the configured sources, optionally preceded by a
# consistent MySQL/MariaDB dump (when MYSQL_CONTAINER is set).
#
# Flow:
#   1. (optional) mysqldump --single-transaction into MYSQL_DUMP_DIR
#   2. snapshot every entry in SOURCES
#   3. show last snapshot list and run a quick maintenance pass
#
# Usage:
#   sudo ./backup.sh -c /path/to/kopia_hetzner.conf

set -euo pipefail

# ============================================================================
# Argument parsing
# ============================================================================
CONF_FILE=""

usage() {
    sed -n '2,18p' "$0"
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        -c|--config) CONF_FILE="$2"; shift 2 ;;
        -h|--help)   usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

[ -n "$CONF_FILE" ] || { echo "Missing -c <config_file>" >&2; usage; }
[ -f "$CONF_FILE" ] || { echo "Config file not found: $CONF_FILE" >&2; exit 1; }

# ============================================================================
# Load configuration
# ============================================================================
# shellcheck disable=SC1090
. "$CONF_FILE"

: "${INSTANCE_NAME:?INSTANCE_NAME is required}"
: "${SOURCES:?SOURCES array is required}"

: "${KOPIA_CONFIG_DIR:=/root/.config/kopia/${INSTANCE_NAME}}"
: "${KOPIA_CONFIG_FILE:=${KOPIA_CONFIG_DIR}/repository.config}"
: "${KOPIA_PASSWORD_FILE:=${KOPIA_CONFIG_DIR}/password}"
: "${KOPIA_PARALLEL:=4}"

: "${MYSQL_CONTAINER:=}"
: "${MYSQL_DUMP_DIR:=}"
: "${MYSQL_DUMP_KEEP_LOCAL:=7}"

kopia_cmd() { kopia --config-file="$KOPIA_CONFIG_FILE" "$@"; }

# ============================================================================
# Helpers
# ============================================================================
log()  { echo -e "\033[1;34m[kopia-backup:${INSTANCE_NAME}]\033[0m $(date -Iseconds) $*"; }
warn() { echo -e "\033[1;33m[kopia-backup:${INSTANCE_NAME}]\033[0m $(date -Iseconds) $*" >&2; }
err()  { echo -e "\033[1;31m[kopia-backup:${INSTANCE_NAME}]\033[0m $(date -Iseconds) $*" >&2; exit 1; }

require_root() { [ "$(id -u)" -eq 0 ] || err "Run as root (sudo)."; }

ensure_kopia_ready() {
    command -v kopia >/dev/null 2>&1 || err "kopia not installed. Run setup.sh first."
    [ -f "$KOPIA_PASSWORD_FILE" ] || err "Password file not found: $KOPIA_PASSWORD_FILE. Run setup.sh first."
    [ -f "$KOPIA_CONFIG_FILE" ]   || err "Kopia config not found: $KOPIA_CONFIG_FILE. Run setup.sh first."
    export KOPIA_PASSWORD
    KOPIA_PASSWORD="$(cat "$KOPIA_PASSWORD_FILE")"
    kopia_cmd repository status >/dev/null 2>&1 || err "Repository not connected. Run setup.sh first."
}

# ============================================================================
# 1. Optional MySQL/MariaDB dump
#    We read credentials directly from the running container's env (no .env
#    parsing, robust against shell-special characters in passwords). We use
#    the application user (MYSQL_USER) because:
#      - it has ALL PRIVILEGES on its database (sufficient for
#        --single-transaction --routines --triggers --events);
#      - it avoids the 'root'@'localhost' vs 'root'@'%' password mismatch
#        common in MariaDB Docker images;
#      - principle of least privilege.
#    We force --protocol=tcp -h 127.0.0.1 so MariaDB matches the '<user>'@'%'
#    grant rather than a possibly different '<user>'@'localhost' entry.
# ============================================================================
dump_mysql() {
    [ -n "$MYSQL_CONTAINER" ] || { log "MYSQL_CONTAINER unset, skipping DB dump."; return; }
    [ -n "$MYSQL_DUMP_DIR" ]  || err "MYSQL_DUMP_DIR is required when MYSQL_CONTAINER is set."

    if ! docker ps --format '{{.Names}}' | grep -qx "$MYSQL_CONTAINER"; then
        warn "Container $MYSQL_CONTAINER not running: skipping DB dump."
        return
    fi

    local mysql_user mysql_password mysql_database
    mysql_user="$(docker exec "$MYSQL_CONTAINER" printenv MYSQL_USER 2>/dev/null || true)"
    mysql_password="$(docker exec "$MYSQL_CONTAINER" printenv MYSQL_PASSWORD 2>/dev/null || true)"
    mysql_database="$(docker exec "$MYSQL_CONTAINER" printenv MYSQL_DATABASE 2>/dev/null || true)"
    if [ -z "$mysql_user" ] || [ -z "$mysql_password" ] || [ -z "$mysql_database" ]; then
        warn "MYSQL_USER/MYSQL_PASSWORD/MYSQL_DATABASE not readable from $MYSQL_CONTAINER: skipping DB dump."
        return
    fi

    mkdir -p "$MYSQL_DUMP_DIR"
    chmod 700 "$MYSQL_DUMP_DIR"
    local ts dump_file
    ts="$(date +%Y%m%d-%H%M%S)"
    dump_file="$MYSQL_DUMP_DIR/${mysql_database}-${ts}.sql.gz"

    # Prefer mariadb-dump if available (mysqldump is a deprecated alias).
    local dump_cmd="mariadb-dump"
    if ! docker exec "$MYSQL_CONTAINER" sh -c 'command -v mariadb-dump' >/dev/null 2>&1; then
        dump_cmd="mysqldump"
    fi

    log "DB dump ($dump_cmd, user=$mysql_user) -> $dump_file"
    docker exec -i -e MYSQL_PWD="$mysql_password" "$MYSQL_CONTAINER" \
        "$dump_cmd" -h 127.0.0.1 --protocol=tcp -u "$mysql_user" \
                    --single-transaction --routines --triggers --events \
                    "$mysql_database" \
        | gzip -c > "$dump_file"

    # Local rotation (Kopia handles long-term retention via global policy).
    ls -1t "$MYSQL_DUMP_DIR"/*.sql.gz 2>/dev/null | tail -n +"$((MYSQL_DUMP_KEEP_LOCAL + 1))" | xargs -r rm -f
    log "DB dump done."
}

# ============================================================================
# 2. Kopia snapshots
# ============================================================================
snapshot_sources() {
    local src
    for src in "${SOURCES[@]}"; do
        if [ ! -e "$src" ]; then
            warn "Source missing, skipping: $src"
            continue
        fi
        log "Snapshot $src (parallel=$KOPIA_PARALLEL) ..."
        kopia_cmd snapshot create --parallel="$KOPIA_PARALLEL" "$src"
    done
}

# ============================================================================
# 3. Post-snapshot listing + maintenance
# ============================================================================
post_actions() {
    log "Latest snapshots:"
    kopia_cmd snapshot list --max-results-per-source=1 | sed 's/^/    /'

    log "Maintenance (quick)..."
    kopia_cmd maintenance run --safety=full || warn "Maintenance not run (only the repo owner can run it)."
}

# ============================================================================
# Main
# ============================================================================
main() {
    require_root
    ensure_kopia_ready
    dump_mysql
    snapshot_sources
    post_actions
    log "Backup completed."
}

main "$@"
