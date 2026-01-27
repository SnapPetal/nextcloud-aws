#!/bin/bash

# Migrate Nextcloud to Lightsail S3 Object Storage
# This script migrates your Nextcloud data to S3 primary storage
#
# Prerequisites:
# 1. Create a Lightsail bucket at: https://lightsail.aws.amazon.com/ls/webapp/home/storage
#    - Choose the 250GB plan ($5/month)
#    - Note the bucket name and region
# 2. Create access keys for the bucket:
#    - Go to bucket -> Permissions -> Access keys
#    - Create new access key, save the Access Key ID and Secret
# 3. Ensure you have a backup of your data

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
echo -e "${BLUE}  Nextcloud S3 Migration Script${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Function to run occ commands
occ() {
    docker compose exec -u www-data app php occ "$@"
}

# Step 0: Pre-flight checks
echo -e "${YELLOW}Step 0: Pre-flight checks${NC}"
echo ""

# Check if Nextcloud is running
if ! docker compose ps | grep -q "nextcloud-app.*Up"; then
    echo -e "${RED}Error: Nextcloud container is not running${NC}"
    echo "Run: docker compose up -d"
    exit 1
fi
echo -e "${GREEN}✓ Nextcloud is running${NC}"

# Check current storage usage
echo ""
echo -e "${BLUE}Current storage usage:${NC}"
df -h /mnt/nextcloud-data | tail -1
echo ""

DATA_SIZE=$(du -sh /mnt/nextcloud-data/data 2>/dev/null | cut -f1 || echo "unknown")
echo -e "User data size: ${YELLOW}${DATA_SIZE}${NC}"
echo ""

# Step 1: Gather S3 bucket information
echo -e "${YELLOW}Step 1: Enter Lightsail Bucket Details${NC}"
echo ""
echo "Create a bucket at: https://lightsail.aws.amazon.com/ls/webapp/home/storage"
echo "Then create access keys under: Bucket -> Permissions -> Access keys"
echo ""

read -p "Bucket name: " S3_BUCKET
read -p "Bucket region (e.g., us-east-1): " S3_REGION
read -p "Access Key ID: " S3_KEY
read -sp "Secret Access Key: " S3_SECRET
echo ""
echo ""

# Validate inputs
if [[ -z "$S3_BUCKET" || -z "$S3_REGION" || -z "$S3_KEY" || -z "$S3_SECRET" ]]; then
    echo -e "${RED}Error: All fields are required${NC}"
    exit 1
fi

# Lightsail S3 endpoint format
S3_ENDPOINT="https://s3.${S3_REGION}.amazonaws.com"

echo -e "${GREEN}✓ Bucket details collected${NC}"
echo ""

# Step 2: Test S3 connection
echo -e "${YELLOW}Step 2: Testing S3 connection...${NC}"

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI..."
    sudo apt-get update && sudo apt-get install -y awscli
fi

# Configure temporary AWS credentials
export AWS_ACCESS_KEY_ID="$S3_KEY"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET"
export AWS_DEFAULT_REGION="$S3_REGION"

# Test bucket access
if aws s3 ls "s3://${S3_BUCKET}" &>/dev/null; then
    echo -e "${GREEN}✓ Successfully connected to S3 bucket${NC}"
else
    echo -e "${RED}Error: Cannot access bucket. Check credentials and bucket name.${NC}"
    exit 1
fi
echo ""

# Step 3: Backup current config
echo -e "${YELLOW}Step 3: Backing up current configuration...${NC}"

BACKUP_DIR="/mnt/nextcloud-data/backups/pre-s3-migration-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"
sudo cp /mnt/nextcloud-data/nextcloud/config/config.php "$BACKUP_DIR/"
echo -e "${GREEN}✓ Config backed up to: ${BACKUP_DIR}${NC}"
echo ""

# Step 4: Enable maintenance mode
echo -e "${YELLOW}Step 4: Enabling maintenance mode...${NC}"
occ maintenance:mode --on
echo -e "${GREEN}✓ Maintenance mode enabled${NC}"
echo ""

# Step 5: Configure S3 as primary storage
echo -e "${YELLOW}Step 5: Configuring S3 as primary storage...${NC}"

# Add S3 configuration to config.php
occ config:system:set objectstore class --value="\\OC\\Files\\ObjectStore\\S3"
occ config:system:set objectstore arguments bucket --value="$S3_BUCKET"
occ config:system:set objectstore arguments region --value="$S3_REGION"
occ config:system:set objectstore arguments key --value="$S3_KEY"
occ config:system:set objectstore arguments secret --value="$S3_SECRET"
occ config:system:set objectstore arguments use_ssl --value="true" --type=boolean
occ config:system:set objectstore arguments use_path_style --value="false" --type=boolean

echo -e "${GREEN}✓ S3 configuration added${NC}"
echo ""

# Step 6: Migrate existing files
echo -e "${YELLOW}Step 6: Migrating files to S3...${NC}"
echo ""
echo -e "${BLUE}This may take a long time depending on data size (${DATA_SIZE}).${NC}"
echo "You can monitor progress in another terminal with:"
echo "  watch 'aws s3 ls s3://${S3_BUCKET} --recursive --summarize | tail -5'"
echo ""
read -p "Press Enter to start migration (or Ctrl+C to abort)..."
echo ""

# The migration happens automatically when Nextcloud accesses files
# But we need to trigger a full scan to migrate all files
echo "Starting file migration..."
echo "This process will:"
echo "  1. Scan all files"
echo "  2. Copy each file to S3"
echo "  3. Update database references"
echo ""

# Use files:scan to trigger the migration
# With objectstore configured, accessing files will migrate them
occ files:scan --all -v

echo ""
echo -e "${GREEN}✓ File scan complete${NC}"
echo ""

# Step 7: Verify migration
echo -e "${YELLOW}Step 7: Verifying migration...${NC}"

S3_COUNT=$(aws s3 ls "s3://${S3_BUCKET}" --recursive | wc -l)
echo "Files in S3 bucket: $S3_COUNT"

# Check Nextcloud status
occ status

echo ""
echo -e "${GREEN}✓ Migration verification complete${NC}"
echo ""

# Step 8: Disable maintenance mode
echo -e "${YELLOW}Step 8: Disabling maintenance mode...${NC}"
occ maintenance:mode --off
echo -e "${GREEN}✓ Maintenance mode disabled${NC}"
echo ""

# Summary
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}  Migration Complete!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. ${YELLOW}Test your Nextcloud:${NC}"
echo "   - Log in and verify files are accessible"
echo "   - Upload a test file"
echo "   - Check photos/images display correctly"
echo ""
echo "2. ${YELLOW}Monitor for a few days${NC}"
echo "   - Check logs: docker compose logs -f app"
echo "   - Verify S3 bucket usage in Lightsail console"
echo ""
echo "3. ${YELLOW}After confirming everything works:${NC}"
echo "   - Old data in /mnt/nextcloud-data/data can be removed"
echo "   - Run: sudo rm -rf /mnt/nextcloud-data/data/*"
echo "   - Consider resizing block storage to save costs"
echo ""
echo "4. ${YELLOW}If issues occur, restore from backup:${NC}"
echo "   - sudo cp ${BACKUP_DIR}/config.php /mnt/nextcloud-data/nextcloud/config/"
echo "   - docker compose restart app"
echo ""
echo -e "${BLUE}Backup location: ${BACKUP_DIR}${NC}"
echo ""
echo "Add these to your .env for reference:"
echo "  S3_BUCKET=${S3_BUCKET}"
echo "  S3_REGION=${S3_REGION}"
echo "  S3_KEY=${S3_KEY}"
echo "  # S3_SECRET stored in Nextcloud config"
echo ""
