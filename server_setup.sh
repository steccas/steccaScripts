#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-s swap_size] [-d] [-u] [-n] [-t timezone] [-l locale] [-c users_config] [-q] livepatch_token"
    echo "Options:"
    echo "  -h           Show this help message"
    echo "  -s size      Swap file size in GB (default: 8)"
    echo "  -d          Skip Docker installation"
    echo "  -u          Skip unattended-upgrades setup"
    echo "  -n          Non-interactive mode (no prompts)"
    echo "  -t timezone Set system timezone (default: Europe/Rome)"
    echo "  -l locale   Set system locale (default: en_US.UTF-8)"
    echo "  -c config   Path to YAML user configuration file"
    echo "  -q          Install and configure QEMU guest agent"
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
INSTALL_QEMU=false

# Parse command line arguments
while getopts "hs:dunt:l:c:q" opt; do
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
        q)
            INSTALL_QEMU=true
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
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
    local cmd="$1"
    local fatal="${2:-true}"  # Second parameter determines if errors are fatal, defaults to true
    
    log "Executing: $cmd"
    if ! eval "$cmd"; then
        if [ "$fatal" = "true" ]; then
            handle_error "Failed to execute: $cmd"  # This calls exit and will terminate the script
        else
            log "Warning: Failed to execute: $cmd"
        fi
        log "Debug: About to return 1 from execute function"
        return 1  # This only exits the function
    fi
    log "Debug: About to return 0 from execute function"
    return 0  # This only exits the function
}

log "Starting server setup..."
apt update && apt install yq
log "Configuration:"
log "- Swap Size: ${SWAP_SIZE}GB"
log "- Docker: $([ "$SKIP_DOCKER" = true ] && echo "Skip" || echo "Install")"
log "- Unattended Upgrades: $([ "$SKIP_UPGRADES" = true ] && echo "Skip" || echo "Configure")"
log "- Interactive: $([ "$NON_INTERACTIVE" = true ] && echo "No" || echo "Yes")"
log "- Timezone: $TIMEZONE"
log "- Locale: $LOCALE"
log "- QEMU Guest Agent: $([ "$INSTALL_QEMU" = true ] && echo "Install" || echo "Skip")"

if [ -n "$USERS_CONFIG" ]; then
    log "Users to be created:"
    user_count=$(yq '.users | length' "$USERS_CONFIG")
    if [ $? -ne 0 ] || [ -z "$user_count" ] || [ "$user_count" = "null" ]; then
        handle_error "Failed to get user count from configuration file"
    fi
    for i in $(seq 0 $((user_count - 1))); do
        username=$(yq ".users[$i].username" "$USERS_CONFIG" | tr -d '"')
        fullname=$(yq ".users[$i].full_name // \"<no full name>\"" "$USERS_CONFIG" | tr -d '"')
        groups=$(yq ".users[$i].groups[]" "$USERS_CONFIG" | tr -d '"')
        github=$(yq ".users[$i].ssh.github_username // \"<no github>\"" "$USERS_CONFIG" | tr -d '"')
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

# # Switch to dracut
# log "Switching to dracut..."
# execute "apt install -y dracut dracut-core tpm2-tools libtss2-tcti-device0 cryptsetup"

# # Configure dracut
# cat > /etc/dracut.conf << 'EOF'
# # Security modules
# add_dracutmodules+=" tpm2-tss crypt "
# EOF

# Remove initramfs-tools and generate new initramfs with dracut
# log "Generating new initramfs with dracut..."
# #execute "update-initramfs -d -k all"  # Delete all old initramfs
# execute "apt remove -y initramfs-tools initramfs-tools-core"
# execute "dracut -f --regenerate-all"  # Generate new initramfs for all kernels

# Configure grub to use dracut
#log "Updating grub configuration..."
#execute "update-grub"

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
    ssh-import-id
)

[ "$SKIP_UPGRADES" = false ] && PACKAGES+=(unattended-upgrades)
[ "$INSTALL_QEMU" = true ] && PACKAGES+=(qemu-guest-agent)

execute "apt install -y ${PACKAGES[*]}"

# Setup qemu-guest-agent if requested
if [ "$INSTALL_QEMU" = true ]; then
    log "Setting up QEMU guest agent..."
    execute "systemctl start qemu-guest-agent"
    execute "systemctl enable qemu-guest-agent"
fi

# Setup livepatch
log "Setting up Canonical Livepatch..."
execute "snap install canonical-livepatch"
execute "pro attach $LIVEPATCH_TOKEN" false
execute "canonical-livepatch status --verbose" false

# Set nano as default editor
log "Setting nano as default editor..."
execute "update-alternatives --install /usr/bin/editor editor /usr/bin/nano 100" false
execute "update-alternatives --set editor /usr/bin/nano" false

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
execute "fallocate -l ${SWAP_SIZE}G /swap.img"
execute "chmod 600 /swap.img"
execute "mkswap /swap.img"
execute "swapon /swap.img"

# Update fstab if needed
if ! grep -q "/swap.img" /etc/fstab; then
    execute "echo '/swap.img none swap sw 0 0' >> /etc/fstab"
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
execute "systemctl restart ssh"

# Function to setup a user from YAML config
setup_user() {
    local user_index=$1
    #local base_query=".users[$user_index]"
    
    # Extract required user information
    local username=$(yq ".users[$user_index].username" "$USERS_CONFIG" | tr -d '"')
    if [ -z "$username" ] || [ "$username" = "null" ]; then
        log "Error: Username is required for user at index $user_index"
        return 1
    fi
    
    # Extract optional information with defaults
    local full_name=$(yq ".users[$user_index].full_name // \"\"" "$USERS_CONFIG" | tr -d '"')
    local uid=$(yq ".users[$user_index].uid // \"\"" "$USERS_CONFIG" | tr -d '"')
    local shell=$(yq ".users[$user_index].shell // \"/bin/bash\"" "$USERS_CONFIG" | tr -d '"')
    local password=$(yq ".users[$user_index].password // \"\"" "$USERS_CONFIG" | tr -d '"') 
    
    # Log user details
    log "User details:"
    log "  - Username: $username"
    log "  - Full Name: ${full_name:-<not set>}"
    log "  - UID: ${uid:-<auto>}"
    log "  - Shell: $shell"
    log "  - Password: $([ -n "$password" ] && echo "<set>" || echo "<not set>")"
    
    if [ "$NON_INTERACTIVE" = false ]; then
        read -p "Do you want to proceed with this user setup? (y/N) " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "User setup skipped by user request"
            return 0
        fi
    fi
    
    # Check if user exists using getent which is more reliable
    local is_new_user=true
    if getent passwd "$username" >/dev/null 2>&1; then
        is_new_user=false
        log "User $username already exists, updating configuration..."
        
        # Update full name if provided
        if [ -n "$full_name" ] && [ "$full_name" != "null" ]; then
            execute "chfn -f \"$full_name\" $username" false
        fi
        
        # Update shell if provided and if it's different from current
        local current_shell=$(getent passwd "$username" | cut -d: -f7)
        if [ -n "$shell" ] && [ "$shell" != "null" ] && [ "$current_shell" != "$shell" ]; then
            log "Updating shell from $current_shell to $shell"
            execute "chsh -s \"$shell\" $username" false
        fi
    else
        log "Creating new user: $username"
        # Create new user with all options in one command
        local uid_opt=""
        [ -n "$uid" ] && [ "$uid" != "null" ] && uid_opt="-u $uid"
        local comment_opt=""
        [ -n "$full_name" ] && [ "$full_name" != "null" ] && comment_opt="-c \"$full_name\""
        
        if ! execute "useradd -m -s \"$shell\" $uid_opt $comment_opt \"$username\""; then
            log "Error: Failed to create user $username"
            return 1
        fi
    fi
    
    # Handle groups (for both new and existing users)
    local groups
    groups=$(yq ".users[$user_index].groups[]" "$USERS_CONFIG" 2>/dev/null | tr -d '"')
    if [ $? -eq 0 ] && [ -n "$groups" ] && [ "$groups" != "null" ]; then
        for group in $groups; do
            usermod -aG "$group" "$username"
        done
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

    # Setup zsh configuration (for both new and existing users)
    log "Setting up zsh for user $username..."
    
    # Clone the repo in user's home directory
    if ! execute "su - $username -c 'git clone https://github.com/steccas/steccaScripts.git'" false; then
        log "Warning: Failed to clone steccaScripts repo for user $username"
        return
    fi
    
    # Run zsh setup from the cloned repo
    if ! execute "su - $username -c './steccaScripts/zshsetup.sh -f ./steccaScripts/zsh_plugin_lists/proxmox'"; then
        log "Warning: zsh setup failed for user $username, continuing with default shell"
        execute "chsh -s /bin/bash $username" false # Fallback to bash
    fi


    # Setup SSH keys if home directory exists
    if [ -d "/home/$username" ]; then
        mkdir -p "/home/$username/.ssh"
        chmod 700 "/home/$username/.ssh"
        chown "$username:$username" "/home/$username/.ssh"
        
        # Check for GitHub username
        local github_user
        github_user=$(yq ".users[$user_index].ssh.github_username // \"\"" "$USERS_CONFIG" 2>/dev/null | tr -d '"')
        if [ $? -eq 0 ] && [ -n "$github_user" ] && [ "$github_user" != "null" ]; then
            log "Importing GitHub SSH keys for $github_user"
            if ! execute "su - $username -c \"ssh-import-id gh:$github_user\"" false; then
                log "Warning: Failed to import GitHub SSH keys for $github_user"
            fi
        else
            # Check for direct authorized_keys
            local keys
            keys=$(yq ".users[$user_index].ssh.authorized_keys[]" "$USERS_CONFIG" 2>/dev/null | tr -d '"')
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
        if ! execute "apt install yq" false; then
            log "Warning: Failed to install yq using apt. Script may fail if yq is required."
            log "Debug: Continuing after yq installation failure"
        fi
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
            username=$(yq ".users[$i].username" "$USERS_CONFIG" | tr -d '"')
            if [ -n "$username" ]; then
                log "Adding user $username to docker group..."
                execute "usermod -aG docker $username"
            fi
        done
    fi
fi

# Configure IP forwarding and network optimizations
if [ "$SKIP_DOCKER" = false ]; then
    log "Configuring IP forwarding and network optimizations..."
    
    # Create network optimization configuration file
    execute "cat > /etc/sysctl.d/99-network-tune.conf << 'EOF'
# Enable IP forwarding for Docker
net.ipv4.ip_forward=1

# Increase system IP port limits
net.ipv4.ip_local_port_range=1024 65535

# Increase TCP max buffer size
net.core.rmem_max=16777216
net.core.wmem_max=16777216

# Increase Linux autotuning TCP buffer limits
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# Enable TCP fast open
net.ipv4.tcp_fastopen=3

# Increase the maximum length of processor input queues
net.core.netdev_max_backlog=16384

# Increase the maximum number of incoming connections
net.core.somaxconn=8192

# Reuse and recycle TIME_WAIT sockets more quickly
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1

# Protection against TCP time-wait assassination
net.ipv4.tcp_rfc1337=1

# Protection against SYN flood attacks
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=8192
EOF"
    
    # Apply the changes
    execute "sysctl -p /etc/sysctl.d/99-network-tune.conf"
fi

execute ./zshsetup.sh -f ./zsh_plugin_lists/proxmox false

log "Server setup completed successfully!"
log "Please review the following:"
log "1. Check if all services are running correctly"
log "2. Verify UFW firewall rules"
log "3. Test user account and sudo access"
[ "$SKIP_DOCKER" = false ] && log "4. Verify Docker installation with: docker run hello-world"

exit 0
