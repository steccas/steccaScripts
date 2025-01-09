#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-s swap_size] [-d] [-u] [-n] [-t timezone] [-l locale] [-c users_config] livepatch_token"
    echo "Options:"
    echo "  -h           Show this help message"
    echo "  -s size      Swap file size in GB (default: 8)"
    echo "  -d          Skip Docker installation"
    echo "  -u          Skip unattended-upgrades setup"
    echo "  -n          Non-interactive mode (no prompts)"
    echo "  -t timezone Set system timezone (default: Europe/Rome)"
    echo "  -l locale   Set system locale (default: en_US.UTF-8)"
    echo "  -c config   Path to YAML user configuration file"
    exit 1
}

# Default values
SWAP_SIZE=8
SKIP_DOCKER=false
SKIP_UPGRADES=false
NON_INTERACTIVE=false
TIMEZONE="Europe/Rome"
LOCALE="en_US.UTF-8"
USERS_CONFIG=""

# Parse arguments
while getopts "hs:dunt:l:c:" opt; do
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
        d)
            SKIP_DOCKER=true
            ;;
        u)
            SKIP_UPGRADES=true
            ;;
        n)
            NON_INTERACTIVE=true
            ;;
        t)
            TIMEZONE="$OPTARG"
            ;;
        l)
            LOCALE="$OPTARG"
            ;;
        c)
            USERS_CONFIG="$OPTARG"
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# Check for required arguments
if [ "$#" -ne 1 ]; then
    echo "Error: Missing required arguments"
    usage
fi

LIVEPATCH_TOKEN="$1"

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
log "- Swap Size: ${SWAP_SIZE}GB"
log "- Docker: $([ "$SKIP_DOCKER" = true ] && echo "Skip" || echo "Install")"
log "- Unattended Upgrades: $([ "$SKIP_UPGRADES" = true ] && echo "Skip" || echo "Configure")"
log "- Timezone: $TIMEZONE"
log "- Locale: $LOCALE"

if [ -n "$USERS_CONFIG" ]; then
    log "- Users to be created:"
    user_count=$(yq '.users | length' "$USERS_CONFIG")
    if [ $? -ne 0 ] || [ -z "$user_count" ] || [ "$user_count" = "null" ]; then
        handle_error "Failed to get user count from configuration file"
    fi
    for i in $(seq 0 $((user_count - 1))); do
        username=$(yq ".users[$i].username" "$USERS_CONFIG")
        fullname=$(yq ".users[$i].full_name // \"<no full name>\"" "$USERS_CONFIG")
        groups=$(yq ".users[$i].groups[]" "$USERS_CONFIG" | tr '\n' ',' | sed 's/,$//')
        github=$(yq ".users[$i].ssh.github_username // \"<no github>\"" "$USERS_CONFIG")
        log "  * $username (${fullname})"
        log "    - Groups: ${groups:-<no groups>}"
        log "    - GitHub: $github"
    done
fi

if [ "$NON_INTERACTIVE" = false ]; then
    echo
    read -p "Do you want to proceed with the installation? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Installation cancelled by user"
        exit 1
    fi
fi

# Upgrade OS
log "Upgrading system packages..."
execute "apt update && apt dist-upgrade -y"

# Configure timezone and locale
log "Configuring timezone and locale..."
if [ -n "$TIMEZONE" ]; then
    execute "timedatectl set-timezone $TIMEZONE"
fi

if [ -n "$LOCALE" ]; then
    execute "locale-gen $LOCALE"
    execute "update-locale LANG=$LOCALE"
fi

# Switch to dracut
log "Switching to dracut..."
execute "apt install -y dracut dracut-core tpm2-tools libtss2-tcti-device0 cryptsetup"

# Configure dracut
cat > /etc/dracut.conf << 'EOF'
# Security modules
add_dracutmodules+=" tpm2-tss crypt "
EOF

# Remove initramfs-tools and generate new initramfs with dracut
log "Generating new initramfs with dracut..."
execute "apt remove -y initramfs-tools initramfs-tools-core"
execute "update-initramfs -d -k all"  # Delete all old initramfs
execute "dracut -f --regenerate-all"  # Generate new initramfs for all kernels

# Configure grub to use dracut
log "Updating grub configuration..."
execute "update-grub"

# Install basic packages
log "Installing basic packages..."
PACKAGES=(
    zsh
    fail2ban
    ufw
    fonts-powerline
    apt-transport-https
    ca-certificates
    curl
    gnupg-agent
    software-properties-common
    net-tools
    iperf
    git
    build-essential
    gnupg
    lsb-release
    ntp
    nano
    micro
    wget
    git-lfs
    fzf
    cifs-utils
    nfs-common
    yq
    htop
    ncdu
)

[ "$SKIP_UPGRADES" = false ] && PACKAGES+=(unattended-upgrades)

execute "apt install -y ${PACKAGES[*]}"

# Setup livepatch
log "Setting up Canonical Livepatch..."
execute "snap install canonical-livepatch"
execute "canonical-livepatch enable $LIVEPATCH_TOKEN"
execute "canonical-livepatch status --verbose"

# Set nano as default editor
execute "update-alternatives --set editor /usr/bin/nano"

# Configure unattended-upgrades
if [ "$SKIP_UPGRADES" = false ]; then
    log "Configuring unattended-upgrades..."
    if [ "$NON_INTERACTIVE" = true ]; then
        execute "dpkg-reconfigure --priority=medium -f noninteractive unattended-upgrades"
    else
        execute "dpkg-reconfigure --priority=medium unattended-upgrades"
        
        log "Opening unattended-upgrades configuration file..."
        log "Recommended changes:"
        log "1. Uncomment '${distro_id}:${distro_codename}-updates' to enable non-security updates"
        log "2. Set 'Unattended-Upgrade::AutoFixInterruptedDpkg' to 'true' to recover from interrupted updates"
        log "3. Set 'Unattended-Upgrade::MinimalSteps' to 'true' for safer upgrades"
        log "4. Enable automatic cleanup:"
        log "   - Set 'Unattended-Upgrade::Remove-Unused-Dependencies' to 'true'"
        log "   - Set 'Unattended-Upgrade::Remove-New-Unused-Dependencies' to 'true'"
        log "5. Configure reboot behavior:"
        log "   - Set 'Unattended-Upgrade::Automatic-Reboot' based on your needs"
        log "   - Set 'Unattended-Upgrade::Automatic-Reboot-Time' if automatic reboot is enabled"
        echo "Press any key to continue..."
        read -n 1 -s
        execute "nano /etc/apt/apt.conf.d/50unattended-upgrades"
    fi
    
    log "Setting up auto-upgrades configuration..."
    execute "cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists \"1\";
APT::Periodic::Download-Upgradeable-Packages \"1\";
APT::Periodic::Unattended-Upgrade \"1\";
APT::Periodic::AutocleanInterval \"7\";
EOF"
fi

# Configure swap
log "Configuring swap (${SWAP_SIZE}GB)..."

# Remove any existing swap files
if [ -f /swapfile ]; then
    execute "swapoff /swapfile"
    execute "rm /swapfile"
fi
if [ -f /swap.img ]; then
    execute "swapoff /swap.img"
    execute "rm /swap.img"
fi

# Create and configure new swap
execute "fallocate -l ${SWAP_SIZE}G /swapfile"
execute "chmod 600 /swapfile"
execute "mkswap /swapfile"
execute "swapon /swapfile"

# Update fstab if needed
if ! grep -q "/swapfile" /etc/fstab; then
    execute "echo '/swapfile none swap sw 0 0' >> /etc/fstab"
fi

# Configure swap behavior
execute "sysctl vm.swappiness=10"
execute "sysctl vm.vfs_cache_pressure=50"

# Make sysctl settings permanent
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
    execute "echo 'vm.swappiness=10' >> /etc/sysctl.conf"
fi
if ! grep -q "vm.vfs_cache_pressure" /etc/sysctl.conf; then
    execute "echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf"
fi

# Configure firewall
log "Configuring UFW firewall..."
execute "ufw allow OpenSSH"
execute "ufw default allow routed"
if [ "$NON_INTERACTIVE" = true ]; then
    execute "ufw --force enable"
else
    execute "ufw enable"
fi

# Secure SSH configuration
log "Hardening SSH configuration..."
# Backup original config
execute "cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak"

# Configure SSH security settings
execute "sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
execute "sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config"
execute "sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config"
execute "sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config"

# Additional security measures
execute "sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/' /etc/ssh/sshd_config"
execute "sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 300/' /etc/ssh/sshd_config"
execute "sed -i 's/#ClientAliveCountMax 3/ClientAliveCountMax 2/' /etc/ssh/sshd_config"

# Validate sshd configuration
log "Validating SSH configuration..."
if ! execute "sshd -t"; then
    log "Error: SSH configuration is invalid, restoring backup..."
    execute "cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config"
    handle_error "SSH configuration validation failed"
fi

# Restart SSH service
log "Restarting SSH service..."
execute "systemctl restart sshd"

# Function to setup a user from YAML config
setup_user() {
    local user_index=$1
    local base_query=".users[$user_index]"
    
    # Extract required user information
    local username=$(yq ".users[$user_index].username" "$USERS_CONFIG")
    if [ -z "$username" ] || [ "$username" = "null" ]; then
        log "Error: Username is required for user at index $user_index"
        return 1
    fi
    
    # Extract optional information with defaults
    local full_name=$(yq ".users[$user_index].full_name // \"\"" "$USERS_CONFIG")
    local uid=$(yq ".users[$user_index].uid // \"\"" "$USERS_CONFIG")
    local shell=$(yq ".users[$user_index].shell // \"/bin/bash\"" "$USERS_CONFIG")
    local password=$(yq ".users[$user_index].password // \"\"" "$USERS_CONFIG")
    
    # Check if user exists
    local is_new_user=false
    if id "$username" >/dev/null 2>&1; then
        log "User $username already exists, updating configuration..."
        
        # Update full name if provided
        if [ -n "$full_name" ] && [ "$full_name" != "null" ]; then
            execute "chfn -f \"$full_name\" $username"
        fi
        
        # Update shell if provided
        if [ -n "$shell" ] && [ "$shell" != "null" ]; then
            execute "chsh -s \"$shell\" $username"
        fi
    else
        is_new_user=true
        # Create new user
        log "Creating user: $username"
        if [ -n "$uid" ] && [ "$uid" != "null" ]; then
            local uid_arg="-u $uid"
        else
            local uid_arg=""
        fi
        
        if [ -n "$full_name" ] && [ "$full_name" != "null" ]; then
            useradd -m $uid_arg -s "$shell" -c "$full_name" "$username"
        else
            useradd -m $uid_arg -s "$shell" "$username"
        fi
    fi
    
    # Handle groups (for both new and existing users)
    local groups
    groups=$(yq ".users[$user_index].groups[]" "$USERS_CONFIG" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$groups" ] && [ "$groups" != "null" ]; then
        for group in $groups; do
            if getent group "$group" >/dev/null; then
                usermod -aG "$group" "$username"
            else
                log "Warning: Group $group does not exist, creating it..."
                groupadd "$group"
                usermod -aG "$group" "$username"
            fi
        done
    fi

    # Setup zsh configuration (for both new and existing users)
    log "Setting up zsh for user $username..."
    local zsh_script="$(dirname $0)/zshsetup.sh"
    local zsh_plugins="$(dirname $0)/zsh_plugin_lists/proxmox"
    
    if [ ! -f "$zsh_script" ]; then
        log "Warning: $zsh_script not found, skipping zsh setup"
    elif [ ! -f "$zsh_plugins" ]; then
        log "Warning: $zsh_plugins not found, skipping zsh setup"
    else
        if ! execute "su - $username -c '$zsh_script -f $zsh_plugins'"; then
            log "Warning: zsh setup failed for user $username, continuing with default shell"
            execute "chsh -s /bin/bash $username"  # Fallback to bash
        fi
    fi

    # Set password for new users only
    if [ "$is_new_user" = true ]; then
        if [ -n "$password" ]; then
            log "Setting password for new user $username..."
            echo "$username:$password" | chpasswd
        else
            if [ "$NON_INTERACTIVE" = true ]; then
                log "Warning: No password set for user $username and running in non-interactive mode"
                # Generate a random password in non-interactive mode
                local random_pass=$(openssl rand -base64 24)
                echo "$username:$random_pass" | chpasswd
                log "Generated random password for $username: $random_pass"
                log "Please change this password immediately after setup!"
            else
                passwd "$username"
            fi
        fi
    fi

    # Setup SSH keys if home directory exists
    if [ -d "/home/$username" ]; then
        mkdir -p "/home/$username/.ssh"
        chmod 700 "/home/$username/.ssh"
        
        # Check for GitHub username
        local github_user
        github_user=$(yq ".users[$user_index].ssh.github_username // \"\"" "$USERS_CONFIG" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$github_user" ] && [ "$github_user" != "null" ]; then
            log "Fetching GitHub SSH keys for $github_user"
            if ! curl -s "https://github.com/$github_user.keys" > "/home/$username/.ssh/authorized_keys"; then
                log "Warning: Failed to fetch GitHub SSH keys for $github_user"
            fi
        else
            # Check for direct authorized_keys
            local keys
            keys=$(yq ".users[$user_index].ssh.authorized_keys[]" "$USERS_CONFIG" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$keys" ] && [ "$keys" != "null" ]; then
                echo "$keys" > "/home/$username/.ssh/authorized_keys"
                chmod 600 "/home/$username/.ssh/authorized_keys"
                chown -R "$username:$username" "/home/$username/.ssh"
            fi
        fi
    fi
}

# Configure users if config file is provided
if [ -n "$USERS_CONFIG" ]; then
    log "Configuring users from $USERS_CONFIG..."
    
    # Validate YAML file exists
    if [ ! -f "$USERS_CONFIG" ]; then
        handle_error "Users configuration file not found: $USERS_CONFIG"
    fi
    
    # Check if yq is available
    if ! command -v yq &> /dev/null; then
        log "Installing yq..."
        execute "snap install yq"
    fi
    
    # Validate YAML structure
    if ! yq '.users' "$USERS_CONFIG" >/dev/null 2>&1; then
        handle_error "Invalid YAML structure: .users array not found"
    fi
    
    # Get number of users
    user_count=$(yq '.users | length' "$USERS_CONFIG")
    if [ $? -ne 0 ] || [ -z "$user_count" ] || [ "$user_count" = "null" ]; then
        handle_error "Failed to get user count from configuration file"
    fi
    
    if [ "$user_count" -eq 0 ]; then
        log "Warning: No users defined in configuration file"
    else
        # Setup each user
        for i in $(seq 0 $((user_count - 1))); do
            if ! setup_user $i; then
                handle_error "Failed to setup user at index $i"
            fi
        done
    fi
fi

# Install Docker
if [ "$SKIP_DOCKER" = false ]; then
    log "Installing Docker..."
    
    # Ensure prerequisites are installed
    execute "apt install -y ca-certificates curl"
    
    # Setup Docker repository
    execute "install -m 0755 -d /etc/apt/keyrings"
    execute "curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc"
    execute "chmod a+r /etc/apt/keyrings/docker.asc"
    
    # Add Docker repository
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package list and install Docker
    execute "apt update"
    execute "apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
    
    # Configure system for Docker networking
    log "Configuring system for Docker networking..."
    
    # Enable IP forwarding
    execute "echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-docker.conf"
    execute "sysctl -p /etc/sysctl.d/99-docker.conf"
    
    # Configure iptables for Docker
    execute "mkdir -p /etc/docker"
    cat > /etc/docker/daemon.json << 'EOF'
{
  "iptables": true,
  "bridge": "none",
  "live-restore": true,
  "userland-proxy": false
}
EOF
    
    # Allow forwarded ports in UFW for Docker
    execute "sed -i '/DEFAULT_FORWARD_POLICY=/c\DEFAULT_FORWARD_POLICY=\"ACCEPT\"' /etc/default/ufw"
    execute "ufw reload"
    
    # Enable and start Docker service
    execute "systemctl enable docker"
    execute "systemctl start docker"
    
    # Add users to docker group if using YAML config
    if [ -n "$USERS_CONFIG" ]; then
        user_count=$(yq '.users | length' "$USERS_CONFIG")
        for i in $(seq 0 $((user_count - 1))); do
            username=$(yq ".users[$i].username" "$USERS_CONFIG")
            if [ -n "$username" ]; then
                log "Adding user $username to docker group..."
                execute "usermod -aG docker $username"
            fi
        done
    fi
fi

log "Server setup completed successfully!"
log "Please review the following:"
log "1. Check if all services are running correctly"
log "2. Verify UFW firewall rules"
log "3. Test user account and sudo access"
[ "$SKIP_DOCKER" = false ] && log "4. Verify Docker installation with: docker run hello-world"

exit 0
