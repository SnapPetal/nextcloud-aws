#!/bin/bash

# Setup Cron for Nextcloud Background Jobs
# This script sets up proper cron-based background job execution

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Setting up Nextcloud cron jobs...${NC}"

# The Nextcloud Docker image already includes a cron setup internally,
# but we need to ensure it's running and the background mode is set correctly.

# Change to project directory
cd ~/nextcloud-aws || exit 1

# Set background mode to cron
echo -e "${YELLOW}Setting background job mode to cron...${NC}"
docker compose exec -u www-data app php occ background:cron

# The official Nextcloud Docker image handles cron internally via supervisord
# However, if you want to ensure cron runs from the host, add this to system crontab

# Add cron job for Nextcloud background tasks
CRON_CMD="cd /home/thonbecker/nextcloud-aws && docker compose exec -u www-data -T app php -f /var/www/html/cron.php >> /tmp/nextcloud-cron.log 2>&1"
CRON_LINE="*/5 * * * * $CRON_CMD"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "cron.php"; then
    echo -e "${BLUE}Nextcloud cron job already exists.${NC}"
else
    echo -e "${YELLOW}Adding Nextcloud cron job (runs every 5 minutes)...${NC}"
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    echo -e "${GREEN}Cron job added!${NC}"
fi

# Also add face recognition cron if Recognize app is installed
RECOGNIZE_CMD="cd /home/thonbecker/nextcloud-aws && docker compose exec -u www-data -T app php occ recognize:classify >> /tmp/recognize.log 2>&1"
RECOGNIZE_LINE="0 5 * * * $RECOGNIZE_CMD"

if crontab -l 2>/dev/null | grep -q "recognize:classify"; then
    echo -e "${BLUE}Face recognition cron job already exists.${NC}"
else
    echo -e "${YELLOW}Adding face recognition cron job (runs daily at 5 AM)...${NC}"
    (crontab -l 2>/dev/null; echo "$RECOGNIZE_LINE") | crontab -
    echo -e "${GREEN}Face recognition cron job added!${NC}"
fi

echo ""
echo -e "${GREEN}Cron setup complete!${NC}"
echo ""
echo "Current crontab:"
crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" || echo "(empty)"
echo ""
echo -e "${BLUE}Notes:${NC}"
echo "  - Nextcloud background jobs run every 5 minutes"
echo "  - Face recognition runs daily at 5 AM"
echo "  - Logs: /tmp/nextcloud-cron.log, /tmp/recognize.log"
