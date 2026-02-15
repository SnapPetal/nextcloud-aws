#!/bin/bash

# Automated Database Backup to S3
# Dumps MariaDB, retains last 3 local backups, syncs to S3

set -e

# Change to project directory
cd ~/nextcloud-aws || exit 1

# Load environment
source .env

BACKUP_DIR="/mnt/nextcloud-data/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="nextcloud-db-${TIMESTAMP}.sql.gz"
LOG_FILE="${BACKUP_DIR}/backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Ensure backup directory exists
sudo mkdir -p "$BACKUP_DIR"
sudo chown "$USER:$USER" "$BACKUP_DIR"

log "Starting database backup..."

# Dump database via docker compose and compress
docker compose exec -T db mariadb-dump \
    -u root -p"${DB_ROOT_PASSWORD}" \
    --single-transaction \
    "${DB_NAME}" | gzip > "${BACKUP_DIR}/${BACKUP_FILE}"

if [ ! -s "${BACKUP_DIR}/${BACKUP_FILE}" ]; then
    log "ERROR: Backup file is empty or missing!"
    exit 1
fi

log "Backup created: ${BACKUP_FILE} ($(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1))"

# Retain only the last 3 backups locally
log "Cleaning old local backups (keeping last 3)..."
cd "$BACKUP_DIR"
ls -1t nextcloud-db-*.sql.gz 2>/dev/null | tail -n +4 | xargs -r rm -f
cd ~/nextcloud-aws

REMAINING=$(ls -1 "${BACKUP_DIR}"/nextcloud-db-*.sql.gz 2>/dev/null | wc -l)
log "Local backups remaining: ${REMAINING}"

# Sync to S3
if [ -n "$S3_BUCKET" ]; then
    log "Syncing backups to s3://${S3_BUCKET}/backups/..."
    aws s3 sync "$BACKUP_DIR" "s3://${S3_BUCKET}/backups/" \
        --exclude "*" --include "nextcloud-db-*.sql.gz" \
        --exclude "backup.log"
    log "S3 sync complete"
else
    log "WARNING: S3_BUCKET not set in .env, skipping S3 sync"
fi

log "Backup process finished successfully"
