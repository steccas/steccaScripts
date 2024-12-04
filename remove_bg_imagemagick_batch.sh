#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-r] [-f fuzz] [-c color] [-q quality] [-t type] [-p threads] [-s] <input_directory> <output_directory>"
    echo "Options:"
    echo "  -h           Show this help message"
    echo "  -r           Process directories recursively"
    echo "  -f fuzz      Fuzz factor percentage (default: 10)"
    echo "  -c color     Background color to remove (default: white)"
    echo "  -q quality   Output image quality 0-100 (default: 90)"
    echo "  -t type      Output type (png/webp/transparent) (default: webp)"
    echo "  -p threads   Number of parallel threads (default: number of CPU cores)"
    echo "  -s           Skip existing files"
    exit 1
}

# Default values
RECURSIVE=false
FUZZ=10
BG_COLOR="white"
QUALITY=90
OUTPUT_TYPE="webp"
PARALLEL_THREADS=$(nproc)
SKIP_EXISTING=false
TOTAL_FILES=0
PROCESSED_FILES=0
FAILED_FILES=0
SKIPPED_FILES=0
START_TIME=$(date +%s)

# Parse arguments
while getopts "hrf:c:q:t:p:s" opt; do
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
        p)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -lt 1 ]; then
                echo "Error: Number of threads must be a positive number"
                exit 1
            fi
            PARALLEL_THREADS=$OPTARG
            ;;
        s)
            SKIP_EXISTING=true
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

# Function to format time
format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d:%02d" $hours $minutes $secs
}

# Function to format file size
format_size() {
    local size=$1
    local units=("B" "KB" "MB" "GB")
    local unit=0
    
    while ((size > 1024 && unit < 3)); do
        size=$((size / 1024))
        ((unit++))
    done
    
    echo "$size${units[$unit]}"
}

# Function to show progress
show_progress() {
    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    local percent=$((100 * PROCESSED_FILES / TOTAL_FILES))
    local remaining_files=$((TOTAL_FILES - PROCESSED_FILES))
    local files_per_second=$(bc <<< "scale=2; $PROCESSED_FILES / ($elapsed + 0.01)")
    local estimated_remaining=$((remaining_files / (files_per_second + 0.01)))
    
    printf "\rProgress: [%-50s] %d%% (%d/%d files, %d failed, %d skipped)" \
        "$(printf '#%.0s' $(seq 1 $((percent/2))))" \
        "$percent" \
        "$PROCESSED_FILES" \
        "$TOTAL_FILES" \
        "$FAILED_FILES" \
        "$SKIPPED_FILES"
    printf "\nElapsed: %s, Estimated remaining: %s, Speed: %.1f files/sec" \
        "$(format_time $elapsed)" \
        "$(format_time $estimated_remaining)" \
        "$files_per_second"
    printf "\033[A\r"
}

# Function to process image
process_image() {
    local input_file="$1"
    local output_file="$2"
    local output_dir=$(dirname "$output_file")
    
    mkdir -p "$output_dir"
    
    if [ "$SKIP_EXISTING" = true ] && [ -f "$output_file" ]; then
        ((SKIPPED_FILES++))
        return 0
    fi
    
    local input_size=$(stat -f%z "$input_file" 2>/dev/null || stat -c%s "$input_file")
    
    case "$OUTPUT_TYPE" in
        transparent)
            magick "$input_file" -fuzz "$FUZZ%" -transparent "$BG_COLOR" "$output_file"
            ;;
        webp)
            magick "$input_file" -fuzz "$FUZZ%" -transparent "$BG_COLOR" -quality "$QUALITY" "${output_file%.*}.webp"
            ;;
        png)
            magick "$input_file" -fuzz "$FUZZ%" -transparent "$BG_COLOR" "${output_file%.*}.png"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        local output_size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file")
        local reduction=$(bc <<< "scale=2; 100 - ($output_size * 100 / $input_size)")
        echo "Processed: $input_file"
        echo "Size reduction: ${reduction}% ($(format_size $input_size) → $(format_size $output_size))"
        ((PROCESSED_FILES++))
    else
        echo "Failed to process: $input_file"
        ((FAILED_FILES++))
    fi
    
    show_progress
}

export -f process_image format_size
export FUZZ BG_COLOR QUALITY OUTPUT_TYPE SKIP_EXISTING PROCESSED_FILES FAILED_FILES SKIPPED_FILES

# Count total files
if [ "$RECURSIVE" = true ]; then
    TOTAL_FILES=$(find "$INPUT_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | wc -l)
else
    TOTAL_FILES=$(ls -1 "$INPUT_DIR"/*.{jpg,jpeg,png} 2>/dev/null | wc -l)
fi

if [ "$TOTAL_FILES" -eq 0 ]; then
    echo "No image files found in $INPUT_DIR"
    exit 1
fi

echo "Starting batch processing..."
echo "Configuration:"
echo "- Input directory: $INPUT_DIR"
echo "- Output directory: $OUTPUT_DIR"
echo "- Recursive: $RECURSIVE"
echo "- Fuzz factor: $FUZZ%"
echo "- Background color: $BG_COLOR"
echo "- Quality: $QUALITY"
echo "- Output type: $OUTPUT_TYPE"
echo "- Parallel threads: $PARALLEL_THREADS"
echo "- Skip existing: $SKIP_EXISTING"
echo "- Total files to process: $TOTAL_FILES"
echo

# Process images in parallel
if [ "$RECURSIVE" = true ]; then
    find "$INPUT_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0 | \
        parallel -0 -j "$PARALLEL_THREADS" process_image {} "$OUTPUT_DIR"/{/.}."$OUTPUT_TYPE"
else
    ls -1 "$INPUT_DIR"/*.{jpg,jpeg,png} 2>/dev/null | \
        parallel -j "$PARALLEL_THREADS" process_image {} "$OUTPUT_DIR"/{/.}."$OUTPUT_TYPE"
fi

# Final statistics
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
echo -e "\n\nProcessing completed!"
echo "Summary:"
echo "- Total files processed: $PROCESSED_FILES"
echo "- Failed: $FAILED_FILES"
echo "- Skipped: $SKIPPED_FILES"
echo "- Total time: $(format_time $TOTAL_TIME)"
echo "- Average speed: $(bc <<< "scale=2; $PROCESSED_FILES / $TOTAL_TIME") files/sec"

exit 0
