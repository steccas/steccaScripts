#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-e|--export] [-i|--import] [-p|--path <backup_directory>] [--no-packages] [--no-services]"
    echo "Options:"
    echo "  -e, --export       Export mode"
    echo "  -i, --import       Import mode"
    echo "  -p, --path PATH    Backup directory path"
    echo "  --no-packages      Skip package installation during import"
    echo "  --no-services      Skip systemd service activation during import"
    echo
    echo "Example: $0 --import --path /path/to/backup --no-packages"
    exit 1
}

# Parse arguments
if [ $# -lt 3 ]; then
    usage
fi

MODE=""
BACKUP_DIR=""
SKIP_PACKAGES=false
SKIP_SERVICES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--export)
            MODE="export"
            shift
            ;;
        -i|--import)
            MODE="import"
            shift
            ;;
        -p|--path)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --no-packages)
            SKIP_PACKAGES=true
            shift
            ;;
        --no-services)
            SKIP_SERVICES=true
            shift
            ;;
        *)
            usage
            ;;
    esac
done

if [ -z "$MODE" ] || [ -z "$BACKUP_DIR" ]; then
    usage
fi

# Function to backup application data
backup_app_data() {
    local app_name="$1"
    local source_path="$2"
    local backup_path="$BACKUP_DIR/$app_name"
    
    if [ -e "$source_path" ]; then
        echo "Backing up $app_name..."
        mkdir -p "$backup_path"
        cp -r "$source_path/." "$backup_path/"
        echo "$app_name backup completed"
    else
        echo "Warning: $app_name directory not found at $source_path"
    fi
}

# Function to restore application data
restore_app_data() {
    local app_name="$1"
    local target_path="$2"
    local backup_path="$BACKUP_DIR/$app_name"
    
    if [ -d "$backup_path" ]; then
        echo "Restoring $app_name..."
        mkdir -p "$target_path"
        cp -r "$backup_path/." "$target_path/"
        echo "$app_name restore completed"
    else
        echo "Warning: No backup found for $app_name"
    fi
}

# Create backup directory if exporting
if [ "$MODE" == "export" ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="$BACKUP_DIR/backup_$TIMESTAMP"
    mkdir -p "$BACKUP_DIR"

    # Export SSH keys
    if [ -d "$HOME/.ssh" ]; then
        cp -r "$HOME/.ssh" "$BACKUP_DIR/"
    fi

    # Backup Windsurf data
    backup_app_data "windsurf" "$HOME/.config/windsurf"

    # Backup Brave data
    backup_app_data "brave" "$HOME/.config/BraveSoftware/Brave-Browser"

    # Backup Ledger Live data
    backup_app_data "ledger_live" "$HOME/.config/Ledger Live"

    # Export package list
    pacman -Qqe > "$BACKUP_DIR/pacman_packages.txt"
    pacman -Qqem > "$BACKUP_DIR/aur_packages.txt"

    # Export systemd services
    systemctl list-unit-files --state=enabled --user > "$BACKUP_DIR/systemd_user_services.txt"
    sudo systemctl list-unit-files --state=enabled > "$BACKUP_DIR/systemd_system_services.txt"

    # Export GPG keys
    gpg --export-secret-keys -o "$BACKUP_DIR/gpg-backup.asc"

    # Export Git configuration
    if [ -f "$HOME/.gitconfig" ]; then
        cp "$HOME/.gitconfig" "$BACKUP_DIR/"
    fi

    # Export Oh My Zsh configuration
    if [ -f "$HOME/.zshrc" ]; then
        cp "$HOME/.zshrc" "$BACKUP_DIR/"
    fi
    if [ -d "$HOME/.oh-my-zsh" ]; then
        cp -r "$HOME/.oh-my-zsh" "$BACKUP_DIR/"
    fi

    # Export custom scripts in ~/bin
    if [ -d "$HOME/bin" ]; then
        cp -r "$HOME/bin" "$BACKUP_DIR/"
    fi

    # Export aliases and functions
    if [ -f "$HOME/.bash_aliases" ]; then
        cp "$HOME/.bash_aliases" "$BACKUP_DIR/"
    fi
    if [ -f "$HOME/.zsh_custom" ]; then
        cp "$HOME/.zsh_custom" "$BACKUP_DIR/"
    fi

    # Export cron jobs
    crontab -l > "$BACKUP_DIR/cron_jobs_backup.txt"

    # Export application configurations
    if [ -d "$HOME/.config" ]; then
        cp -r "$HOME/.config" "$BACKUP_DIR/"
    fi

    # Export custom fonts
    if [ -d "$HOME/.fonts" ]; then
        cp -r "$HOME/.fonts" "$BACKUP_DIR/"
    fi

    # Export VS Code settings and extensions
    if [ -d "$HOME/.config/Code/User" ]; then
        mkdir -p "$BACKUP_DIR/vscode"
        cp "$HOME/.config/Code/User/settings.json" "$BACKUP_DIR/vscode/"
        code --list-extensions > "$BACKUP_DIR/vscode/vscode_extensions_list.txt"
    fi

    # Export Windsurf settings and extensions
    if [ -d "$HOME/.config/windsurf" ]; then
        mkdir -p "$BACKUP_DIR/windsurf"
        rsync -a --exclude 'Cache' --exclude 'CachedData' --exclude 'GPUCache' "$HOME/.config/windsurf/" "$BACKUP_DIR/windsurf/"
        windsurf --list-extensions > "$BACKUP_DIR/windsurf/extensions_list.txt"
    fi

    # Export browser profiles
    if [ -d "$HOME/.mozilla/firefox" ]; then
        mkdir -p "$BACKUP_DIR/.mozilla/firefox"
        rsync -a --exclude 'cache2' --exclude 'startupCache' "$HOME/.mozilla/firefox/" "$BACKUP_DIR/.mozilla/firefox/"
    fi
    if [ -d "$HOME/.config/google-chrome" ]; then
        mkdir -p "$BACKUP_DIR/google-chrome"
        rsync -a --exclude 'Cache' --exclude 'GPUCache' "$HOME/.config/google-chrome/" "$BACKUP_DIR/google-chrome/"
    fi
    if [ -d "$HOME/.config/chromium" ]; then
        mkdir -p "$BACKUP_DIR/chromium"
        rsync -a --exclude 'Cache' --exclude 'GPUCache' "$HOME/.config/chromium/" "$BACKUP_DIR/chromium/"
    fi
    if [ -d "$HOME/.config/BraveSoftware/Brave-Browser" ]; then
        mkdir -p "$BACKUP_DIR/brave"
        rsync -a --exclude 'Cache' --exclude 'GPUCache' --exclude 'Code Cache' "$HOME/.config/BraveSoftware/Brave-Browser/" "$BACKUP_DIR/brave/"
    fi

    # Export Ledger Live settings
    if [ -d "$HOME/.config/Ledger Live" ]; then
        mkdir -p "$BACKUP_DIR/ledger-live"
        rsync -a --exclude 'Cache' --exclude 'GPUCache' "$HOME/.config/Ledger Live/" "$BACKUP_DIR/ledger-live/"
    fi

    # Export dotfiles for tools (e.g., .tool-versions)
    if [ -f "$HOME/.tool-versions" ]; then
        cp "$HOME/.tool-versions" "$BACKUP_DIR/"
    fi

    # Export custom keybindings
    if [ -d "$HOME/.config" ]; then
        cp -r "$HOME/.config" "$BACKUP_DIR/"
    fi

    # Export Docker configurations (if applicable)
    if [ -d "$HOME/.docker" ]; then
        cp -r "$HOME/.docker" "$BACKUP_DIR/"
    fi

    # Export network settings
    if [ -d "$HOME/.netctl" ]; then
        cp -r "$HOME/.netctl" "$BACKUP_DIR/"
    fi

    # Export OpenRGB profiles and configuration
    if [ -d "$HOME/.config/OpenRGB" ]; then
        cp -r "$HOME/.config/OpenRGB" "$BACKUP_DIR/"
    fi

    echo "Backup completed successfully at $BACKUP_DIR"

elif [ "$MODE" == "import" ]; then
    # Import SSH keys
    if [ -d "$BACKUP_DIR/.ssh" ]; then
        cp -r "$BACKUP_DIR/.ssh" "$HOME/"
        chmod 700 "$HOME/.ssh"
        chmod 600 "$HOME/.ssh/"*
    fi

    # Restore Windsurf data
    restore_app_data "windsurf" "$HOME/.config/windsurf"

    # Restore Brave data
    restore_app_data "brave" "$HOME/.config/BraveSoftware/Brave-Browser"

    # Restore Ledger Live data
    restore_app_data "ledger_live" "$HOME/.config/Ledger Live"

    # Import GPG keys
    if [ -f "$BACKUP_DIR/gpg-backup.asc" ]; then
        gpg --import "$BACKUP_DIR/gpg-backup.asc"
    fi

    # Import Git configuration
    if [ -f "$BACKUP_DIR/.gitconfig" ]; then
        cp "$BACKUP_DIR/.gitconfig" "$HOME/"
    fi

    # Import Oh My Zsh configuration
    if [ -f "$BACKUP_DIR/.zshrc" ]; then
        cp "$BACKUP_DIR/.zshrc" "$HOME/"
    fi
    if [ -d "$BACKUP_DIR/.oh-my-zsh" ]; then
        cp -r "$BACKUP_DIR/.oh-my-zsh" "$HOME/"
    fi

    # Import custom scripts in ~/bin
    if [ -d "$BACKUP_DIR/bin" ]; then
        cp -r "$BACKUP_DIR/bin" "$HOME/"
    fi

    # Import aliases and functions
    if [ -f "$BACKUP_DIR/.bash_aliases" ]; then
        cp "$BACKUP_DIR/.bash_aliases" "$HOME/"
    fi
    if [ -f "$BACKUP_DIR/.zsh_custom" ]; then
        cp "$BACKUP_DIR/.zsh_custom" "$HOME/"
    fi

    # Import cron jobs
    if [ -f "$BACKUP_DIR/cron_jobs_backup.txt" ]; then
        crontab "$BACKUP_DIR/cron_jobs_backup.txt"
    fi

    # Import application configurations
    if [ -d "$BACKUP_DIR/.config" ]; then
        cp -r "$BACKUP_DIR/.config" "$HOME/"
    fi

    # Import custom fonts
    if [ -d "$BACKUP_DIR/.fonts" ]; then
        cp -r "$BACKUP_DIR/.fonts" "$HOME/"
    fi

    # Import VS Code settings and extensions
    if [ -d "$BACKUP_DIR/vscode" ]; then
        if [ -f "$BACKUP_DIR/vscode/settings.json" ]; then
            mkdir -p "$HOME/.config/Code/User"
            cp "$BACKUP_DIR/vscode/settings.json" "$HOME/.config/Code/User/"
        fi
        if [ -f "$BACKUP_DIR/vscode/vscode_extensions_list.txt" ]; then
            xargs -n 1 code --install-extension < "$BACKUP_DIR/vscode/vscode_extensions_list.txt"
        fi
    fi

    # Import Windsurf settings and extensions
    if [ -d "$BACKUP_DIR/windsurf" ]; then
        echo "Restoring Windsurf configuration..."
        mkdir -p "$HOME/.config/windsurf"
        cp -r "$BACKUP_DIR/windsurf/." "$HOME/.config/windsurf/"
        if [ -f "$BACKUP_DIR/windsurf/extensions_list.txt" ]; then
            echo "Restoring Windsurf extensions..."
            while read -r extension; do
                windsurf --install-extension "$extension"
            done < "$BACKUP_DIR/windsurf/extensions_list.txt"
        fi
    fi

    # Import browser profiles
    if [ -d "$BACKUP_DIR/.mozilla" ]; then
        cp -r "$BACKUP_DIR/.mozilla" "$HOME/"
    fi
    if [ -d "$BACKUP_DIR/google-chrome" ]; then
        cp -r "$BACKUP_DIR/google-chrome" "$HOME/.config/"
    fi
    if [ -d "$BACKUP_DIR/chromium" ]; then
        cp -r "$BACKUP_DIR/chromium" "$HOME/.config/"
    fi
    if [ -d "$BACKUP_DIR/brave" ]; then
        echo "Restoring Brave Browser profile..."
        mkdir -p "$HOME/.config/BraveSoftware/Brave-Browser"
        cp -r "$BACKUP_DIR/brave/." "$HOME/.config/BraveSoftware/Brave-Browser/"
    fi

    # Import Ledger Live settings
    if [ -d "$BACKUP_DIR/ledger-live" ]; then
        echo "Restoring Ledger Live configuration..."
        mkdir -p "$HOME/.config/Ledger Live"
        cp -r "$BACKUP_DIR/ledger-live/." "$HOME/.config/Ledger Live/"
    fi

    # Import dotfiles for tools (e.g., .tool-versions)
    if [ -f "$BACKUP_DIR/.tool-versions" ]; then
        cp "$BACKUP_DIR/.tool-versions" "$HOME/"
    fi

    # Import Docker configurations
    if [ -d "$BACKUP_DIR/.docker" ]; then
        cp -r "$BACKUP_DIR/.docker" "$HOME/"
    fi

    # Import network settings
    if [ -d "$BACKUP_DIR/.netctl" ]; then
        cp -r "$BACKUP_DIR/.netctl" "$HOME/"
    fi

    # Import OpenRGB profiles and configuration
    if [ -d "$BACKUP_DIR/.config/OpenRGB" ]; then
        mkdir -p "$HOME/.config/OpenRGB"
        cp -r "$BACKUP_DIR/.config/OpenRGB" "$HOME/.config/"
    fi

    # Install packages if they exist in backup and not skipped
    if [ "$SKIP_PACKAGES" = false ]; then
        if [ -f "$BACKUP_DIR/pacman_packages.txt" ]; then
            echo "Installing official packages..."
            sudo pacman -S --needed - < "$BACKUP_DIR/pacman_packages.txt"
        fi

        if [ -f "$BACKUP_DIR/aur_packages.txt" ]; then
            echo "Installing AUR packages..."
            if command -v yay >/dev/null 2>&1; then
                yay -S --needed - < "$BACKUP_DIR/aur_packages.txt"
            else
                echo "Warning: yay not found. Please install AUR packages manually."
            fi
        fi
    else
        echo "Skipping package installation (--no-packages flag set)"
    fi

    # Enable systemd services if not skipped
    if [ "$SKIP_SERVICES" = false ]; then
        if [ -f "$BACKUP_DIR/systemd_user_services.txt" ]; then
            echo "Enabling user systemd services..."
            while read -r service; do
                systemctl enable --user "$service"
            done < "$BACKUP_DIR/systemd_user_services.txt"
        fi

        if [ -f "$BACKUP_DIR/systemd_system_services.txt" ]; then
            echo "Enabling system systemd services..."
            while read -r service; do
                sudo systemctl enable "$service"
            done < "$BACKUP_DIR/systemd_system_services.txt"
        fi
    else
        echo "Skipping systemd service activation (--no-services flag set)"
    fi

    echo "Restore completed successfully"
fi
