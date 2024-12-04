#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-i interval] [-t timeout] [-v] [-f] INTERFACE TARGET_IP"
    echo "Options:"
    echo "  -h          Show this help message"
    echo "  -i interval Check interval in seconds (default: 60)"
    echo "  -t timeout  Ping timeout in seconds (default: 5)"
    echo "  -v          Verbose output"
    echo "  -f          Force restart even if ping succeeds"
    echo
    echo "Example: $0 -i 30 wg0 8.8.8.8"
    exit 1
}

# Function to log messages
log() {
    local level=$1
    shift
    local msg="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            [ "$VERBOSE" = true ] && echo "[$timestamp] INFO: $msg"
            ;;
        WARN)
            echo "[$timestamp] WARNING: $msg" >&2
            ;;
        ERROR)
            echo "[$timestamp] ERROR: $msg" >&2
            ;;
        *)
            echo "[$timestamp] $msg"
            ;;
    esac
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log ERROR "This script must be run as root"
        exit 1
    fi
}

# Function to check dependencies
check_dependencies() {
    for cmd in systemctl ping ip; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log ERROR "Required command '$cmd' not found"
            exit 1
        fi
    done
}

# Function to validate interface
validate_interface() {
    local interface=$1
    if ! ip link show "$interface" >/dev/null 2>&1; then
        log ERROR "Interface $interface does not exist"
        exit 1
    fi
}

# Function to restart WireGuard interface
restart_wireguard() {
    local interface=$1
    log INFO "Restarting WireGuard interface $interface"
    
    if systemctl restart "wg-quick@${interface}"; then
        log INFO "WireGuard interface $interface restarted successfully"
        return 0
    else
        log ERROR "Failed to restart WireGuard interface $interface"
        return 1
    fi
}

# Default values
INTERVAL=60
TIMEOUT=5
VERBOSE=false
FORCE=false

# Parse arguments
while getopts "hi:t:vf" opt; do
    case $opt in
        h)
            usage
            ;;
        i)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -lt 1 ]; then
                log ERROR "Interval must be a positive number"
                exit 1
            fi
            INTERVAL=$OPTARG
            ;;
        t)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -lt 1 ]; then
                log ERROR "Timeout must be a positive number"
                exit 1
            fi
            TIMEOUT=$OPTARG
            ;;
        v)
            VERBOSE=true
            ;;
        f)
            FORCE=true
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# Check required arguments
if [ "$#" -ne 2 ]; then
    log ERROR "Missing required arguments"
    usage
fi

INTERFACE=$1
TARGET_IP=$2

# Initial checks
check_root
check_dependencies
validate_interface "$INTERFACE"

# Validate IP address format
if ! [[ "$TARGET_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log ERROR "Invalid IP address format. Expected format: XXX.XXX.XXX.XXX"
    exit 1
fi

log INFO "Starting WireGuard connection monitor:"
log INFO "- Interface: $INTERFACE"
log INFO "- Target IP: $TARGET_IP"
log INFO "- Check Interval: $INTERVAL seconds"
log INFO "- Ping Timeout: $TIMEOUT seconds"
log INFO "- Force Restart: $FORCE"

FAILURES=0
RESTARTS=0
START_TIME=$(date +%s)

while true; do
    if [ "$FORCE" = true ]; then
        log INFO "Forced restart requested"
        if restart_wireguard "$INTERFACE"; then
            ((RESTARTS++))
        fi
        FORCE=false
    else
        if ! ping -c 1 -W "$TIMEOUT" "$TARGET_IP" >/dev/null 2>&1; then
            ((FAILURES++))
            log WARN "Ping failed (failure #$FAILURES)"
            if restart_wireguard "$INTERFACE"; then
                ((RESTARTS++))
                FAILURES=0
            fi
        else
            FAILURES=0
            [ "$VERBOSE" = true ] && log INFO "Connection is healthy"
        fi
    fi
    
    # Show statistics if verbose
    if [ "$VERBOSE" = true ]; then
        CURRENT_TIME=$(date +%s)
        UPTIME=$((CURRENT_TIME - START_TIME))
        log INFO "Statistics:"
        log INFO "- Uptime: ${UPTIME}s"
        log INFO "- Total Restarts: $RESTARTS"
        log INFO "- Current Failures: $FAILURES"
    fi
    
    sleep "$INTERVAL"
done
