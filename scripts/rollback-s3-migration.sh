#!/bin/bash

# Rollback S3 Migration
# Use this if the migration fails and you need to restore local storage

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/nextcloud-aws || exit 1

echo -e "${YELLOW}S3 Migration Rollback${NC}"
echo ""

# Find the most recent backup
BACKUP_DIR=$(ls -td /mnt/nextcloud-data/backups/pre-s3-migration-* 2>/dev/null | head -1)

if [[ -z "$BACKUP_DIR" ]]; then
    echo -e "${RED}No backup found!${NC}"
    echo "Looking for backups in /mnt/nextcloud-data/backups/"
    ls -la /mnt/nextcloud-data/backups/ 2>/dev/null || echo "No backups directory"
    exit 1
fi

echo "Found backup: $BACKUP_DIR"
echo ""

read -p "Restore from this backup? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${YELLOW}Enabling maintenance mode...${NC}"
docker compose exec -u www-data app php occ maintenance:mode --on || true

echo -e "${YELLOW}Restoring config.php...${NC}"
sudo cp "$BACKUP_DIR/config.php" /mnt/nextcloud-data/nextcloud/config/config.php
sudo chown www-data:www-data /mnt/nextcloud-data/nextcloud/config/config.php

echo -e "${YELLOW}Restarting Nextcloud...${NC}"
docker compose restart app

echo -e "${YELLOW}Waiting for Nextcloud to start...${NC}"
sleep 10

echo -e "${YELLOW}Disabling maintenance mode...${NC}"
docker compose exec -u www-data app php occ maintenance:mode --off || true

echo ""
echo -e "${GREEN}Rollback complete!${NC}"
echo ""
echo "Your Nextcloud should now be using local storage again."
echo "Test by logging in and checking your files."
