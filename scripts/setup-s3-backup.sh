#!/bin/bash

# One-time setup for automated S3 database backups.
#
# The backup bucket and IAM user are managed by CDK (HomeWeb db-backup-stack).
# This script configures AWS credentials on the server and wires up the cron job.
#
# Before running, retrieve the secret key from Secrets Manager:
#   aws-vault exec thonbecker -- aws secretsmanager get-secret-value \
#     --secret-id nextcloud-db-backup-user-secret-key \
#     --query SecretString --output text

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/nextcloud-aws || exit 1

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}   S3 Database Backup Setup${NC}"
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

# CDK-managed resources
DB_BACKUP_BUCKET="nextcloud-db-backups-thonbecker"
EXPECTED_KEY_ID="AKIAZVRVZ6IX6NOI2C3K"

echo ""
echo "Bucket (CDK-managed): s3://${DB_BACKUP_BUCKET}"
echo "IAM user:             nextcloud-db-backup-user"
echo ""
echo -e "${YELLOW}Retrieve the secret key with:${NC}"
echo "  aws-vault exec thonbecker -- aws secretsmanager get-secret-value \\"
echo "    --secret-id nextcloud-db-backup-user-secret-key \\"
echo "    --query SecretString --output text"
echo ""

read -rp "AWS Access Key ID [${EXPECTED_KEY_ID}]: " ACCESS_KEY_ID
ACCESS_KEY_ID="${ACCESS_KEY_ID:-${EXPECTED_KEY_ID}}"

read -rsp "AWS Secret Access Key: " SECRET_ACCESS_KEY
echo ""

if [ -z "$SECRET_ACCESS_KEY" ]; then
    echo -e "${RED}Secret access key cannot be empty!${NC}"
    exit 1
fi

# Configure default AWS credentials for the backup service account
aws configure set aws_access_key_id "$ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$SECRET_ACCESS_KEY"
aws configure set region us-east-1
aws configure set output json

echo -e "${GREEN}AWS credentials configured.${NC}"

# Verify bucket access
echo -e "${YELLOW}Verifying access to s3://${DB_BACKUP_BUCKET}...${NC}"
if aws s3 ls "s3://${DB_BACKUP_BUCKET}" &> /dev/null; then
    echo -e "${GREEN}Bucket access verified.${NC}"
else
    echo -e "${RED}Cannot access s3://${DB_BACKUP_BUCKET}. Check credentials and IAM permissions.${NC}"
    exit 1
fi

# Set S3_DB_BACKUP_BUCKET in .env
if grep -q "^S3_DB_BACKUP_BUCKET=" .env 2>/dev/null; then
    sed -i "s|^S3_DB_BACKUP_BUCKET=.*|S3_DB_BACKUP_BUCKET=${DB_BACKUP_BUCKET}|" .env
    echo -e "${GREEN}Updated S3_DB_BACKUP_BUCKET in .env${NC}"
elif grep -q "^S3_BUCKET=" .env 2>/dev/null; then
    sed -i "/^S3_BUCKET=/a S3_DB_BACKUP_BUCKET=${DB_BACKUP_BUCKET}" .env
    echo -e "${GREEN}Added S3_DB_BACKUP_BUCKET to .env${NC}"
else
    echo "" >> .env
    echo "S3_DB_BACKUP_BUCKET=${DB_BACKUP_BUCKET}" >> .env
    echo -e "${GREEN}Added S3_DB_BACKUP_BUCKET to .env${NC}"
fi

# Set up cron job for daily backups at 2 AM
SCRIPT_PATH="${HOME}/nextcloud-aws/scripts/backup-to-s3.sh"
CRON_CMD="0 2 * * * ${SCRIPT_PATH} >> /mnt/nextcloud-data/backups/cron.log 2>&1"

chmod +x "$SCRIPT_PATH"

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
echo "  - Save locally to /mnt/nextcloud-data/backups/"
echo "  - Keep the last 3 local copies per database"
echo "  - Upload to:"
echo "      s3://${DB_BACKUP_BUCKET}/mariadb/   (Nextcloud MariaDB)"
echo "      s3://${DB_BACKUP_BUCKET}/postgres/  (Ente PostgreSQL)"
echo "  - S3 objects expire automatically after 7 days (CDK lifecycle rule)"
echo ""
echo "To run a backup manually:"
echo "  ./scripts/backup-to-s3.sh"
echo ""
echo "To check cron logs:"
echo "  tail -f /mnt/nextcloud-data/backups/cron.log"
