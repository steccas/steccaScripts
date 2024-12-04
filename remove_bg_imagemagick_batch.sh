#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-r] [-f fuzz] [-c color] [-q quality] [-t type] <input_directory> <output_directory>"
    echo "Options:"
    echo "  -h           Show this help message"
    echo "  -r           Process directories recursively"
    echo "  -f fuzz      Fuzz factor percentage (default: 10)"
    echo "  -c color     Background color to remove (default: white)"
    echo "  -q quality   Output image quality 0-100 (default: 90)"
    echo "  -t type      Output type (png/webp/transparent) (default: webp)"
    exit 1
}

# Default values
RECURSIVE=false
FUZZ=10
BG_COLOR="white"
QUALITY=90
OUTPUT_TYPE="webp"
TOTAL_FILES=0
PROCESSED_FILES=0
FAILED_FILES=0

# Parse arguments
while getopts "hrf:c:q:t:" opt; do
    case $opt in
        h)
            usage
            ;;
        r)
            RECURSIVE=true
            ;;
        f)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -gt 100 ]; then
                echo "Error: Fuzz must be a number between 0 and 100"
                exit 1
            fi
            FUZZ=$OPTARG
            ;;
        c)
            BG_COLOR="$OPTARG"
            ;;
        q)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -gt 100 ]; then
                echo "Error: Quality must be a number between 0 and 100"
                exit 1
            fi
            QUALITY=$OPTARG
            ;;
        t)
            case "$OPTARG" in
                png|webp|transparent)
                    OUTPUT_TYPE="$OPTARG"
                    ;;
                *)
                    echo "Error: Invalid output type. Must be png, webp, or transparent"
                    exit 1
                    ;;
            esac
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
    printf "\rProgress: [%-50s] %d%% (%d/%d files, %d failed)" \
        "$(printf '#%.0s' $(seq 1 $((percent/2))))" \
        "$percent" \
        "$PROCESSED_FILES" \
        "$TOTAL_FILES" \
        "$FAILED_FILES"
}

# Function to process image
process_image() {
    local input_file="$1"
    local rel_path="${input_file#$INPUT_DIR/}"
    local output_subdir="$OUTPUT_DIR/$(dirname "$rel_path")"
    local extension
    
    case "$OUTPUT_TYPE" in
        webp) extension="webp" ;;
        png) extension="png" ;;
        transparent) extension="png" ;;
    esac
    
    local output_file="$output_subdir/$(basename "${input_file%.*}").$extension"

    # Create output subdirectory if needed
    mkdir -p "$output_subdir"

    # Process image based on output type
    local cmd="magick \"$input_file\" -fuzz ${FUZZ}% -transparent \"$BG_COLOR\""
    if [ "$OUTPUT_TYPE" = "webp" ]; then
        cmd="$cmd -quality $QUALITY"
    elif [ "$OUTPUT_TYPE" = "transparent" ]; then
        cmd="$cmd -channel A -threshold 50%"
    fi
    cmd="$cmd \"$output_file\""

    if eval "$cmd" 2>/dev/null; then
        ((PROCESSED_FILES++))
        show_progress
    else
        ((FAILED_FILES++))
        echo -e "\nError processing: $input_file"
    fi
}

# Count total files
if [ "$RECURSIVE" = true ]; then
    TOTAL_FILES=$(find "$INPUT_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | wc -l)
else
    TOTAL_FILES=$(ls -1 "$INPUT_DIR"/*.{jpg,jpeg,png} 2>/dev/null | wc -l)
fi

if [ "$TOTAL_FILES" -eq 0 ]; then
    echo "No image files found in the input directory"
    exit 1
fi

echo "Background Removal Configuration:"
echo "- Input Directory: $INPUT_DIR"
echo "- Output Directory: $OUTPUT_DIR"
echo "- Recursive: $([ "$RECURSIVE" = true ] && echo "Yes" || echo "No")"
echo "- Fuzz Factor: ${FUZZ}%"
echo "- Background Color: $BG_COLOR"
echo "- Output Type: $OUTPUT_TYPE"
[ "$OUTPUT_TYPE" = "webp" ] && echo "- Quality: $QUALITY"
echo "- Total Files: $TOTAL_FILES"
echo

# Process images
if [ "$RECURSIVE" = true ]; then
    find "$INPUT_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0 | 
    while IFS= read -r -d '' file; do
        process_image "$file"
    done
else
    for ext in jpg jpeg png; do
        for file in "$INPUT_DIR"/*."$ext" "$INPUT_DIR"/*."${ext^^}"; do
            if [ -f "$file" ]; then
                process_image "$file"
            fi
        done
    done
fi

echo -e "\nProcessing completed:"
echo "- Successfully processed: $((PROCESSED_FILES)) files"
echo "- Failed: $FAILED_FILES files"
[ "$FAILED_FILES" -gt 0 ] && echo "Check the output above for error messages"

exit 0
