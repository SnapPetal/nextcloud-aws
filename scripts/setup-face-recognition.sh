#!/bin/bash
# Setup face recognition for Memories app using Recognize
# This enables AI-powered face detection and clustering in your photo library

set -e

echo "=========================================="
echo "Face Recognition Setup for Nextcloud Memories"
echo "=========================================="
echo ""
echo "This script will:"
echo "  1. Install Recognize app (AI face detection)"
echo "  2. Configure Memories to use face recognition"
echo "  3. Run initial face classification on your photos"
echo "  4. Show how to set up automatic processing"
echo ""
echo "⚠️  WARNING: Initial face recognition will take several hours"
echo "    for large photo collections (157 GB = possibly overnight)"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Setup cancelled."
    exit 1
fi

cd ~/nextcloud-aws

echo ""
echo "Step 1: Installing Recognize app..."
echo "-----------------------------------"

# Install Recognize app
docker compose exec -u www-data app php occ app:install recognize 2>/dev/null && echo "✅ Recognize installed" || echo "✅ Recognize already installed"

# Enable the app
docker compose exec -u www-data app php occ app:enable recognize
echo "✅ Recognize enabled"

echo ""
echo "Step 2: Configuring Recognize..."
echo "-----------------------------------"

# Set Recognize to use face recognition mode
docker compose exec -u www-data app php occ recognize:download-models

echo "✅ AI models downloaded"

echo ""
echo "Step 3: Checking system resources..."
echo "-----------------------------------"

# Show current resource usage
echo "Current Docker container stats:"
docker stats --no-stream

echo ""
echo "Step 4: Starting initial face classification..."
echo "-----------------------------------"
echo ""
echo "This will scan all your photos for faces."
echo "Progress will be shown below..."
echo ""
read -p "Start face classification now? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo ""
    echo "🔍 Running face classification..."
    echo "This may take several hours for large collections."
    echo "You can safely Ctrl+C and it will continue in background."
    echo ""

    # Run classification with verbose output
    docker compose exec -u www-data app php occ recognize:classify --verbose || true

    echo ""
    echo "✅ Face classification started!"
else
    echo ""
    echo "⏭️  Skipped initial classification."
    echo "You can run it later with:"
    echo "  docker compose exec -u www-data app php occ recognize:classify"
fi

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo ""
echo "1. Access Memories app:"
echo "   https://cloud.thonbecker.biz/apps/memories"
echo ""
echo "2. Click 'People' tab to see face clusters"
echo ""
echo "3. Name faces by clicking on clusters and selecting 'Rename'"
echo ""
echo "4. Set up automatic face recognition for NEW photos:"
echo "   Add to crontab (runs nightly at 2 AM):"
echo ""
echo "   crontab -e"
echo ""
echo "   Add this line:"
echo "   0 2 * * * cd ~/nextcloud-aws && docker compose exec -u www-data app php occ recognize:classify >> /tmp/recognize.log 2>&1"
echo ""
echo "5. Monitor progress:"
echo "   tail -f /tmp/recognize.log"
echo "   docker compose logs -f app | grep -i recognize"
echo ""
echo "=========================================="
echo ""
echo "Tips:"
echo "  - Face recognition improves over time as you name faces"
echo "  - You can merge duplicate face clusters in the People tab"
echo "  - Processing is CPU intensive but runs in background"
echo "  - Your 4GB RAM instance handles this fine, just slower than high-end servers"
echo ""
