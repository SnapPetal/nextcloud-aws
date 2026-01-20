#!/bin/bash
# Setup automatic thumbnail generation for new images
# This script configures Nextcloud to automatically generate previews

echo "Setting up automatic preview generation for Nextcloud..."
echo ""

cd ~/nextcloud-aws

# Install Preview Generator app if not already installed
echo "Installing Preview Generator app..."
docker compose exec -u www-data app php occ app:install previewgenerator 2>/dev/null || echo "Preview Generator already installed"
docker compose exec -u www-data app php occ app:enable previewgenerator

echo ""
echo "Configuring preview settings..."

# Set preview sizes (optimized for photos)
docker compose exec -u www-data app php occ config:system:set preview_max_x --value=2048
docker compose exec -u www-data app php occ config:system:set preview_max_y --value=2048
docker compose exec -u www-data app php occ config:system:set jpeg_quality --value=85

# Enable preview generator for common image formats
docker compose exec -u www-data app php occ config:app:set previewgenerator squareSizes --value="32 256"
docker compose exec -u www-data app php occ config:app:set previewgenerator widthSizes --value="256 384"
docker compose exec -u www-data app php occ config:app:set previewgenerator heightSizes --value="256"

echo ""
echo "✅ Preview Generator app installed and configured!"
echo ""
echo "Now setting up automatic preview generation..."
echo ""
echo "Option 1: Add to server crontab (runs every 15 minutes for new files)"
echo "Run this on your Lightsail server:"
echo ""
echo "  crontab -e"
echo ""
echo "Add this line:"
echo "  */15 * * * * cd ~/nextcloud-aws && docker compose exec -u www-data app php occ preview:pre-generate >> /tmp/preview-generate.log 2>&1"
echo ""
echo "Option 2: Use Nextcloud's built-in cron (if configured)"
echo "The preview generator will run automatically when Nextcloud's cron runs."
echo ""
echo "To generate previews for all existing files NOW, run:"
echo "  ./scripts/generate-previews.sh"
echo ""
