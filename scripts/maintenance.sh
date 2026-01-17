#!/bin/bash

# Nextcloud Maintenance Script
# Common maintenance tasks for Nextcloud on AWS Lightsail

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Change to project directory
cd ~/nextcloud-aws || exit 1

show_menu() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   Nextcloud Maintenance Menu${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo "1. View logs (all containers)"
    echo "2. View Nextcloud app logs only"
    echo "3. Check container status"
    echo "4. Restart all containers"
    echo "5. Update containers to latest versions"
    echo "6. Run Nextcloud maintenance mode ON"
    echo "7. Run Nextcloud maintenance mode OFF"
    echo "8. Add missing database indices"
    echo "9. Scan files for all users"
    echo "10. Backup database"
    echo "11. Backup files"
    echo "12. Check disk usage"
    echo "13. Clear Redis cache"
    echo "14. Show Nextcloud status"
    echo "15. Run security scan"
    echo "0. Exit"
    echo ""
    read -p "Enter your choice: " choice
}

view_logs() {
    echo -e "${GREEN}Viewing all container logs (Ctrl+C to exit)...${NC}"
    docker compose logs -f
}

view_app_logs() {
    echo -e "${GREEN}Viewing Nextcloud app logs (Ctrl+C to exit)...${NC}"
    docker compose logs -f app
}

check_status() {
    echo -e "${GREEN}Container Status:${NC}"
    docker compose ps
    echo ""
    echo -e "${GREEN}Container Resource Usage:${NC}"
    docker stats --no-stream
}

restart_containers() {
    echo -e "${YELLOW}Restarting all containers...${NC}"
    docker compose restart
    echo -e "${GREEN}Containers restarted successfully!${NC}"
    docker compose ps
}

update_containers() {
    echo -e "${YELLOW}Pulling latest images...${NC}"
    docker compose pull
    echo ""
    echo -e "${YELLOW}Recreating containers with new images...${NC}"
    docker compose up -d
    echo ""
    echo -e "${GREEN}Update complete!${NC}"
    docker compose ps
    echo ""
    echo -e "${YELLOW}Cleaning up old images...${NC}"
    docker image prune -f
}

maintenance_on() {
    echo -e "${YELLOW}Enabling maintenance mode...${NC}"
    docker compose exec -u www-data app php occ maintenance:mode --on
    echo -e "${GREEN}Maintenance mode enabled${NC}"
}

maintenance_off() {
    echo -e "${YELLOW}Disabling maintenance mode...${NC}"
    docker compose exec -u www-data app php occ maintenance:mode --off
    echo -e "${GREEN}Maintenance mode disabled${NC}"
}

add_indices() {
    echo -e "${YELLOW}Adding missing database indices...${NC}"
    docker compose exec -u www-data app php occ db:add-missing-indices
    echo -e "${GREEN}Database indices updated${NC}"
}

scan_files() {
    echo -e "${YELLOW}Scanning files for all users...${NC}"
    docker compose exec -u www-data app php occ files:scan --all
    echo -e "${GREEN}File scan complete${NC}"
}

backup_database() {
    BACKUP_DIR="/mnt/nextcloud-data/backups"
    BACKUP_FILE="$BACKUP_DIR/nextcloud-db-$(date +%Y%m%d-%H%M%S).sql"

    echo -e "${YELLOW}Creating database backup...${NC}"
    sudo mkdir -p "$BACKUP_DIR"

    # Read database credentials from .env
    source .env

    if [[ -n "$DB_HOST" ]]; then
        # External database
        echo -e "${BLUE}Backing up external Lightsail database...${NC}"
        read -sp "Enter database password: " DB_PASS
        echo ""

        # Check if MySQL or PostgreSQL
        if mysqldump --version &> /dev/null; then
            mysqldump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_FILE"
        elif pg_dump --version &> /dev/null; then
            PGPASSWORD="$DB_PASS" pg_dump -h "$DB_HOST" -U "$DB_USER" "$DB_NAME" > "$BACKUP_FILE"
        else
            echo -e "${RED}Neither mysql-client nor postgresql-client is installed!${NC}"
            echo "Install with: sudo apt install mysql-client -y"
            echo "Or for PostgreSQL: sudo apt install postgresql-client -y"
            return 1
        fi
    fi

    if [ -f "$BACKUP_FILE" ]; then
        sudo chown $USER:$USER "$BACKUP_FILE"
        echo -e "${GREEN}Database backup created: $BACKUP_FILE${NC}"
        ls -lh "$BACKUP_FILE"
    else
        echo -e "${RED}Backup failed!${NC}"
    fi
}

backup_files() {
    BACKUP_DIR="/mnt/nextcloud-data/backups"
    BACKUP_FILE="$BACKUP_DIR/nextcloud-files-$(date +%Y%m%d-%H%M%S).tar.gz"

    echo -e "${YELLOW}Creating file backup (this may take a while)...${NC}"
    sudo mkdir -p "$BACKUP_DIR"

    sudo tar -czf "$BACKUP_FILE" \
        -C /mnt/nextcloud-data \
        --exclude='backups' \
        nextcloud data

    if [ -f "$BACKUP_FILE" ]; then
        sudo chown $USER:$USER "$BACKUP_FILE"
        echo -e "${GREEN}File backup created: $BACKUP_FILE${NC}"
        ls -lh "$BACKUP_FILE"
    else
        echo -e "${RED}Backup failed!${NC}"
    fi
}

check_disk() {
    echo -e "${GREEN}Disk Usage:${NC}"
    df -h /mnt/nextcloud-data
    echo ""
    echo -e "${GREEN}Data Directory Breakdown:${NC}"
    sudo du -sh /mnt/nextcloud-data/* | sort -h
}

clear_cache() {
    echo -e "${YELLOW}Clearing Redis cache...${NC}"
    docker compose exec redis redis-cli FLUSHALL
    echo -e "${GREEN}Redis cache cleared${NC}"
}

show_status() {
    echo -e "${GREEN}Nextcloud Status:${NC}"
    docker compose exec -u www-data app php occ status
    echo ""
    echo -e "${GREEN}Nextcloud Version:${NC}"
    docker compose exec -u www-data app php occ -V
}

security_scan() {
    echo -e "${GREEN}Running security scan...${NC}"
    docker compose exec -u www-data app php occ security:certificates
    echo ""
    echo -e "${GREEN}Checking for updates:${NC}"
    docker compose exec -u www-data app php occ update:check
}

# Main loop
while true; do
    show_menu

    case $choice in
        1) view_logs ;;
        2) view_app_logs ;;
        3) check_status ;;
        4) restart_containers ;;
        5) update_containers ;;
        6) maintenance_on ;;
        7) maintenance_off ;;
        8) add_indices ;;
        9) scan_files ;;
        10) backup_database ;;
        11) backup_files ;;
        12) check_disk ;;
        13) clear_cache ;;
        14) show_status ;;
        15) security_scan ;;
        0)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
