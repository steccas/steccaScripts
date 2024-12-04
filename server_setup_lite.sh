#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-s swap_size] [-n] [-k] [-f] [-u] [-t] [-p]"
    echo "Options:"
    echo "  -h           Show this help message"
    echo "  -s size      Swap file size in GB (default: 6)"
    echo "  -n          Skip snapd removal"
    echo "  -k          Keep existing swap configuration"
    echo "  -f          Skip Fish shell installation"
    echo "  -u          Skip unattended-upgrades setup"
    echo "  -t          Enable automatic security updates"
    echo "  -p          Enable power management tweaks"
    exit 1
}

# Default values
SWAP_SIZE=6
SKIP_SNAPD=false
KEEP_SWAP=false
SKIP_FISH=false
SKIP_UPGRADES=false
ENABLE_AUTO_UPDATES=false
ENABLE_POWER_TWEAKS=false

# Parse arguments
while getopts "hs:nkfutp" opt; do
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
        u)
            SKIP_UPGRADES=true
            ;;
        t)
            ENABLE_AUTO_UPDATES=true
            ;;
        p)
            ENABLE_POWER_TWEAKS=true
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

# Function to configure unattended upgrades
setup_unattended_upgrades() {
    log "Setting up unattended-upgrades..."
    execute "apt install -y unattended-upgrades apt-listchanges"
    
    # Configure unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Package-Blacklist {
};
Unattended-Upgrade::DevRelease "auto";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    # Enable automatic updates if requested
    if [ "$ENABLE_AUTO_UPDATES" = true ]; then
        cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
    fi
}

# Function to configure power management
setup_power_management() {
    log "Configuring power management settings..."
    
    # Install TLP for better power management
    execute "apt install -y tlp tlp-rdw"
    execute "systemctl enable tlp"
    execute "systemctl start tlp"
    
    # Configure CPU governor
    cat > /etc/sysfs.d/99-cpu-governor.conf << EOF
devices/system/cpu/cpu*/cpufreq/scaling_governor = powersave
EOF
    
    # Configure disk I/O scheduler
    cat > /etc/udev/rules.d/60-scheduler.rules << EOF
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
EOF
}

log "Starting lite server setup..."
log "Configuration:"
log "- Swap Size: ${SWAP_SIZE}GB"
log "- Remove Snapd: $([ "$SKIP_SNAPD" = false ] && echo "Yes" || echo "No")"
log "- Configure Swap: $([ "$KEEP_SWAP" = false ] && echo "Yes" || echo "No")"
log "- Install Fish: $([ "$SKIP_FISH" = false ] && echo "Yes" || echo "No")"
log "- Setup Upgrades: $([ "$SKIP_UPGRADES" = false ] && echo "Yes" || echo "No")"
log "- Auto Updates: $([ "$ENABLE_AUTO_UPDATES" = true ] && echo "Yes" || echo "No")"
log "- Power Tweaks: $([ "$ENABLE_POWER_TWEAKS" = true ] && echo "Yes" || echo "No")"

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
    htop
    iotop
    net-tools
    nmap
    tree
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

# Configure unattended upgrades if not skipped
if [ "$SKIP_UPGRADES" = false ]; then
    setup_unattended_upgrades
fi

# Configure power management if enabled
if [ "$ENABLE_POWER_TWEAKS" = true ]; then
    setup_power_management
fi

# Configure Fish shell if installed
if [ "$SKIP_FISH" = false ]; then
    log "Setting Fish as default shell..."
    execute "chsh -s $(which fish)"
fi

# Set some useful system limits
cat >> /etc/sysctl.conf << EOF
# Increase max file handles
fs.file-max = 2097152

# Increase max number of inotify watches
fs.inotify.max_user_watches = 524288

# Optimize network settings
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_syncookies = 1
EOF

execute "sysctl -p"

log "Server setup completed successfully!"
log "System status:"
log "- Installed Packages:"
dpkg-query -W -f='${Package}\n' "${PACKAGES[@]}" 2>/dev/null
log "- Swap Configuration:"
swapon --show
log "- Default Shell: $(getent passwd root | cut -d: -f7)"
log "- System Limits:"
sysctl fs.file-max fs.inotify.max_user_watches net.core.somaxconn

exit 0
