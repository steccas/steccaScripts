#!/usr/bin/env fish

# Function to display usage
function show_help
    echo "Usage: "(status filename)" [-h] [-l locale]"
    echo "Options:"
    echo "  -h         Show this help message"
    echo "  -l locale  Set specific locale (default: en_US.UTF-8)"
    exit 1
end

# Parse arguments
set -l options 'h' 'l:'
argparse $options -- $argv
or begin
    show_help
    exit 1
end

if set -ql _flag_h
    show_help
end

# Set default locale
set -l locale "en_US.UTF-8"

# Override locale if specified
if set -ql _flag_l
    set locale $_flag_l
end

# Check if locale exists
if not locale -a | grep -q "^$locale\$"
    echo "Error: Locale '$locale' is not available on this system"
    echo "Available locales:"
    locale -a
    exit 1
end

# Backup existing config
set -l config_file ~/.config/fish/config.fish
if test -f $config_file
    cp $config_file $config_file.backup
    echo "Backup created at $config_file.backup"
end

# Update locale settings
echo "Setting locale to $locale..."
set -Ux LC_ALL $locale
set -Ux LC_CTYPE $locale
set -Ux LANG $locale

# Verify settings
echo "Current locale settings:"
echo "LC_ALL: $LC_ALL"
echo "LC_CTYPE: $LC_CTYPE"
echo "LANG: $LANG"

echo "Font settings updated successfully"
echo "Please restart your fish shell for changes to take effect"

exit 0
