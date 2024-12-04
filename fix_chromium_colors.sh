#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-d] [-r] [-p profile] [-c color] [-v]"
    echo "Options:"
    echo "  -h           Show this help message"
    echo "  -d           Dry run (show what would be done)"
    echo "  -r           Remove existing profiles before setting sRGB"
    echo "  -p profile   Specify ICC profile (default: sRGB)"
    echo "  -c color     Color profile name (default: sRGB-elle-V2-srgbtrc.icc)"
    echo "  -v           Verbose output"
    exit 1
}

# Default values
DRY_RUN=false
REMOVE_EXISTING=false
ICC_PROFILE="sRGB"
COLOR_PROFILE="sRGB-elle-V2-srgbtrc.icc"
VERBOSE=false

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

# Parse arguments
while getopts "hdrp:c:v" opt; do
    case $opt in
        h)
            usage
            ;;
        d)
            DRY_RUN=true
            ;;
        r)
            REMOVE_EXISTING=true
            ;;
        p)
            ICC_PROFILE="$OPTARG"
            ;;
        c)
            COLOR_PROFILE="$OPTARG"
            ;;
        v)
            VERBOSE=true
            ;;
        \?)
            usage
            ;;
    esac
done

# Check if colormgr is installed
if ! command -v colormgr &> /dev/null; then
    log ERROR "colormgr is not installed. Please install colord package."
    exit 1
fi

# Check if the color profile file exists
PROFILE_PATH="/usr/share/color/icc/colord/$COLOR_PROFILE"
if [ ! -f "$PROFILE_PATH" ]; then
    log ERROR "Color profile not found at $PROFILE_PATH"
    log ERROR "Available profiles:"
    ls -1 /usr/share/color/icc/colord/
    exit 1
fi

# Function to execute or simulate command
execute_cmd() {
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would execute: $@"
    else
        log INFO "Executing: $@"
        if ! "$@"; then
            log ERROR "Command failed: $@"
            return 1
        fi
    fi
    return 0
}

# Function to get device ID
get_device_id() {
    local device_id=""
    while read -r line; do
        if [[ $line =~ ^Device[[:space:]]+ID:[[:space:]]+(.+)$ ]]; then
            device_id="${BASH_REMATCH[1]}"
            break
        fi
    done < <(colormgr get-devices)
    echo "$device_id"
}

# Function to get profile ID
get_profile_id() {
    local profile_name="$1"
    local profile_id=""
    while read -r line; do
        if [[ $line =~ ^Profile[[:space:]]+ID:[[:space:]]+(.+)$ ]] && \
           grep -q "Profile Name: $profile_name" < <(colormgr get-profile "${BASH_REMATCH[1]}"); then
            profile_id="${BASH_REMATCH[1]}"
            break
        fi
    done < <(colormgr get-profiles)
    echo "$profile_id"
}

log INFO "Fixing Chromium color profiles..."

# Get device ID
DEVICE_ID=$(get_device_id)
if [ -z "$DEVICE_ID" ]; then
    log ERROR "No color managed device found"
    exit 1
fi
log INFO "Found device ID: $DEVICE_ID"

# Remove existing profiles if requested
if [ "$REMOVE_EXISTING" = true ]; then
    log INFO "Removing existing color profiles..."
    while read -r profile_id; do
        if [ -n "$profile_id" ]; then
            execute_cmd colormgr device-remove-profile "$DEVICE_ID" "$profile_id"
        fi
    done < <(colormgr device-get-profiles "$DEVICE_ID" | grep "^Profile ID" | cut -d' ' -f3)
fi

# Get profile ID
PROFILE_ID=$(get_profile_id "$ICC_PROFILE")
if [ -z "$PROFILE_ID" ]; then
    log INFO "Profile $ICC_PROFILE not found, importing..."
    if ! execute_cmd colormgr import-profile "$PROFILE_PATH"; then
        log ERROR "Failed to import color profile"
        exit 1
    fi
    PROFILE_ID=$(get_profile_id "$ICC_PROFILE")
    if [ -z "$PROFILE_ID" ]; then
        log ERROR "Failed to get profile ID after import"
        exit 1
    fi
fi
log INFO "Using profile ID: $PROFILE_ID"

# Add profile to device
log INFO "Adding profile to device..."
if ! execute_cmd colormgr device-add-profile "$DEVICE_ID" "$PROFILE_ID"; then
    log ERROR "Failed to add profile to device"
    exit 1
fi

# Make profile default
log INFO "Setting profile as default..."
if ! execute_cmd colormgr device-make-profile-default "$DEVICE_ID" "$PROFILE_ID"; then
    log ERROR "Failed to set profile as default"
    exit 1
fi

# Verify configuration
if [ "$VERBOSE" = true ]; then
    log INFO "Current device configuration:"
    colormgr device-get-default-profile "$DEVICE_ID"
    log INFO "Available profiles:"
    colormgr device-get-profiles "$DEVICE_ID"
fi

log INFO "Color profile configuration completed successfully!"
if [ "$DRY_RUN" = true ]; then
    log INFO "This was a dry run. No changes were made."
fi

exit 0
