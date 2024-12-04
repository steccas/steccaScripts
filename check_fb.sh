#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-i] <names_file> <leaked_files...>"
    echo "Options:"
    echo "  -h    Show this help message"
    echo "  -i    Case insensitive search"
    exit 1
}

# Parse arguments
CASE_SENSITIVE=true

while getopts "hi" opt; do
    case $opt in
        h)
            usage
            ;;
        i)
            CASE_SENSITIVE=false
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# Check for required arguments
if [ $# -lt 2 ]; then
    echo "Error: Missing required arguments"
    usage
fi

namesfile=$1
shift

# Validate input file
if [ ! -f "$namesfile" ]; then
    echo "Error: Names file '$namesfile' does not exist"
    exit 1
fi

# Check if leaked files exist
for file in "$@"; do
    if [ ! -f "$file" ]; then
        echo "Error: Leaked file '$file' does not exist"
        exit 1
    fi
done

# Read names into array
mapfile -t names < "$namesfile"

if [ ${#names[@]} -eq 0 ]; then
    echo "Error: Names file is empty"
    exit 1
fi

echo "Checking ${#names[@]} entries against ${#@} file(s)..."

# Set grep options based on case sensitivity
GREP_OPTS="--color=always"
if [ "$CASE_SENSITIVE" = false ]; then
    GREP_OPTS="$GREP_OPTS -i"
fi

# Process each name
for name in "${names[@]}"; do
    if [ -n "$name" ]; then
        echo "Checking: $name"
        cat "$@" | grep $GREP_OPTS "$name" || echo "No matches found"
    fi
done

exit 0