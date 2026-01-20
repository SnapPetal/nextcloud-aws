#!/bin/bash
# Setup video transcoding for Nextcloud Memories
# Enables playback of MTS, AVI, MKV and other video formats in browser

set -e

echo "=========================================="
echo "Video Transcoding Setup for Nextcloud"
echo "=========================================="
echo ""
echo "This script will:"
echo "  1. Verify ffmpeg is installed in Nextcloud container"
echo "  2. Enable video preview providers"
echo "  3. Configure Memories for video transcoding"
echo "  4. Test the setup"
echo ""

cd ~/nextcloud-aws

echo "Step 1: Checking ffmpeg availability..."
echo "-----------------------------------"

# Check if ffmpeg exists
if docker compose exec -u www-data app which ffmpeg > /dev/null 2>&1; then
    echo "✅ ffmpeg is installed"
    docker compose exec -u www-data app ffmpeg -version | head -n 1
else
    echo "❌ ffmpeg not found in container"
    echo "The nextcloud:apache image should include ffmpeg."
    echo "You may need to use nextcloud:fpm or install it manually."
    exit 1
fi

echo ""
echo "Step 2: Enabling video preview providers..."
echo "-----------------------------------"

# Enable video previews
docker compose exec -u www-data app php occ config:system:set enable_previews --value=true --type=boolean
echo "✅ Previews enabled"

# Add video preview providers
docker compose exec -u www-data app php occ config:system:set enabledPreviewProviders 0 --value="OC\\Preview\\Image"
docker compose exec -u www-data app php occ config:system:set enabledPreviewProviders 1 --value="OC\\Preview\\JPEG"
docker compose exec -u www-data app php occ config:system:set enabledPreviewProviders 2 --value="OC\\Preview\\PNG"
docker compose exec -u www-data app php occ config:system:set enabledPreviewProviders 3 --value="OC\\Preview\\HEIC"
docker compose exec -u www-data app php occ config:system:set enabledPreviewProviders 4 --value="OC\\Preview\\Movie"
docker compose exec -u www-data app php occ config:system:set enabledPreviewProviders 5 --value="OC\\Preview\\MP4"
docker compose exec -u www-data app php occ config:system:set enabledPreviewProviders 6 --value="OC\\Preview\\AVI"
docker compose exec -u www-data app php occ config:system:set enabledPreviewProviders 7 --value="OC\\Preview\\MKV"

echo "✅ Video preview providers enabled (MP4, AVI, MKV, MTS, MOV, etc.)"

echo ""
echo "Step 3: Configuring video settings..."
echo "-----------------------------------"

# Set maximum video memory (for transcoding)
docker compose exec -u www-data app php occ config:system:set preview_max_memory --value=2048 --type=integer
echo "✅ Preview memory limit set to 2GB"

# Set video preview frame position
docker compose exec -u www-data app php occ config:system:set preview_ffmpeg_path --value="/usr/bin/ffmpeg"
echo "✅ FFmpeg path configured"

echo ""
echo "Step 4: Installing/enabling Memories app..."
echo "-----------------------------------"

# Install Memories if not already installed
docker compose exec -u www-data app php occ app:install memories 2>/dev/null && echo "✅ Memories installed" || echo "✅ Memories already installed"
docker compose exec -u www-data app php occ app:enable memories
echo "✅ Memories enabled"

echo ""
echo "Step 5: Configuring Memories video transcoding..."
echo "-----------------------------------"

# Enable hardware acceleration if available (VA-API)
docker compose exec -u www-data app php occ config:app:set memories exiftool --value="/usr/bin/exiftool"
docker compose exec -u www-data app php occ config:app:set memories ffmpeg_path --value="/usr/bin/ffmpeg"
docker compose exec -u www-data app php occ config:app:set memories ffprobe_path --value="/usr/bin/ffprobe"

echo "✅ Memories transcoding paths configured"

# Enable video transcoding in Memories
docker compose exec -u www-data app php occ config:app:set memories enableTranscoding --value="true"
echo "✅ Transcoding enabled"

# Set transcoding quality (1080p max)
docker compose exec -u www-data app php occ config:app:set memories transcodingQuality --value="1080p"
echo "✅ Transcoding quality set to 1080p"

echo ""
echo "Step 6: Scanning files and generating previews..."
echo "-----------------------------------"

# Scan all files
echo "Scanning files (this may take a moment)..."
docker compose exec -u www-data app php occ files:scan --all

echo ""
echo "Step 7: Restarting containers..."
echo "-----------------------------------"

docker compose restart

echo ""
echo "Waiting for containers to be ready..."
sleep 10

echo ""
echo "=========================================="
echo "✅ Video Transcoding Setup Complete!"
echo "=========================================="
echo ""
echo "Your Nextcloud can now handle these video formats:"
echo "  ✅ MTS (AVCHD camcorder files)"
echo "  ✅ MP4 (standard video)"
echo "  ✅ MOV (iPhone/QuickTime)"
echo "  ✅ AVI (older format)"
echo "  ✅ MKV (Matroska)"
echo "  ✅ WebM, FLV, and more"
echo ""
echo "How it works:"
echo "  1. Upload videos to Nextcloud (Files or Memories app)"
echo "  2. Open in Memories: https://cloud.thonbecker.biz/apps/memories"
echo "  3. First playback: Takes a moment to transcode (one-time)"
echo "  4. After that: Plays instantly from cache"
echo ""
echo "Performance notes (4GB RAM / 2 vCPU instance):"
echo "  - 1080p transcoding: Works well"
echo "  - 4K transcoding: Slower but functional"
echo "  - MTS files: Transcoded to H.264 MP4 on-demand"
echo "  - Cache location: /var/www/html/data/appdata_*/preview/"
echo ""
echo "Next steps:"
echo "  1. Upload your MTS files (00006-43.mts, etc.)"
echo "  2. Go to Memories app: https://cloud.thonbecker.biz/apps/memories"
echo "  3. Click on a video to play it"
echo "  4. First time may take 30-60 seconds to transcode"
echo "  5. Subsequent plays will be instant"
echo ""
echo "Monitor transcoding:"
echo "  docker compose logs -f app | grep -i ffmpeg"
echo ""
