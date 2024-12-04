#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-s swap_size] [-n] [-k] [-f]"
    echo "Options:"
    echo "  -h           Show this help message"
    echo "  -s size      Swap file size in GB (default: 6)"
    echo "  -n          Skip snapd removal"
    echo "  -k          Keep existing swap configuration"
    echo "  -f          Skip Fish shell installation"
    exit 1
}

# Default values
SWAP_SIZE=6
SKIP_SNAPD=false
KEEP_SWAP=false
SKIP_FISH=false

# Parse arguments
while getopts "hs:nkf" opt; do
    case $opt in
        h)
            usage
            ;;
        s)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -lt 1 ]; then
                echo "Error: Swap size must be a positive number"
                exit 1
            fi
            SWAP_SIZE=$OPTARG
            ;;
        n)
            SKIP_SNAPD=true
            ;;
        k)
            KEEP_SWAP=true
            ;;
        f)
            SKIP_FISH=true
            ;;
        \?)
            usage
            ;;
    esac
done

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to handle errors
handle_error() {
    log "Error: $1"
    exit 1
}

# Function to execute commands with error handling
execute() {
    log "Executing: $1"
    if ! eval "$1"; then
        handle_error "Failed to execute: $1"
    fi
}

log "Starting lite server setup..."
log "Configuration:"
log "- Swap Size: ${SWAP_SIZE}GB"
log "- Remove Snapd: $([ "$SKIP_SNAPD" = false ] && echo "Yes" || echo "No")"
log "- Configure Swap: $([ "$KEEP_SWAP" = false ] && echo "Yes" || echo "No")"
log "- Install Fish: $([ "$SKIP_FISH" = false ] && echo "Yes" || echo "No")"

# Upgrade OS
log "Upgrading system packages..."
execute "apt update && apt dist-upgrade -y"

# Remove snapd if requested
if [ "$SKIP_SNAPD" = false ]; then
    log "Removing snapd..."
    execute "apt autoremove --purge -y snapd"
fi

# Install basic packages
log "Installing basic packages..."
PACKAGES=(
    apt-transport-https
    ca-certificates
    curl
    gnupg-agent
    software-properties-common
    fonts-powerline
)

[ "$SKIP_FISH" = false ] && PACKAGES+=(fish)

execute "apt install -y ${PACKAGES[*]}"

# Configure swap
if [ "$KEEP_SWAP" = false ]; then
    log "Configuring swap (${SWAP_SIZE}GB)..."
    
    # Check current swap configuration
    CURRENT_SWAP=$(swapon --show=NAME --noheadings)
    if [ -n "$CURRENT_SWAP" ]; then
        log "Disabling current swap..."
        execute "swapoff -a"
    fi
    
    # Remove existing swap files
    [ -f /swap.img ] && execute "rm /swap.img"
    [ -f /swapfile ] && execute "rm /swapfile"
    
    # Create new swap
    execute "fallocate -l ${SWAP_SIZE}G /swapfile"
    execute "chmod 600 /swapfile"
    execute "mkswap /swapfile"
    execute "swapon /swapfile"
    
    # Update fstab if needed
    if ! grep -q "/swapfile" /etc/fstab; then
        log "Adding swap entry to fstab..."
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    fi
    
    # Configure swappiness
    execute "sysctl vm.swappiness=10"
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        log "Setting permanent swappiness..."
        echo "vm.swappiness=10" >> /etc/sysctl.conf
    fi
fi

# Configure Fish shell if installed
if [ "$SKIP_FISH" = false ]; then
    log "Setting Fish as default shell..."
    execute "chsh -s $(which fish)"
fi

log "Server setup completed successfully!"
log "System status:"
log "- Installed Packages:"
dpkg-query -W -f='${Package}\n' "${PACKAGES[@]}" 2>/dev/null
log "- Swap Configuration:"
swapon --show
log "- Default Shell: $(getent passwd root | cut -d: -f7)"

exit 0
