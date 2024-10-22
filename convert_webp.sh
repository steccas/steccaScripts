#!/bin/bash

# Check if the user has provided input and output directory arguments
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <input_directory> <output_directory>"
  exit 1
fi

INPUT_DIR=$1
OUTPUT_DIR=$2

# Check if ImageMagick is installed
if ! command -v magick &> /dev/null
then
    echo "ImageMagick is not installed. Please install ImageMagick to proceed."
    exit 1
fi

# Process each image in the input directory
for input_image in "$INPUT_DIR"/*; do
  if [[ -f "$input_image" ]]; then
    filename=$(basename -- "$input_image")
    output_image="$OUTPUT_DIR/${filename%.*}.webp"

    # Use ImageMagick to convert to WebP
    magick "$input_image" "$output_image"

    if [ $? -eq 0 ]; then
      echo "Image converted to WebP successfully: $output_image"
    else
      echo "An error occurred during processing: $input_image"
    fi
  fi
done
