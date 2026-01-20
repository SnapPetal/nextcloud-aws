#!/bin/bash
# Rebuild Nextcloud container with ffmpeg support for video transcoding

set -e

echo "=========================================="
echo "Rebuilding Nextcloud with ffmpeg Support"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Build a custom Nextcloud image with ffmpeg"
echo "  2. Stop current containers"
echo "  3. Start new containers with video support"
echo "  4. Verify ffmpeg is installed"
echo ""
echo "⚠️  This will cause ~2-3 minutes of downtime"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Rebuild cancelled."
    exit 1
fi

cd ~/nextcloud-aws

echo ""
echo "Step 1: Building custom Nextcloud image with ffmpeg..."
echo "-----------------------------------"
echo "This may take 5-10 minutes on first build..."
echo ""

# Build the custom image
docker compose build --no-cache app

echo ""
echo "✅ Custom image built successfully"

echo ""
echo "Step 2: Stopping current containers..."
echo "-----------------------------------"

docker compose down

echo "✅ Containers stopped"

echo ""
echo "Step 3: Starting new containers with ffmpeg..."
echo "-----------------------------------"

docker compose up -d

echo "✅ Containers started"

echo ""
echo "Step 4: Waiting for Nextcloud to be ready..."
echo "-----------------------------------"

sleep 15

# Wait for healthcheck
echo "Waiting for healthcheck to pass..."
for i in {1..30}; do
    if docker compose exec -T app curl -f http://localhost/status.php > /dev/null 2>&1; then
        echo "✅ Nextcloud is ready"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

echo ""
echo "Step 5: Verifying ffmpeg installation..."
echo "-----------------------------------"

if docker compose exec -u www-data app which ffmpeg > /dev/null 2>&1; then
    echo "✅ ffmpeg is installed!"
    docker compose exec -u www-data app ffmpeg -version | head -n 1
else
    echo "❌ ffmpeg not found - something went wrong"
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ Rebuild Complete!"
echo "=========================================="
echo ""
echo "Your Nextcloud now has ffmpeg installed for video transcoding."
echo ""
echo "Next steps:"
echo "  1. Run the video transcoding setup:"
echo "     ./scripts/setup-video-transcoding.sh"
echo ""
echo "  2. Test by playing an MTS video in Memories app:"
echo "     https://cloud.thonbecker.biz/apps/memories"
echo ""
echo "Note: Future 'docker compose up -d' will use the cached custom image."
echo "      To rebuild from scratch, use: docker compose build --no-cache app"
echo ""
