#!/bin/bash
# Generate previews for all photos and videos
# This significantly improves photo browsing performance

echo "Generating previews for all files..."
echo "This may take a while for large photo collections."
echo ""

cd ~/nextcloud-aws

# Generate previews for all files
docker compose exec -u www-data app php occ preview:generate-all -vvv

echo ""
echo "Preview generation complete!"
echo ""
echo "For ongoing preview generation, you can add this to cron:"
echo "0 3 * * * cd ~/nextcloud-aws && docker compose exec -u www-data app php occ preview:pre-generate"
