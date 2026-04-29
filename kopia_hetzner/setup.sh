#!/bin/bash
#
# kopia_hetzner/setup.sh
#
# Idempotent setup of a Kopia repository on a Hetzner Storage Box (SFTP
# backend). Designed to be re-runnable: every step checks whether it is
# already done and skips. Safe for multiple instances on the same host
# (config-driven, INSTANCE_NAME isolates state).
#
# What it does:
#   1. Installs kopia from the official apt repo (if missing)
#   2. Generates a dedicated ed25519 SSH key (if missing)
#   3. Populates known_hosts and verifies fingerprints against Hetzner's
#      official values (anti-MitM at first contact)
#   4. Uploads the public key to the Storage Box (ssh-copy-id -s with SFTP
#      batch fallback for sub-accounts whose .ssh/ does not exist yet)
#   5. Creates the encrypted Kopia SFTP repository (or connects to it),
#      using --external + tuned --ssh-args to avoid known issues with the
#      Go SSH knownhosts library and the dual-port nature of the Storage Box
#   6. Applies a sensible global policy (retention + compression + ignores)
#   7. Optionally installs a systemd timer for scheduled snapshots
#
# Usage:
#   sudo ./setup.sh -c /path/to/kopia_hetzner.conf
#   sudo ./setup.sh -c <conf> --reset           clean local state only
#   sudo ./setup.sh -c <conf> --install-timer   force timer install
#   sudo ./setup.sh -c <conf> --no-timer        skip timer prompt
#
# Optional environment:
#   KOPIA_PASSWORD   pre-set the repo encryption password (no prompt)
#
# Reference: see README.md alongside this script.

set -euo pipefail

# ============================================================================
# Argument parsing
# ============================================================================
CONF_FILE=""
DO_RESET=0
TIMER_FORCE=""   # ""=ask, "1"=install, "0"=skip

usage() {
    sed -n '2,30p' "$0"
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        -c|--config)      CONF_FILE="$2"; shift 2 ;;
        --reset)          DO_RESET=1; shift ;;
        --install-timer)  TIMER_FORCE=1; shift ;;
        --no-timer)       TIMER_FORCE=0; shift ;;
        -h|--help)        usage ;;
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
: "${SB_USER:?SB_USER is required}"
: "${SB_HOST:?SB_HOST is required}"
: "${SB_PORT:=23}"
: "${SB_PATH:=./kopia}"

: "${HETZNER_FP_ED25519:?HETZNER_FP_ED25519 is required}"
: "${HETZNER_FP_RSA:=}"

: "${SSH_KEY:=/root/.ssh/kopia_${INSTANCE_NAME}_ed25519}"
: "${KNOWN_HOSTS:=/root/.ssh/kopia_${INSTANCE_NAME}_known_hosts}"
: "${KOPIA_CONFIG_DIR:=/root/.config/kopia/${INSTANCE_NAME}}"
: "${KOPIA_CONFIG_FILE:=${KOPIA_CONFIG_DIR}/repository.config}"
: "${KOPIA_PASSWORD_FILE:=${KOPIA_CONFIG_DIR}/password}"
: "${BACKUP_LOG:=/var/log/kopia-${INSTANCE_NAME}.log}"

: "${KOPIA_KEEP_LATEST:=10}"
: "${KOPIA_KEEP_HOURLY:=24}"
: "${KOPIA_KEEP_DAILY:=14}"
: "${KOPIA_KEEP_WEEKLY:=8}"
: "${KOPIA_KEEP_MONTHLY:=12}"
: "${KOPIA_KEEP_ANNUAL:=3}"
: "${KOPIA_COMPRESSION:=zstd}"
: "${KOPIA_IGNORE:=()}"

: "${INSTALL_TIMER:=0}"
: "${TIMER_NAME:=kopia-${INSTANCE_NAME}}"
: "${TIMER_ONCALENDAR:=*-*-* 03:30:00}"
: "${TIMER_RANDOMIZED_DELAY:=30min}"

SYSTEMD_SERVICE="/etc/systemd/system/${TIMER_NAME}.service"
SYSTEMD_TIMER="/etc/systemd/system/${TIMER_NAME}.timer"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"

# Kopia respects the --config-file flag globally; we wrap kopia to inject it
# so multiple instances coexist. KOPIA_PASSWORD is exported when needed.
kopia_cmd() { kopia --config-file="$KOPIA_CONFIG_FILE" "$@"; }

# ============================================================================
# Helpers
# ============================================================================
log()  { echo -e "\033[1;34m[kopia-setup:${INSTANCE_NAME}]\033[0m $*"; }
warn() { echo -e "\033[1;33m[kopia-setup:${INSTANCE_NAME}]\033[0m $*" >&2; }
err()  { echo -e "\033[1;31m[kopia-setup:${INSTANCE_NAME}]\033[0m $*" >&2; exit 1; }

require_root() { [ "$(id -u)" -eq 0 ] || err "Run as root (sudo)."; }

# ============================================================================
# 1. Install kopia
# ============================================================================
install_kopia() {
    if command -v kopia >/dev/null 2>&1; then
        log "kopia already installed: $(kopia --version)"
        return
    fi
    log "Installing kopia from the official apt repository..."
    apt-get update -qq
    apt-get install -y --no-install-recommends curl gnupg ca-certificates openssh-client
    curl -fsSL https://kopia.io/signing-key | gpg --dearmor -o /usr/share/keyrings/kopia-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/kopia-keyring.gpg] https://packages.kopia.io/apt/ stable main" \
        > /etc/apt/sources.list.d/kopia.list
    apt-get update -qq
    apt-get install -y kopia
    log "kopia installed: $(kopia --version)"
}

# ============================================================================
# 2. Generate dedicated SSH key
# ============================================================================
generate_ssh_key() {
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    if [ -f "$SSH_KEY" ]; then
        log "SSH key already present: $SSH_KEY"
        return
    fi
    log "Generating dedicated ed25519 key for Kopia..."
    ssh-keygen -t ed25519 -N "" -C "kopia-${INSTANCE_NAME}@$(hostname)" -f "$SSH_KEY"
    chmod 600 "$SSH_KEY"
}

# ============================================================================
# 3. Known hosts + Hetzner fingerprint verification (anti-MitM)
# ============================================================================
populate_known_hosts() {
    if [ -f "$KNOWN_HOSTS" ] && grep -q "$SB_HOST" "$KNOWN_HOSTS"; then
        local fps_existing
        fps_existing="$(ssh-keygen -lf "$KNOWN_HOSTS" 2>/dev/null | awk '{print $2}')"
        if echo "$fps_existing" | grep -Fxq "$HETZNER_FP_ED25519"; then
            log "known_hosts already populated for $SB_HOST (ED25519 fingerprint verified)."
            return
        fi
        warn "Existing known_hosts does not contain expected fingerprint: regenerating."
        : > "$KNOWN_HOSTS"
    fi

    log "Fetching host keys from $SB_HOST:$SB_PORT..."
    local tmp; tmp="$(mktemp)"
    ssh-keyscan -p "$SB_PORT" -t rsa,ed25519 "$SB_HOST" > "$tmp" 2>/dev/null
    [ -s "$tmp" ] || { rm -f "$tmp"; err "ssh-keyscan returned nothing. Host unreachable?"; }

    local fps; fps="$(ssh-keygen -lf "$tmp" | awk '{print $2}')"
    echo "$fps" | grep -Fxq "$HETZNER_FP_ED25519" \
        || { rm -f "$tmp"; err "ED25519 fingerprint mismatch with Hetzner's official value. Possible MitM. ABORT."; }
    if [ -n "$HETZNER_FP_RSA" ]; then
        echo "$fps" | grep -Fxq "$HETZNER_FP_RSA" \
            || warn "RSA fingerprint mismatch/absent (non-fatal, continuing with ED25519)."
    fi

    mkdir -p "$(dirname "$KNOWN_HOSTS")"
    cat "$tmp" > "$KNOWN_HOSTS"
    rm -f "$tmp"
    chmod 600 "$KNOWN_HOSTS"
    log "Host keys verified and saved in $KNOWN_HOSTS."
}

# ============================================================================
# 4. Upload public key to the Storage Box
# ============================================================================
upload_key_to_storagebox() {
    log "Checking whether the key is already authorised..."
    if ssh -i "$SSH_KEY" \
           -o BatchMode=yes \
           -o UserKnownHostsFile="$KNOWN_HOSTS" \
           -o StrictHostKeyChecking=yes \
           -p "$SB_PORT" "$SB_USER@$SB_HOST" exit 2>/dev/null; then
        log "Key already authorised. OK."
        return
    fi

    warn "Key not authorised yet. You will be asked for the Storage Box SSH password ONCE."

    # Try ssh-copy-id -s (OpenSSH >= 8.5). Avoid grepping its --help under
    # `set -o pipefail` (false negatives); use numeric version check instead.
    local ssh_ver ssh_major ssh_minor ok=0
    ssh_ver="$(ssh -V 2>&1 | sed -n 's/.*OpenSSH_\([0-9.]*\).*/\1/p')"
    ssh_major="${ssh_ver%%.*}"
    ssh_minor="${ssh_ver#*.}"; ssh_minor="${ssh_minor%%.*}"
    : "${ssh_major:=0}"; : "${ssh_minor:=0}"
    local has_dash_s=0
    if [ "$ssh_major" -gt 8 ] 2>/dev/null \
       || { [ "$ssh_major" -eq 8 ] && [ "$ssh_minor" -ge 5 ]; } 2>/dev/null; then
        has_dash_s=1
    fi
    if [ "$has_dash_s" -eq 1 ]; then
        log "Trying ssh-copy-id -s (OpenSSH $ssh_ver)..."
        if ssh-copy-id -s -i "${SSH_KEY}.pub" -p "$SB_PORT" "$SB_USER@$SB_HOST"; then
            ok=1
        else
            warn "ssh-copy-id failed (typical for sub-accounts without .ssh/). Falling back to SFTP batch."
        fi
    else
        warn "ssh-copy-id has no -s flag (OpenSSH $ssh_ver < 8.5). Using SFTP batch."
    fi

    # Fallback: SFTP batch. Creates .ssh/, fetches existing authorized_keys
    # if any, idempotently appends our key, uploads.
    if [ "$ok" -eq 0 ]; then
        local pub batch existing
        pub="$(cat "${SSH_KEY}.pub")"
        batch="$(mktemp)"
        existing="$(mktemp)"
        cat >"$batch" <<EOF
-mkdir .ssh
chmod 700 .ssh
-get .ssh/authorized_keys $existing
EOF
        sftp -P "$SB_PORT" \
             -o UserKnownHostsFile="$KNOWN_HOSTS" \
             -o StrictHostKeyChecking=yes \
             -b "$batch" "$SB_USER@$SB_HOST" || true

        touch "$existing"
        # Ensure trailing newline before append, otherwise keys may concatenate.
        if [ -s "$existing" ] && [ "$(tail -c1 "$existing")" != "" ]; then
            printf '\n' >> "$existing"
        fi
        if ! grep -Fxq "$pub" "$existing"; then
            echo "$pub" >> "$existing"
        fi
        cat >"$batch" <<EOF
put $existing .ssh/authorized_keys
chmod 600 .ssh/authorized_keys
EOF
        sftp -P "$SB_PORT" \
             -o UserKnownHostsFile="$KNOWN_HOSTS" \
             -o StrictHostKeyChecking=yes \
             -b "$batch" "$SB_USER@$SB_HOST"
        rm -f "$batch" "$existing"
    fi

    if ssh -i "$SSH_KEY" \
           -o BatchMode=yes \
           -o UserKnownHostsFile="$KNOWN_HOSTS" \
           -o StrictHostKeyChecking=yes \
           -p "$SB_PORT" "$SB_USER@$SB_HOST" exit 2>/dev/null; then
        log "Key successfully authorised."
    else
        err "Key upload failed: passwordless login still does not work. Check credentials and remote permissions."
    fi
}

# ============================================================================
# 5. Repository encryption password
# ============================================================================
ensure_repo_password() {
    mkdir -p "$KOPIA_CONFIG_DIR"
    chmod 700 "$KOPIA_CONFIG_DIR"
    if [ -f "$KOPIA_PASSWORD_FILE" ]; then
        log "Repo password already present: $KOPIA_PASSWORD_FILE"
        return
    fi
    if [ -n "${KOPIA_PASSWORD:-}" ]; then
        printf '%s' "$KOPIA_PASSWORD" > "$KOPIA_PASSWORD_FILE"
    else
        echo
        echo "Set an ENCRYPTION password for the Kopia repository."
        echo "WARNING: without it the backups are NOT recoverable. Store it in a password manager."
        local p1 p2
        while :; do
            read -r -s -p "Password: " p1; echo
            read -r -s -p "Confirm:  " p2; echo
            [ "$p1" = "$p2" ] && [ -n "$p1" ] && break
            warn "Passwords do not match or are empty, try again."
        done
        printf '%s' "$p1" > "$KOPIA_PASSWORD_FILE"
        unset p1 p2
    fi
    chmod 600 "$KOPIA_PASSWORD_FILE"
}

# ============================================================================
# 6. Create / connect SFTP repository
#    Use --external because Kopia's internal Go SSH knownhosts library has
#    incompatibilities with several SSH servers (kopia/kopia#2948, #1777),
#    and force port + ed25519 host key explicitly because:
#      - Kopia does not reliably forward --port to the external ssh binary
#        (it falls back to port 22, which on Hetzner Storage Box exposes
#        only RSA/DSS host keys, not ed25519);
#      - ed25519 is the only host key with an officially verified fingerprint.
# ============================================================================
setup_repository() {
    export KOPIA_PASSWORD
    KOPIA_PASSWORD="$(cat "$KOPIA_PASSWORD_FILE")"

    if kopia_cmd repository status >/dev/null 2>&1; then
        log "Kopia repository already connected."
        kopia_cmd repository status | sed 's/^/    /'
        return
    fi

    local ssh_args
    ssh_args="-i $SSH_KEY -o UserKnownHostsFile=$KNOWN_HOSTS -o StrictHostKeyChecking=yes -o BatchMode=yes -o HostKeyAlgorithms=ssh-ed25519 -o Port=$SB_PORT -p $SB_PORT"

    log "Trying to connect to an existing repository (--external mode)..."
    if kopia_cmd repository connect sftp \
            --external \
            --path="$SB_PATH" \
            --host="$SB_HOST" \
            --port="$SB_PORT" \
            --username="$SB_USER" \
            --ssh-args="$ssh_args" 2>/dev/null; then
        log "Connected to existing repository."
        return
    fi

    log "No remote repository found, creating a new one (--external mode)..."
    kopia_cmd repository create sftp \
        --external \
        --path="$SB_PATH" \
        --host="$SB_HOST" \
        --port="$SB_PORT" \
        --username="$SB_USER" \
        --ssh-args="$ssh_args"
    log "Repository created and connected."
}

# ============================================================================
# 7. Global retention + ignore policy
# ============================================================================
apply_global_policy() {
    log "Applying global policy (retention, compression, ignores)..."
    local args=(
        --keep-latest="$KOPIA_KEEP_LATEST"
        --keep-hourly="$KOPIA_KEEP_HOURLY"
        --keep-daily="$KOPIA_KEEP_DAILY"
        --keep-weekly="$KOPIA_KEEP_WEEKLY"
        --keep-monthly="$KOPIA_KEEP_MONTHLY"
        --keep-annual="$KOPIA_KEEP_ANNUAL"
        --compression="$KOPIA_COMPRESSION"
    )
    local p
    for p in "${KOPIA_IGNORE[@]:-}"; do
        [ -n "$p" ] && args+=(--add-ignore="$p")
    done
    kopia_cmd policy set --global "${args[@]}"
    log "Global policy applied."
}

# ============================================================================
# 8. systemd timer (modern alternative to cron)
# ============================================================================
install_systemd_timer() {
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemd not detected: skipping timer install. Use cron manually."
        return
    fi

    local want="$TIMER_FORCE"
    [ -z "$want" ] && want="$INSTALL_TIMER"
    if [ -z "$want" ] || [ "$want" = "" ]; then
        echo
        read -r -p "Install systemd timer for automatic backups (${TIMER_ONCALENDAR})? [y/N] " ans
        case "${ans:-}" in
            y|Y|yes|YES) want=1 ;;
            *) want=0 ;;
        esac
    fi
    [ "$want" = "1" ] || { log "Timer not installed (re-run with --install-timer to enable)."; return; }

    [ -x "$BACKUP_SCRIPT" ] || err "backup.sh not found or not executable: $BACKUP_SCRIPT"

    log "Writing systemd unit: $SYSTEMD_SERVICE"
    cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=Kopia backup (${INSTANCE_NAME}) -> Hetzner Storage Box
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=oneshot
Nice=19
IOSchedulingClass=best-effort
IOSchedulingPriority=7
ExecStart=${BACKUP_SCRIPT} -c ${CONF_FILE}
StandardOutput=append:${BACKUP_LOG}
StandardError=append:${BACKUP_LOG}
SyslogIdentifier=${TIMER_NAME}
EOF

    log "Writing systemd timer: $SYSTEMD_TIMER"
    cat > "$SYSTEMD_TIMER" <<EOF
[Unit]
Description=Schedule Kopia backups (${INSTANCE_NAME})

[Timer]
OnCalendar=${TIMER_ONCALENDAR}
RandomizedDelaySec=${TIMER_RANDOMIZED_DELAY}
Persistent=true
Unit=${TIMER_NAME}.service

[Install]
WantedBy=timers.target
EOF

    touch "$BACKUP_LOG"
    chmod 640 "$BACKUP_LOG"
    systemctl daemon-reload
    systemctl enable --now "${TIMER_NAME}.timer"
    log "Timer active. Next runs:"
    systemctl list-timers "${TIMER_NAME}.timer" --no-pager | sed 's/^/    /'
}

# ============================================================================
# Reset (local state only, never touches the Storage Box)
# ============================================================================
reset_local_state() {
    require_root
    warn "Local state RESET for instance '${INSTANCE_NAME}'. Storage Box data is NOT touched."
    read -r -p "Are you sure? (yes/NO) " ans
    [ "${ans:-}" = "yes" ] || { log "Aborted."; exit 0; }

    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files "${TIMER_NAME}.timer" >/dev/null 2>&1; then
        systemctl disable --now "${TIMER_NAME}.timer" 2>/dev/null || true
    fi
    rm -f "$SYSTEMD_SERVICE" "$SYSTEMD_TIMER"
    command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true

    if command -v kopia >/dev/null 2>&1 && kopia_cmd repository status >/dev/null 2>&1; then
        kopia_cmd repository disconnect || true
    fi

    rm -f "$SSH_KEY" "${SSH_KEY}.pub" "$KNOWN_HOSTS" "$KOPIA_PASSWORD_FILE" "$KOPIA_CONFIG_FILE" "${KOPIA_CONFIG_FILE}".*

    log "Local state reset for '${INSTANCE_NAME}'. Re-run setup.sh to reinitialise."
    log "NB: the public key remains in the Storage Box's authorized_keys, and"
    log "    the repository is still in $SB_PATH. Clean those manually if desired."
}

# ============================================================================
# Main
# ============================================================================
main() {
    require_root
    install_kopia
    generate_ssh_key
    populate_known_hosts
    upload_key_to_storagebox
    ensure_repo_password
    setup_repository
    apply_global_policy
    install_systemd_timer

    cat <<EOF

============================================================
  Kopia setup completed for instance '${INSTANCE_NAME}'.
============================================================

Repository:     sftp://${SB_USER}@${SB_HOST}:${SB_PORT}/${SB_PATH}
SSH key:        ${SSH_KEY}  (pub: ${SSH_KEY}.pub)
Repo password:  ${KOPIA_PASSWORD_FILE}  (chmod 600)
Kopia config:   ${KOPIA_CONFIG_FILE}

Next steps:
  1. Run a first manual snapshot:
         sudo ${BACKUP_SCRIPT} -c ${CONF_FILE}
  2. If you installed the systemd timer:
         systemctl list-timers ${TIMER_NAME}.timer
         systemctl status ${TIMER_NAME}.service
         journalctl -u ${TIMER_NAME}.service -n 200
  3. Useful Kopia commands (use --config-file=${KOPIA_CONFIG_FILE}):
         kopia --config-file=${KOPIA_CONFIG_FILE} snapshot list
         kopia --config-file=${KOPIA_CONFIG_FILE} snapshot verify --all-sources

Recovery:
  - Setup interrupted?     re-run: sudo $0 -c ${CONF_FILE}   (idempotent)
  - Local state corrupt?   sudo $0 -c ${CONF_FILE} --reset   then re-run.
  - Remote repo corrupt?   delete '${SB_PATH}' on the Storage Box and re-run.

EOF
}

if [ "$DO_RESET" -eq 1 ]; then
    reset_local_state
else
    main
fi
