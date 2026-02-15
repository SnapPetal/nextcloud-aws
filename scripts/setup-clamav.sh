#!/bin/bash

# ClamAV Setup for Nextcloud
# Enables and configures the files_antivirus app to use the ClamAV container

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/nextcloud-aws || exit 1

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}   ClamAV Antivirus Setup${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Wait for ClamAV to be healthy
echo -e "${YELLOW}Checking ClamAV container health...${NC}"
RETRIES=0
MAX_RETRIES=30
while [ $RETRIES -lt $MAX_RETRIES ]; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' nextcloud-clamav 2>/dev/null || echo "not found")
    if [ "$STATUS" = "healthy" ]; then
        echo -e "${GREEN}ClamAV is healthy and ready${NC}"
        break
    fi
    echo "  ClamAV status: ${STATUS} (attempt $((RETRIES + 1))/${MAX_RETRIES})"
    RETRIES=$((RETRIES + 1))
    sleep 10
done

if [ "$STATUS" != "healthy" ]; then
    echo -e "${RED}ClamAV is not healthy after ${MAX_RETRIES} attempts.${NC}"
    echo "Check container logs: docker compose logs clamav"
    exit 1
fi

# Install and enable the antivirus app
echo -e "${YELLOW}Installing files_antivirus app...${NC}"
docker compose exec -u www-data app php occ app:install files_antivirus 2>/dev/null || \
    docker compose exec -u www-data app php occ app:enable files_antivirus

echo -e "${GREEN}files_antivirus app enabled${NC}"

# Configure antivirus to use ClamAV daemon
echo -e "${YELLOW}Configuring antivirus settings...${NC}"
docker compose exec -u www-data app php occ config:app:set files_antivirus av_mode --value="daemon"
docker compose exec -u www-data app php occ config:app:set files_antivirus av_host --value="clamav"
docker compose exec -u www-data app php occ config:app:set files_antivirus av_port --value="3310"
docker compose exec -u www-data app php occ config:app:set files_antivirus av_stream_max_length --value="104857600"
docker compose exec -u www-data app php occ config:app:set files_antivirus av_infected_action --value="only_log"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   ClamAV Setup Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Configuration:"
echo "  - Mode: Daemon"
echo "  - Host: clamav (Docker network)"
echo "  - Port: 3310"
echo "  - Max scan size: 100 MB"
echo "  - Infected action: Log only (change in Admin > Security settings)"
echo ""
echo "Files will be scanned automatically on upload."
echo "Review detections in Admin > Logging."
