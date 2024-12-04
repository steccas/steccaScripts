#!/usr/bin/env fish

# Function to display usage
function show_help
    echo "Usage: "(status filename)" [-h] [-l locale] [-f font] [-t theme] [-r] [-b]"
    echo "Options:"
    echo "  -h         Show this help message"
    echo "  -l locale  Set specific locale (default: en_US.UTF-8)"
    echo "  -f font    Set specific font (default: 'MesloLGS NF')"
    echo "  -t theme   Set color theme (default: 'Dracula')"
    echo "  -r        Restore from backup if available"
    echo "  -b        Create backup only without making changes"
    exit 1
end

# Function to log messages
function log -a level message
    set -l timestamp (date '+%Y-%m-%d %H:%M:%S')
    switch $level
        case INFO
            echo "[$timestamp] INFO: $message"
        case WARN
            echo "[$timestamp] WARNING: $message" >&2
        case ERROR
            echo "[$timestamp] ERROR: $message" >&2
        case '*'
            echo "[$timestamp] $message"
    end
end

# Parse arguments
set -l options 'h' 'l:' 'f:' 't:' 'r' 'b'
argparse $options -- $argv
or begin
    show_help
    exit 1
end

if set -ql _flag_h
    show_help
end

# Default values
set -l locale "en_US.UTF-8"
set -l font "MesloLGS NF"
set -l theme "Dracula"
set -l restore false
set -l backup_only false

# Override defaults with provided arguments
if set -ql _flag_l
    set locale $_flag_l
end

if set -ql _flag_f
    set font $_flag_f
end

if set -ql _flag_t
    set theme $_flag_t
end

if set -ql _flag_r
    set restore true
end

if set -ql _flag_b
    set backup_only true
end

# Check if fish shell is being used
if not string match -q "*fish*" $SHELL
    log ERROR "This script must be run in fish shell"
    exit 1
end

# Check if locale exists
if not locale -a | grep -q "^$locale\$"
    log ERROR "Locale '$locale' is not available on this system"
    echo "Available locales:"
    locale -a
    exit 1
end

# Check if font is installed
if not fc-list | grep -qi "$font"
    log WARN "Font '$font' is not installed. You may need to install it manually"
end

# Configuration paths
set -l config_dir ~/.config/fish
set -l config_file $config_dir/config.fish
set -l backup_file $config_file.backup
set -l functions_dir $config_dir/functions
set -l completions_dir $config_dir/completions

# Create necessary directories
mkdir -p $functions_dir $completions_dir

# Backup existing configuration
if test -f $config_file
    if not test -f $backup_file
        cp $config_file $backup_file
        log INFO "Backup created at $backup_file"
    else
        log WARN "Backup file already exists, skipping backup"
    end
end

# If backup only mode, exit here
if test $backup_only = true
    log INFO "Backup completed. No changes made"
    exit 0
end

# If restore mode, restore from backup
if test $restore = true
    if test -f $backup_file
        cp $backup_file $config_file
        log INFO "Configuration restored from backup"
        exit 0
    else
        log ERROR "No backup file found at $backup_file"
        exit 1
    end
end

# Update locale settings
log INFO "Setting locale to $locale..."
set -Ux LC_ALL $locale
set -Ux LC_CTYPE $locale
set -Ux LANG $locale

# Configure font and theme
log INFO "Configuring font and theme..."
cat > $config_file << EOF
# Locale settings
set -gx LC_ALL $locale
set -gx LC_CTYPE $locale
set -gx LANG $locale

# Font configuration
set -g theme_powerline_fonts yes
set -g theme_nerd_fonts yes
set -g fish_prompt_pwd_dir_length 0
set -g theme_display_user yes
set -g theme_display_hostname yes
set -g theme_display_cmd_duration yes
set -g theme_show_exit_status yes
set -g theme_git_worktree_support yes
set -g theme_display_git yes
set -g theme_display_git_dirty yes
set -g theme_display_git_untracked yes
set -g theme_display_git_ahead_verbose yes
set -g theme_display_git_dirty_verbose yes
set -g theme_display_git_stashed_verbose yes
set -g theme_display_git_default_branch yes
set -g theme_git_default_branches master main

# Theme settings
set -g fish_prompt_pwd_dir_length 1
set -g theme_color_scheme $theme
set -g theme_display_date yes
set -g theme_display_cmd_duration yes
set -g theme_title_display_process yes
set -g theme_title_display_path yes
set -g theme_title_use_abbreviated_path yes
set -g theme_date_format "+%Y-%m-%d %H:%M:%S"
set -g theme_avoid_ambiguous_glyphs yes
set -g theme_powerline_fonts yes
set -g theme_nerd_fonts yes
set -g theme_show_exit_status yes
set -g theme_display_jobs_verbose yes

# Custom key bindings
function fish_user_key_bindings
    bind \cr 'history-search-backward'
    bind \cf 'forward-char'
    bind \cb 'backward-char'
end

# Set default terminal font
if test -n "$TMUX"
    printf '\ePtmux;\e\e]50;%s\a\e\\' "xft:$font:size=10"
else
    printf '\e]50;%s\a' "xft:$font:size=10"
end
EOF

# Create fish_prompt function
cat > $functions_dir/fish_prompt.fish << 'EOF'
function fish_prompt --description 'Write out the prompt'
    set -l last_status $status
    set -l normal (set_color normal)
    set -l status_color (set_color brgreen)
    set -l cwd_color (set_color $fish_color_cwd)
    set -l vcs_color (set_color brpurple)
    set -l prompt_status ""

    # Show last status if not successful
    if test $last_status -ne 0
        set status_color (set_color $fish_color_error)
        set prompt_status "[$last_status]"
    end

    # Show username and hostname
    echo -n -s (set_color brblue) "$USER" @ (prompt_hostname) $normal " "
    
    # Show current directory
    echo -n -s $cwd_color (prompt_pwd) $normal
    
    # Show git status if available
    set -l git_info
    if command -sq git
        set -l git_branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if test -n "$git_branch"
            set git_info "$vcs_color($git_branch)$normal"
            
            # Check for modified files
            if not git diff --quiet 2>/dev/null
                set git_info "$git_info*"
            end
            
            # Check for untracked files
            if test -n (git ls-files --others --exclude-standard 2>/dev/null)
                set git_info "$git_info+"
            end
            
            echo -n -s " " $git_info
        end
    end

    # Show prompt symbol
    echo -n -s $status_color $prompt_status " ➜ " $normal
end
EOF

# Source the new configuration
source $config_file

log INFO "Fish shell configuration completed successfully!"
log INFO "Changes made:"
log INFO "- Set locale to $locale"
log INFO "- Configured font to $font"
log INFO "- Applied $theme color scheme"
log INFO "- Created custom prompt with git integration"
log INFO "- Added key bindings for better navigation"
log INFO "- Backup saved at $backup_file"

echo
log INFO "Please restart your shell or run 'source $config_file' to apply changes"

exit 0
