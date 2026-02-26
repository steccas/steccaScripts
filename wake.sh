#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-t timeout] [-i interval] [-v] [-b broadcast] MAC_ADDRESS IP_ADDRESS INTERFACE"
    echo "Options:"
    echo "  -h            Show this help message"
    echo "  -t timeout    Maximum time to wait in seconds (default: 300)"
    echo "  -i interval   Interval between attempts in seconds (default: 4)"
    echo "  -v            Verbose output"
    echo "  -b broadcast  Subnet broadcast address for cross-VLAN WOL (e.g. 192.168.1.255)"
    echo
    echo "Example: $0 -b 192.168.1.255 FF:FF:FF:FF:FF:FF 192.168.1.6 eth0"
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

# Default values
TIMEOUT=300
INTERVAL=4
VERBOSE=false
BROADCAST=""

# Parse arguments
while getopts "ht:i:v:b:" opt; do
    case $opt in
        h)
            usage
            ;;
        t)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -lt 1 ]; then
                log ERROR "Timeout must be a positive number"
                exit 1
            fi
            TIMEOUT=$OPTARG
            ;;
        i)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -lt 1 ]; then
                log ERROR "Interval must be a positive number"
                exit 1
            fi
            INTERVAL=$OPTARG
            ;;
        v)
            VERBOSE=true
            ;;
        b)
            BROADCAST=$OPTARG
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# Check required arguments
if [ "$#" -ne 3 ]; then
    log ERROR "Missing required arguments"
    usage
fi

MAC_ADDRESS=$1
IP_ADDRESS=$2
INTERFACE=$3

# Validate MAC address format
if ! [[ "$MAC_ADDRESS" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    log ERROR "Invalid MAC address format. Expected format: XX:XX:XX:XX:XX:XX"
    exit 1
fi

# Validate IP address format
if ! [[ "$IP_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log ERROR "Invalid IP address format. Expected format: XXX.XXX.XXX.XXX"
    exit 1
fi

# Check if interface exists
if ! ip link show "$INTERFACE" &>/dev/null; then
    log ERROR "Interface $INTERFACE does not exist"
    exit 1
fi

# Add /usr/sbin to PATH if not already present
[[ ":$PATH:" != *":/usr/sbin:"* ]] && export PATH="$PATH:/usr/sbin"

# Check for required tools
for tool in wakeonlan etherwake ping; do
    if ! command -v $tool &>/dev/null; then
        log ERROR "$tool could not be found. Please install it first."
        exit 1
    fi
done

log INFO "Starting wake-on-LAN for device:"
log INFO "- MAC Address: $MAC_ADDRESS"
log INFO "- IP Address: $IP_ADDRESS"
log INFO "- Interface: $INTERFACE"
log INFO "- Broadcast: ${BROADCAST:-not set, using IP}"
log INFO "- Timeout: $TIMEOUT seconds"
log INFO "- Interval: $INTERVAL seconds"

START_TIME=$(date +%s)
ATTEMPTS=0

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        log ERROR "Timeout reached after $ATTEMPTS attempts"
        exit 1
    fi
    
    # Try to ping the target
    if ping -c 1 -W 1 "$IP_ADDRESS" >/dev/null 2>&1; then
        log INFO "Device is now responding after $ATTEMPTS attempts (${ELAPSED}s)"
        exit 0
    fi
    
    # Send wake-on-LAN packets using multiple methods for best coverage
    log INFO "Sending wake-on-LAN packets (attempt $((++ATTEMPTS)))"
    # 1. Plain broadcast 255.255.255.255 (no ARP, no router, works via L2 VLAN trunk)
    wakeonlan "$MAC_ADDRESS" 2>/dev/null
    # 2. L2 raw broadcast on local interface (no ARP, no router)
    etherwake -i "$INTERFACE" "$MAC_ADDRESS" 2>/dev/null
    # 3. Unicast to IP (requires ARP on router, works when server was recently on)
    wakeonlan -i "$IP_ADDRESS" "$MAC_ADDRESS" 2>/dev/null
    # 4. Directed broadcast if provided (requires router support, last resort)
    if [ -n "$BROADCAST" ]; then
        wakeonlan -i "$BROADCAST" "$MAC_ADDRESS" 2>/dev/null
    fi
    
    # Show remaining time if verbose
    if [ "$VERBOSE" = true ]; then
        REMAINING=$((TIMEOUT - ELAPSED))
        log INFO "Time remaining: ${REMAINING}s"
    fi
    
    sleep "$INTERVAL"
done