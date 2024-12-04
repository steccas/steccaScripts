#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-d] [-r]"
    echo "Options:"
    echo "  -h    Show this help message"
    echo "  -d    Dry run (show what would be done)"
    echo "  -r    Remove existing profiles before setting sRGB"
    exit 1
}

# Parse arguments
DRY_RUN=false
REMOVE_EXISTING=false

while getopts "hdr" opt; do
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
        \?)
            usage
            ;;
    esac
done

# Check if colormgr is installed
if ! command -v colormgr &> /dev/null; then
    echo "Error: colormgr is not installed. Please install colord package."
    exit 1
fi

# Function to execute or simulate command
execute_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute: $@"
    else
        echo "Executing: $@"
        "$@"
    fi
}

echo "Fixing Chromium color profiles..."

# Get sRGB profile path
SRGB_PATH=$(colormgr get-standard-space srgb | grep "Object Path:" | cut -d: -f2)
if [ -z "$SRGB_PATH" ]; then
    echo "Error: Could not find sRGB profile"
    exit 1
fi
echo "Found sRGB profile: $SRGB_PATH"

# Get all display devices
DISPLAY_PATHS=$(colormgr get-devices display | grep "Object Path:" | cut -d: -f2)
if [ -z "$DISPLAY_PATHS" ]; then
    echo "Error: No display devices found"
    exit 1
fi

# Process each display
for DISPLAY_PATH in $DISPLAY_PATHS; do
    echo
    echo "Processing display: $DISPLAY_PATH"
    
    # Get display info
    DISPLAY_INFO=$(colormgr get-device-details $DISPLAY_PATH)
    echo "Display details:"
    echo "$DISPLAY_INFO" | grep "Model:" || echo "  Model: Unknown"
    echo "$DISPLAY_INFO" | grep "Vendor:" || echo "  Vendor: Unknown"
    
    if [ "$REMOVE_EXISTING" = true ]; then
        echo "Removing existing profiles..."
        EXISTING_PROFILES=$(colormgr device-get-profiles $DISPLAY_PATH | grep "Object Path:" | cut -d: -f2)
        for PROFILE in $EXISTING_PROFILES; do
            execute_cmd colormgr device-remove-profile $DISPLAY_PATH $PROFILE
        done
    fi
    
    # Add sRGB profile
    echo "Adding sRGB profile..."
    execute_cmd colormgr device-add-profile $DISPLAY_PATH $SRGB_PATH
    
    # Make sRGB profile default
    echo "Setting sRGB as default..."
    execute_cmd colormgr device-make-profile-default $DISPLAY_PATH $SRGB_PATH
done

echo
if [ "$DRY_RUN" = true ]; then
    echo "Dry run completed. No changes were made."
else
    echo "Color profile configuration completed successfully."
    echo "Please restart Chromium for changes to take effect."
fi

exit 0
