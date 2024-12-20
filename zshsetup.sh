#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-v] [-n] [-t THEME] [-p PLUGINS...]"
    echo "Options:"
    echo "  -h          Show this help message"
    echo "  -v          Verbose output"
    echo "  -n          No backup (skip backing up existing configurations)"
    echo "  -t THEME    Specify oh-my-zsh theme (default: 'robbyrussell')"
    echo "  -p PLUGINS  Specify additional plugins (space-separated list)"
    echo
    echo "Example: $0 -v -t agnoster -p 'git docker kubectl'"
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

# Function to backup existing configuration
backup_config() {
    local backup_dir="$HOME/.zsh_backup_$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$HOME/.zshrc" ]; then
        log INFO "Backing up existing .zshrc to $backup_dir"
        mkdir -p "$backup_dir"
        cp "$HOME/.zshrc" "$backup_dir/"
    fi
    
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log INFO "Backing up existing oh-my-zsh to $backup_dir"
        cp -r "$HOME/.oh-my-zsh" "$backup_dir/"
    fi
}

# Function to install dependencies
install_dependencies() {
    log INFO "Installing required packages..."
    
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y zsh git curl wget nano
    elif command -v yum >/dev/null 2>&1; then
        sudo yum -y install zsh git curl wget nano
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm zsh git curl wget nano
    else
        log ERROR "Unsupported package manager. Please install zsh, git, curl, wget, and nano manually."
        exit 1
    fi
}

# Function to install oh-my-zsh
install_oh_my_zsh() {
    log INFO "Installing oh-my-zsh..."
    
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log WARN "oh-my-zsh is already installed"
        return
    fi
    
    # Install oh-my-zsh
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    
    if [ $? -ne 0 ]; then
        log ERROR "Failed to install oh-my-zsh"
        exit 1
    fi
}

# Function to install plugins
install_plugins() {
    local plugins=($@)
    local custom_plugins_dir="$HOME/.oh-my-zsh/custom/plugins"
    
    # Install zsh-autosuggestions
    if [ ! -d "$custom_plugins_dir/zsh-autosuggestions" ]; then
        log INFO "Installing zsh-autosuggestions..."
        git clone https://github.com/zsh-users/zsh-autosuggestions "$custom_plugins_dir/zsh-autosuggestions"
    fi
    
    # Install zsh-syntax-highlighting
    if [ ! -d "$custom_plugins_dir/zsh-syntax-highlighting" ]; then
        log INFO "Installing zsh-syntax-highlighting..."
        git clone https://github.com/zsh-users/zsh-syntax-highlighting "$custom_plugins_dir/zsh-syntax-highlighting"
    fi
    
    # Install zsh-completions
    if [ ! -d "$custom_plugins_dir/zsh-completions" ]; then
        log INFO "Installing zsh-completions..."
        git clone https://github.com/zsh-users/zsh-completions "$custom_plugins_dir/zsh-completions"
    fi
    
    # Install zsh-history-substring-search
    if [ ! -d "$custom_plugins_dir/zsh-history-substring-search" ]; then
        log INFO "Installing zsh-history-substring-search..."
        git clone https://github.com/zsh-users/zsh-history-substring-search "$custom_plugins_dir/zsh-history-substring-search"
    fi
    
    # Add custom plugins to .zshrc
    local plugin_list="git zsh-autosuggestions zsh-syntax-highlighting zsh-completions zsh-history-substring-search ${plugins[@]}"
    sed -i "s/plugins=(git)/plugins=($plugin_list)/" "$HOME/.zshrc"
}

# Function to configure theme
configure_theme() {
    local theme=$1
    log INFO "Setting theme to $theme..."
    sed -i "s/ZSH_THEME=\"robbyrussell\"/ZSH_THEME=\"$theme\"/" "$HOME/.zshrc"
}

# Default values
VERBOSE=false
NO_BACKUP=false
THEME="robbyrussell"
PLUGINS=()

# Parse arguments
while getopts "hvnt:p:" opt; do
    case $opt in
        h)
            usage
            ;;
        v)
            VERBOSE=true
            ;;
        n)
            NO_BACKUP=true
            ;;
        t)
            THEME="$OPTARG"
            ;;
        p)
            IFS=' ' read -r -a PLUGINS <<< "$OPTARG"
            ;;
        \?)
            usage
            ;;
    esac
done

# Main installation process
log INFO "Starting zsh setup..."

# Backup existing configuration
if [ "$NO_BACKUP" = false ]; then
    backup_config
fi

# Install dependencies
install_dependencies

# Install oh-my-zsh
install_oh_my_zsh

# Install and configure plugins
install_plugins "${PLUGINS[@]}"

# Configure theme
configure_theme "$THEME"

# Set zsh as default shell
if [ "$SHELL" != "$(which zsh)" ]; then
    log INFO "Setting zsh as default shell..."
    chsh -s "$(which zsh)"
fi

# Add custom configurations
cat >> "$HOME/.zshrc" << 'EOL'

# Custom aliases
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# History configuration
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# Key bindings
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
EOL

log INFO "zsh setup completed successfully!"
log INFO "Please restart your terminal or run 'zsh' to start using your new shell"

echo "Press any key to proceed..."

# Loop until a key is pressed
while true; do
read -rsn1 key  # Read a single character silently
if [[ -n "$key" ]]; then
nano .zshrc
exit 0
