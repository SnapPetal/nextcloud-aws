#!/bin/bash
# Update server with latest changes from GitHub

set -e

echo "=========================================="
echo "Updating Nextcloud Server"
echo "=========================================="
echo ""

cd ~/nextcloud-aws

echo "Step 1: Pulling latest code from GitHub..."
echo "-----------------------------------"
git pull origin main
echo "✅ Code updated"

echo ""
echo "Step 2: Restarting containers..."
echo "-----------------------------------"
docker compose down
docker compose up -d

echo ""
echo "Step 3: Waiting for Nextcloud to be ready..."
echo "-----------------------------------"
sleep 10

# Wait for healthcheck
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
echo "=========================================="
echo "✅ Server Updated Successfully!"
echo "=========================================="
echo ""
echo "Your Nextcloud is now running with:"
echo "  - Official nextcloud:apache image (simplified)"
echo "  - No ffmpeg complexity"
echo "  - Ready for MP4 videos"
echo ""
echo "Access your Nextcloud:"
echo "  https://cloud.thonbecker.biz"
echo ""
echo "For MTS videos:"
echo "  - Convert to MP4 using HandBrake: https://handbrake.fr/"
echo "  - Then upload the MP4 files"
echo "  - They'll play instantly!"
echo ""
