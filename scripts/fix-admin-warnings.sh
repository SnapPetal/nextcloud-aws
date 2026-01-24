#!/bin/bash

# Fix Nextcloud Admin Warnings
# Addresses common administration issues reported in the admin panel

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Change to project directory
cd ~/nextcloud-aws || exit 1

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}   Nextcloud Admin Warnings Fix${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Function to run occ commands
occ() {
    docker compose exec -u www-data app php occ "$@"
}

# 1. Set default phone region
echo -e "${YELLOW}1. Setting default phone region to US...${NC}"
occ config:system:set default_phone_region --value="US"
echo -e "${GREEN}   Done!${NC}"
echo ""

# 2. Set maintenance window (3 AM UTC - during low usage hours)
echo -e "${YELLOW}2. Setting maintenance window start time (3 AM UTC)...${NC}"
occ config:system:set maintenance_window_start --type=integer --value=3
echo -e "${GREEN}   Done!${NC}"
echo ""

# 3. Add missing database indices
echo -e "${YELLOW}3. Adding missing database indices...${NC}"
occ db:add-missing-indices
echo -e "${GREEN}   Done!${NC}"
echo ""

# 4. Run mimetype migrations
echo -e "${YELLOW}4. Running mimetype migrations (this may take a while)...${NC}"
occ maintenance:repair --include-expensive
echo -e "${GREEN}   Done!${NC}"
echo ""

# 5. Set up background jobs to use cron
echo -e "${YELLOW}5. Setting background jobs to use cron...${NC}"
occ background:cron
echo -e "${GREEN}   Done!${NC}"
echo ""

# 6. Install and configure Client Push (notify_push)
echo -e "${YELLOW}6. Installing Client Push (notify_push) app...${NC}"
if occ app:list | grep -q "notify_push"; then
    echo -e "${BLUE}   notify_push already installed, enabling...${NC}"
    occ app:enable notify_push || true
else
    occ app:install notify_push || echo -e "${YELLOW}   Could not install notify_push - may need manual installation${NC}"
fi
echo -e "${GREEN}   Done!${NC}"
echo ""

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}   Basic fixes completed!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "${YELLOW}Manual steps still needed:${NC}"
echo ""
echo -e "1. ${BLUE}Email Configuration:${NC}"
echo "   Go to Administration Settings > Basic settings"
echo "   Configure SMTP server (e.g., AWS SES, Gmail, etc.)"
echo ""
echo -e "2. ${BLUE}AppAPI Deploy Daemon:${NC}"
echo "   This requires Docker socket access for the container."
echo "   If you need External Apps (Ex-Apps), run:"
echo "   ./scripts/setup-appapi.sh"
echo ""
echo -e "3. ${BLUE}High-performance Backend (Nextcloud Talk):${NC}"
echo "   Only needed if you use video calls with 3+ participants."
echo "   Requires separate signaling server setup."
echo "   See: https://github.com/strukturag/nextcloud-spreed-signaling"
echo ""
echo -e "4. ${BLUE}Client Push (notify_push):${NC}"
echo "   If installed, you need to configure the reverse proxy."
echo "   Run: ./scripts/setup-notify-push.sh"
echo ""
echo -e "5. ${BLUE}Error Logs:${NC}"
echo "   Check logs with: docker compose logs app | grep -i error"
echo "   Or use the maintenance menu: ./scripts/maintenance.sh"
echo ""
