#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-o output_file] [-v]"
    echo "Options:"
    echo "  -h          Show this help message"
    echo "  -o file     Output file path (default: ./cf_real-ip.conf)"
    echo "  -v          Verbose output"
    echo
    echo "Example: $0 -o /etc/nginx/conf.d/cf_real-ip.conf"
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

# Default values
OUTPUT_FILE="./cf_real-ip.conf"
VERBOSE=false

# Parse arguments
while getopts "ho:v" opt; do
    case $opt in
        h)
            usage
            ;;
        o)
            OUTPUT_FILE="$OPTARG"
            ;;
        v)
            VERBOSE=true
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# Check if curl is installed
if ! command -v curl &>/dev/null; then
    log ERROR "curl is not installed. Please install curl to proceed."
    exit 1
fi

log INFO "Fetching Cloudflare IP ranges..."
log INFO "Output file: $OUTPUT_FILE"

# Create temporary file
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Fetch IPv4 ranges
log INFO "Fetching IPv4 ranges..."
IPV4_RANGES=$(curl -s "https://www.cloudflare.com/ips-v4")
if [ $? -ne 0 ] || [ -z "$IPV4_RANGES" ]; then
    log ERROR "Failed to fetch IPv4 ranges from Cloudflare"
    exit 1
fi

# Fetch IPv6 ranges
log INFO "Fetching IPv6 ranges..."
IPV6_RANGES=$(curl -s "https://www.cloudflare.com/ips-v6")
if [ $? -ne 0 ] || [ -z "$IPV6_RANGES" ]; then
    log ERROR "Failed to fetch IPv6 ranges from Cloudflare"
    exit 1
fi

# Generate configuration file
log INFO "Generating configuration file..."
{
    echo "$IPV4_RANGES" | while read -r ip; do
        [ -n "$ip" ] && echo "set_real_ip_from $ip;"
    done
    echo "$IPV6_RANGES" | while read -r ip; do
        [ -n "$ip" ] && echo "set_real_ip_from $ip;"
    done
} > "$TEMP_FILE"

# Verify the file was created and has content
if [ ! -s "$TEMP_FILE" ]; then
    log ERROR "Failed to generate configuration file"
    exit 1
fi

# Create output directory if it doesn't exist
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
if [ ! -d "$OUTPUT_DIR" ]; then
    log INFO "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    if [ $? -ne 0 ]; then
        log ERROR "Failed to create output directory: $OUTPUT_DIR"
        exit 1
    fi
fi

# Move temp file to final location
mv "$TEMP_FILE" "$OUTPUT_FILE"
if [ $? -ne 0 ]; then
    log ERROR "Failed to write to output file: $OUTPUT_FILE"
    exit 1
fi

# Display results
IP_COUNT=$(wc -l < "$OUTPUT_FILE")
log INFO "Configuration file generated successfully!"
log INFO "Total IP ranges: $IP_COUNT"

if [ "$VERBOSE" = true ]; then
    log INFO "Configuration file contents:"
    cat "$OUTPUT_FILE"
fi

exit 0