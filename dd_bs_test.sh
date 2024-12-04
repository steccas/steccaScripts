#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-f filename] [-s size] [-m min_bs] [-x max_bs]"
    echo "Options:"
    echo "  -h           Show this help message"
    echo "  -f filename  Test file name (default: dd_obs_testfile)"
    echo "  -s size      Test file size in MB (default: 128)"
    echo "  -m min_bs    Minimum block size in bytes (default: 512)"
    echo "  -x max_bs    Maximum block size in bytes (default: 64M)"
    echo "  -c          CSV output format"
    exit 1
}

# Default values
TEST_FILE="dd_obs_testfile"
TEST_FILE_SIZE=$((128 * 1024 * 1024))  # 128MB in bytes
MIN_BLOCK_SIZE=512
MAX_BLOCK_SIZE=$((64 * 1024 * 1024))  # 64MB
CSV_OUTPUT=false

# Parse arguments
while getopts "hf:s:m:x:c" opt; do
    case $opt in
        h)
            usage
            ;;
        f)
            TEST_FILE="$OPTARG"
            ;;
        s)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                echo "Error: Size must be a number"
                exit 1
            fi
            TEST_FILE_SIZE=$((OPTARG * 1024 * 1024))
            ;;
        m)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                echo "Error: Block size must be a number"
                exit 1
            fi
            MIN_BLOCK_SIZE=$OPTARG
            ;;
        x)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                echo "Error: Block size must be a number"
                exit 1
            fi
            MAX_BLOCK_SIZE=$OPTARG
            ;;
        c)
            CSV_OUTPUT=true
            ;;
        \?)
            usage
            ;;
    esac
done

# Since we're dealing with dd, abort if any errors occur
set -e

# Check if test file already exists
TEST_FILE_EXISTS=0
if [ -e "$TEST_FILE" ]; then 
    TEST_FILE_EXISTS=1
    echo "Warning: Test file '$TEST_FILE' already exists and will be overwritten"
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled"
        exit 1
    fi
fi

# Check for root privileges
if [ $EUID -ne 0 ]; then
    echo "Warning: Kernel cache will not be cleared between tests without sudo."
    echo "This will likely cause inaccurate results."
    echo "Consider running with sudo for more accurate measurements."
    echo
fi

# Function to format sizes
format_size() {
    local size=$1
    if [ $size -ge $((1024 * 1024 * 1024)) ]; then
        echo "$(($size / 1024 / 1024 / 1024))G"
    elif [ $size -ge $((1024 * 1024)) ]; then
        echo "$(($size / 1024 / 1024))M"
    elif [ $size -ge 1024 ]; then
        echo "$(($size / 1024))K"
    else
        echo "${size}B"
    fi
}

# Print test parameters
echo "Test Parameters:"
echo "- File: $TEST_FILE"
echo "- Size: $(format_size $TEST_FILE_SIZE)"
echo "- Block size range: $(format_size $MIN_BLOCK_SIZE) to $(format_size $MAX_BLOCK_SIZE)"
echo

# Header
if [ "$CSV_OUTPUT" = true ]; then
    echo "block_size,block_size_human,transfer_rate,transfer_rate_mbps"
else
    printf "%-10s %-10s : %s\n" "Block Size" "(Human)" "Transfer Rate"
    echo "----------------------------------------"
fi

# Generate block sizes (powers of 2)
BLOCK_SIZES=()
BS=$MIN_BLOCK_SIZE
while [ $BS -le $MAX_BLOCK_SIZE ]; do
    BLOCK_SIZES+=($BS)
    BS=$((BS * 2))
done

# Perform the tests
for BLOCK_SIZE in "${BLOCK_SIZES[@]}"; do
    # Calculate number of segments required
    COUNT=$(($TEST_FILE_SIZE / $BLOCK_SIZE))

    if [ $COUNT -le 0 ]; then
        echo "Warning: Block size of $BLOCK_SIZE too large for file size, skipping."
        continue
    fi

    # Clear kernel cache if running as root
    if [ $EUID -eq 0 ] && [ -e /proc/sys/vm/drop_caches ]; then
        echo 3 > /proc/sys/vm/drop_caches
    fi

    # Create test file with specified block size
    DD_RESULT=$(dd if=/dev/zero of=$TEST_FILE bs=$BLOCK_SIZE count=$COUNT conv=fsync 2>&1 1>/dev/null)

    # Extract transfer rate
    TRANSFER_RATE=$(echo $DD_RESULT | grep --only-matching -E '[0-9.]+ ([MGk]?B|bytes)/s(ec)?')
    
    # Extract numeric value for CSV
    RATE_VALUE=$(echo $TRANSFER_RATE | grep --only-matching -E '[0-9.]+')
    RATE_UNIT=$(echo $TRANSFER_RATE | grep --only-matching -E '[MGk]?B')
    
    # Convert to MB/s for CSV
    case $RATE_UNIT in
        GB) RATE_MBS=$(echo "$RATE_VALUE * 1024" | bc) ;;
        MB) RATE_MBS=$RATE_VALUE ;;
        kB) RATE_MBS=$(echo "$RATE_VALUE / 1024" | bc) ;;
        B)  RATE_MBS=$(echo "$RATE_VALUE / 1024 / 1024" | bc) ;;
    esac

    # Output results
    if [ "$CSV_OUTPUT" = true ]; then
        echo "$BLOCK_SIZE,$(format_size $BLOCK_SIZE),$TRANSFER_RATE,$RATE_MBS"
    else
        printf "%-10s %-10s : %s\n" "$BLOCK_SIZE" "$(format_size $BLOCK_SIZE)" "$TRANSFER_RATE"
    fi

    # Clean up test file if we created it
    if [ $TEST_FILE_EXISTS -eq 0 ]; then rm $TEST_FILE; fi
done

echo
echo "Test completed successfully"
exit 0
