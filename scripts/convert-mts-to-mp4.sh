#!/bin/bash
# Convert all MTS files to MP4 format for Nextcloud
# Usage: ./convert-mts-to-mp4.sh /path/to/photos/folder

set -e

# Check if directory is provided
if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/photos/folder"
    echo "Example: $0 ~/nextcloud/photos"
    exit 1
fi

PHOTOS_DIR="$1"

# Check if directory exists
if [ ! -d "$PHOTOS_DIR" ]; then
    echo "Error: Directory $PHOTOS_DIR does not exist"
    exit 1
fi

# Check if ffmpeg is installed
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is not installed"
    echo "Install it with: sudo apt install ffmpeg -y"
    exit 1
fi

echo "=========================================="
echo "MTS to MP4 Batch Converter"
echo "=========================================="
echo ""
echo "Directory: $PHOTOS_DIR"
echo ""

# Count MTS files
total=$(find "$PHOTOS_DIR" -type f \( -iname "*.mts" \) | wc -l)

if [ "$total" -eq 0 ]; then
    echo "No MTS files found in $PHOTOS_DIR"
    exit 0
fi

echo "Found $total MTS file(s) to convert"
echo ""
echo "Settings:"
echo "  - Quality: CRF 23 (good balance of quality/size)"
echo "  - Codec: H.264 (best compatibility)"
echo "  - Audio: AAC 128kbps"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Conversion cancelled."
    exit 0
fi

echo ""
echo "Starting conversion..."
echo ""

# Counter
count=0
failed=0

# Find and convert all MTS files
find "$PHOTOS_DIR" -type f \( -iname "*.mts" \) | while read -r file; do
    count=$((count + 1))
    output="${file%.*}.mp4"

    # Skip if MP4 already exists
    if [ -f "$output" ]; then
        echo "[$count/$total] SKIP: ${file##*/} (MP4 already exists)"
        continue
    fi

    echo "[$count/$total] Converting: ${file##*/}"

    # Convert with error handling
    if ffmpeg -i "$file" -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 128k "$output" -y -loglevel error -stats; then
        # Get file sizes
        original_size=$(du -h "$file" | cut -f1)
        new_size=$(du -h "$output" | cut -f1)
        echo "  ✅ Done! $original_size → $new_size"
        echo "     Original: $file"
        echo "     Converted: $output"
    else
        echo "  ❌ Failed to convert: ${file##*/}"
        failed=$((failed + 1))
    fi

    echo ""
done

echo ""
echo "=========================================="
echo "Conversion Complete!"
echo "=========================================="
echo ""
echo "Total files: $total"
echo "Failed: $failed"
echo ""
echo "Next steps:"
echo "  1. Verify the MP4 files play correctly"
echo "  2. Delete the original MTS files to save space:"
echo "     find \"$PHOTOS_DIR\" -type f -iname \"*.mts\" -delete"
echo ""
echo "  3. Upload MP4 files to Nextcloud (if not already there)"
echo "     - Use desktop client or web interface"
echo "     - They'll play instantly in Memories app!"
echo ""
