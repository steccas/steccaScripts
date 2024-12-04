#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-s swap_size] [-p password] [-d] username livepatch_token"
    echo "Options:"
    echo "  -h           Show this help message"
    echo "  -s size      Swap file size in GB (default: 8)"
    echo "  -p password  Set user password (instead of prompt)"
    echo "  -d          Skip Docker installation"
    echo "  -f          Skip Fish shell setup"
    echo "  -u          Skip unattended-upgrades setup"
    echo "  -n          Non-interactive mode (no prompts)"
    exit 1
}

# Default values
SWAP_SIZE=8
SKIP_DOCKER=false
SKIP_FISH=false
SKIP_UPGRADES=false
NON_INTERACTIVE=false
USER_PASSWORD=""

# Parse arguments
while getopts "hs:p:dfun" opt; do
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
        p)
            USER_PASSWORD="$OPTARG"
            ;;
        d)
            SKIP_DOCKER=true
            ;;
        f)
            SKIP_FISH=true
            ;;
        u)
            SKIP_UPGRADES=true
            ;;
        n)
            NON_INTERACTIVE=true
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# Check for required arguments
if [ "$#" -ne 2 ]; then
    echo "Error: Missing required arguments"
    usage
fi

USERNAME="$1"
LIVEPATCH_TOKEN="$2"

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

log "Starting server setup..."
log "Configuration:"
log "- Username: $USERNAME"
log "- Swap Size: ${SWAP_SIZE}GB"
log "- Docker: $([ "$SKIP_DOCKER" = true ] && echo "Skip" || echo "Install")"
log "- Fish Shell: $([ "$SKIP_FISH" = true ] && echo "Skip" || echo "Install")"
log "- Unattended Upgrades: $([ "$SKIP_UPGRADES" = true ] && echo "Skip" || echo "Configure")"

# Upgrade OS
log "Upgrading system packages..."
execute "apt update && apt dist-upgrade -y"

# Install basic packages
log "Installing basic packages..."
PACKAGES=(
    fonts-powerline
    apt-transport-https
    ca-certificates
    curl
    gnupg-agent
    software-properties-common
    cifs-utils
    nfs-common
    net-tools
    iperf
    git
    build-essential
    gnupg
    lsb-release
)

[ "$SKIP_FISH" = false ] && PACKAGES+=(fish)
[ "$SKIP_UPGRADES" = false ] && PACKAGES+=(unattended-upgrades)

execute "apt install -y ${PACKAGES[*]}"

# Setup livepatch
log "Setting up Canonical Livepatch..."
execute "snap install canonical-livepatch"
execute "ua attach $LIVEPATCH_TOKEN"
execute "ua enable livepatch"

# Configure unattended-upgrades
if [ "$SKIP_UPGRADES" = false ]; then
    log "Configuring unattended-upgrades..."
    if [ "$NON_INTERACTIVE" = false ]; then
        nano /etc/apt/apt.conf.d/50unattended-upgrades
    else
        cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Package-Blacklist {
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
    fi
fi

# Configure swap
log "Configuring swap (${SWAP_SIZE}GB)..."
execute "swapoff -a"
[ -f /swap.img ] && execute "rm /swap.img"
[ -f /swapfile ] && execute "rm /swapfile"
execute "fallocate -l ${SWAP_SIZE}G /swapfile"
execute "chmod 600 /swapfile"
execute "mkswap /swapfile"
execute "swapon /swapfile"
grep -q "/swapfile" /etc/fstab || echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
execute "sysctl vm.swappiness=10"
grep -q "vm.swappiness" /etc/sysctl.conf || echo "vm.swappiness=10" >> /etc/sysctl.conf

# Configure firewall
log "Configuring UFW firewall..."
execute "ufw allow openssh"
execute "ufw --force enable"

# Add user
log "Creating user: $USERNAME..."
if [ -n "$USER_PASSWORD" ]; then
    echo "$USERNAME:$USER_PASSWORD" | chpasswd
else
    adduser $USERNAME
fi

# Install Docker
if [ "$SKIP_DOCKER" = false ]; then
    log "Installing Docker..."
    execute "mkdir -p /etc/apt/keyrings"
    execute "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    execute "apt update"
    execute "apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
    execute "usermod -aG docker $USERNAME"
fi

# Configure Fish shell
if [ "$SKIP_FISH" = false ]; then
    log "Configuring Fish shell..."
    execute "chsh -s $(which fish)"
    execute "sudo -u $USERNAME chsh -s $(which fish)"
    execute "sudo -u $USERNAME fish -c 'curl -L https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish'"
    execute "sudo -u $USERNAME fish -c 'omf install bobthefish'"
    execute "chown -R $USERNAME:$USERNAME /home/$USERNAME/.config/"
fi

log "Server setup completed successfully!"
log "Please review the following:"
log "1. Check if all services are running correctly"
log "2. Verify UFW firewall rules"
log "3. Test user account and sudo access"
[ "$SKIP_DOCKER" = false ] && log "4. Verify Docker installation with: docker run hello-world"
[ "$SKIP_FISH" = false ] && log "5. Start a new shell to use Fish"

exit 0
