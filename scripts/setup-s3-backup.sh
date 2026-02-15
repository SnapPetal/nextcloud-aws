#!/bin/bash

# One-time setup for automated S3 backups
# Installs AWS CLI, configures S3 bucket, and adds cron job

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/nextcloud-aws || exit 1

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}   S3 Backup Setup${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    echo -e "${YELLOW}Installing AWS CLI...${NC}"
    sudo apt-get update && sudo apt-get install -y awscli
    echo -e "${GREEN}AWS CLI installed${NC}"
else
    echo -e "${GREEN}AWS CLI already installed ($(aws --version))${NC}"
fi

# Configure AWS credentials if not already set
if ! aws sts get-caller-identity &> /dev/null 2>&1; then
    echo ""
    echo -e "${YELLOW}AWS credentials not configured. Running 'aws configure'...${NC}"
    echo -e "${BLUE}You'll need your AWS Access Key ID, Secret Access Key, and region.${NC}"
    aws configure
fi

# Prompt for S3 bucket name
echo ""
read -p "Enter S3 bucket name for backups: " S3_BUCKET

if [ -z "$S3_BUCKET" ]; then
    echo -e "${RED}Bucket name cannot be empty!${NC}"
    exit 1
fi

# Verify bucket access
echo -e "${YELLOW}Verifying access to s3://${S3_BUCKET}...${NC}"
if aws s3 ls "s3://${S3_BUCKET}" &> /dev/null; then
    echo -e "${GREEN}Bucket access verified${NC}"
else
    echo -e "${RED}Cannot access bucket '${S3_BUCKET}'. Make sure it exists and you have permission.${NC}"
    exit 1
fi

# Add S3_BUCKET to .env if not already present
if grep -q "^S3_BUCKET=" .env 2>/dev/null; then
    sed -i "s|^S3_BUCKET=.*|S3_BUCKET=${S3_BUCKET}|" .env
    echo -e "${GREEN}Updated S3_BUCKET in .env${NC}"
else
    echo "" >> .env
    echo "# S3 Backup Configuration" >> .env
    echo "S3_BUCKET=${S3_BUCKET}" >> .env
    echo -e "${GREEN}Added S3_BUCKET to .env${NC}"
fi

# Set up cron job for daily backups at 2 AM
CRON_CMD="0 2 * * * ${HOME}/nextcloud-aws/scripts/backup-to-s3.sh >> /mnt/nextcloud-data/backups/cron.log 2>&1"
SCRIPT_PATH="${HOME}/nextcloud-aws/scripts/backup-to-s3.sh"

# Make backup script executable
chmod +x "$SCRIPT_PATH"

# Add cron job if not already present
if crontab -l 2>/dev/null | grep -qF "backup-to-s3.sh"; then
    echo -e "${YELLOW}Cron job already exists, updating...${NC}"
    (crontab -l 2>/dev/null | grep -vF "backup-to-s3.sh"; echo "$CRON_CMD") | crontab -
else
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
fi

echo -e "${GREEN}Cron job configured: daily at 2:00 AM${NC}"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Setup Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Backups will:"
echo "  - Run daily at 2:00 AM"
echo "  - Save to /mnt/nextcloud-data/backups/"
echo "  - Keep only the last 3 local backups"
echo "  - Sync to s3://${S3_BUCKET}/backups/"
echo ""
echo "To run a backup manually:"
echo "  ./scripts/backup-to-s3.sh"
echo ""
echo "To check cron logs:"
echo "  tail -f /mnt/nextcloud-data/backups/cron.log"
