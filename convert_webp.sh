#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-r] [-q quality] <input_directory> <output_directory>"
    echo "Options:"
    echo "  -h           Show this help message"
    echo "  -r           Process directories recursively"
    echo "  -q quality   WebP quality (0-100, default: 75)"
    exit 1
}

# Default values
RECURSIVE=false
QUALITY=75
TOTAL_FILES=0
PROCESSED_FILES=0

# Parse arguments
while getopts "hrq:" opt; do
    case $opt in
        h)
            usage
            ;;
        r)
            RECURSIVE=true
            ;;
        q)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -lt 0 ] || [ "$OPTARG" -gt 100 ]; then
                echo "Error: Quality must be a number between 0 and 100"
                exit 1
            fi
            QUALITY=$OPTARG
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# Check for required arguments
if [ "$#" -ne 2 ]; then
    echo "Error: Missing required arguments"
    usage
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"

# Validate directories
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' does not exist"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Check if ImageMagick is installed
if ! command -v magick &> /dev/null; then
    echo "Error: ImageMagick is not installed. Please install ImageMagick to proceed."
    exit 1
fi

# Function to show progress
show_progress() {
    local percent=$((100 * PROCESSED_FILES / TOTAL_FILES))
    printf "\rProgress: [%-50s] %d%% (%d/%d files)" \
        "$(printf '#%.0s' $(seq 1 $((percent/2))))" \
        "$percent" \
        "$PROCESSED_FILES" \
        "$TOTAL_FILES"
}

# Function to process images
process_image() {
    local input_file="$1"
    local rel_path="${input_file#$INPUT_DIR/}"
    local output_subdir="$OUTPUT_DIR/$(dirname "$rel_path")"
    local output_file="$output_subdir/$(basename "${input_file%.*}").webp"

    # Create output subdirectory if needed
    mkdir -p "$output_subdir"

    # Convert image
    if magick "$input_file" -quality "$QUALITY" "$output_file" 2>/dev/null; then
        ((PROCESSED_FILES++))
        show_progress
    else
        echo -e "\nError processing: $input_file"
    fi
}

# Count total files
if [ "$RECURSIVE" = true ]; then
    TOTAL_FILES=$(find "$INPUT_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) | wc -l)
else
    TOTAL_FILES=$(ls -1 "$INPUT_DIR"/*.{jpg,jpeg,png,gif} 2>/dev/null | wc -l)
fi

if [ "$TOTAL_FILES" -eq 0 ]; then
    echo "No image files found in the input directory"
    exit 1
fi

echo "Converting $TOTAL_FILES files to WebP format (quality: $QUALITY)"
echo "From: $INPUT_DIR"
echo "To: $OUTPUT_DIR"
echo

# Process images
if [ "$RECURSIVE" = true ]; then
    find "$INPUT_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) -print0 | 
    while IFS= read -r -d '' file; do
        process_image "$file"
    done
else
    for ext in jpg jpeg png gif; do
        for file in "$INPUT_DIR"/*."$ext" "$INPUT_DIR"/*."${ext^^}"; do
            if [ -f "$file" ]; then
                process_image "$file"
            fi
        done
    done
fi

echo -e "\nConversion completed: $PROCESSED_FILES files processed"
exit 0
