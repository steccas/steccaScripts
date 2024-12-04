#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-e|--export] [-i|--import] [-p|--path <backup_directory>]"
    exit 1
}

# Parse arguments
if [ $# -lt 3 ]; then
    usage
fi

MODE=""
BACKUP_DIR=""

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
        *)
            usage
            ;;
    esac
done

if [ -z "$MODE" ] || [ -z "$BACKUP_DIR" ]; then
    usage
fi

# Create backup directory if exporting
if [ "$MODE" == "export" ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="$BACKUP_DIR/backup_$TIMESTAMP"
    mkdir -p "$BACKUP_DIR"

    # Export SSH keys
    if [ -d "$HOME/.ssh" ]; then
        cp -r "$HOME/.ssh" "$BACKUP_DIR/"
    fi

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

    # Export browser profiles
    if [ -d "$HOME/.mozilla/firefox" ]; then
        cp -r "$HOME/.mozilla/firefox" "$BACKUP_DIR/"
    fi
    if [ -d "$HOME/.config/google-chrome" ]; then
        cp -r "$HOME/.config/google-chrome" "$BACKUP_DIR/"
    fi
    if [ -d "$HOME/.config/chromium" ]; then
        cp -r "$HOME/.config/chromium" "$BACKUP_DIR/"
    fi

    # Export dotfiles for tools (e.g., .tool-versions)
    if [ -f "$HOME/.tool-versions" ]; then
        cp "$HOME/.tool-versions" "$BACKUP_DIR/"
    fi

    # Export custom keybindings
    if [ -d "$HOME/.config" ]; then
        cp -r "$HOME/.config" "$BACKUP_DIR/"
    fi

    # Export package list (Pacman and AUR)
    pacman -Qqen > "$BACKUP_DIR/pkglist.txt"
    pacman -Qqem > "$BACKUP_DIR/aur_pkglist.txt"

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

    # Completion message
    echo "Backup completed successfully at $BACKUP_DIR"

elif [ "$MODE" == "import" ]; then
    # Import SSH keys
    if [ -d "$BACKUP_DIR/.ssh" ]; then
        cp -r "$BACKUP_DIR/.ssh" "$HOME/"
        chmod 700 "$HOME/.ssh"
        chmod 600 "$HOME/.ssh"/*
    fi

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

    # Completion message
    echo "Import completed successfully from $BACKUP_DIR"
else
    usage
fi
