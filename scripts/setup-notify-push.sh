#!/bin/bash

# Setup Notify Push (Client Push) for Nextcloud
# Provides real-time updates to desktop and mobile clients

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/nextcloud-aws || exit 1

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}   Nextcloud Notify Push Setup${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Function to run occ commands
occ() {
    docker compose exec -u www-data app php occ "$@"
}

# Check if notify_push is installed
echo -e "${YELLOW}Checking notify_push app status...${NC}"
if ! occ app:list | grep -q "notify_push"; then
    echo -e "${YELLOW}Installing notify_push app...${NC}"
    occ app:install notify_push
fi

occ app:enable notify_push

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${YELLOW}Nginx Configuration Required${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Add the following to your Nginx configuration"
echo "(usually /etc/nginx/sites-available/nextcloud):"
echo ""
echo -e "${GREEN}# Client Push (notify_push)${NC}"
echo "location ^~ /push/ {"
echo "    proxy_pass http://127.0.0.1:7867/;"
echo "    proxy_http_version 1.1;"
echo "    proxy_set_header Upgrade \$http_upgrade;"
echo "    proxy_set_header Connection \"Upgrade\";"
echo "    proxy_set_header Host \$host;"
echo "    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
echo "    proxy_read_timeout 86400s;"
echo "}"
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${YELLOW}Docker Compose Update Required${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "The notify_push binary needs to run as a separate service."
echo "This requires updating docker-compose.yml to add the notify_push container."
echo ""
echo "Would you like to update docker-compose.yml automatically? (y/n)"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${RED}Note: notify_push requires additional setup that's complex for Docker.${NC}"
    echo -e "${YELLOW}For a simpler alternative, you can skip this and Nextcloud will${NC}"
    echo -e "${YELLOW}fall back to polling (slightly higher resource usage but works fine).${NC}"
    echo ""
    echo -e "${BLUE}Recommended: Skip notify_push for now unless you have many desktop clients.${NC}"
fi

echo ""
echo -e "${GREEN}Setup information displayed.${NC}"
echo "For full documentation, see:"
echo "https://github.com/nextcloud/notify_push"
