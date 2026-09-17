#!/bin/bash

# Automated Database Backup to S3
# Backs up MariaDB (Nextcloud) and SQLite (Vaultwarden),
# retains last 3 local copies, and uploads to S3.
#
# Bucket priority:
#   S3_DB_BACKUP_BUCKET  — dedicated bucket (setup-db-backup-bucket.sh); uploads to
#                          mariadb/ and vaultwarden/ prefixes
#   S3_BUCKET            — legacy fallback; uploads to backups/ (MariaDB only)

set -eo pipefail

cd ~/nextcloud-aws || exit 1
source .env

BACKUP_DIR="/var/lib/nextcloud/data/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
MARIADB_FILE="nextcloud-db-${TIMESTAMP}.sql.gz"
VW_FILE="vaultwarden-db-${TIMESTAMP}.sqlite3.gz"
VW_DATA_FILE="vaultwarden-data-${TIMESTAMP}.tar.gz"
LOG_FILE="${BACKUP_DIR}/backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Ensure backup directory exists
sudo mkdir -p "$BACKUP_DIR"
sudo chown "$USER:$USER" "$BACKUP_DIR"

# ── MariaDB backup ──────────────────────────────────────────────────────────

log "Starting MariaDB backup..."

docker compose exec -T db mariadb-dump \
    -u root -p"${DB_ROOT_PASSWORD}" \
    --single-transaction \
    "${DB_NAME}" | gzip > "${BACKUP_DIR}/${MARIADB_FILE}"

if [ ! -s "${BACKUP_DIR}/${MARIADB_FILE}" ]; then
    log "ERROR: MariaDB backup file is empty or missing!"
    exit 1
fi

log "MariaDB backup created: ${MARIADB_FILE} ($(du -h "${BACKUP_DIR}/${MARIADB_FILE}" | cut -f1))"

# Retain only the last 3 MariaDB backups locally
log "Cleaning old local MariaDB backups (keeping last 3)..."
cd "$BACKUP_DIR"
ls -1t nextcloud-db-*.sql.gz 2>/dev/null | tail -n +4 | xargs -r rm -f
cd ~/nextcloud-aws

REMAINING=$(ls -1 "${BACKUP_DIR}"/nextcloud-db-*.sql.gz 2>/dev/null | wc -l)
log "Local MariaDB backups remaining: ${REMAINING}"

# ── Vaultwarden SQLite backup ────────────────────────────────────────────────

VW_BACKED_UP=false

if docker ps --format '{{.Names}}' | grep -q '^vaultwarden$'; then
    log "Starting Vaultwarden SQLite backup..."

    # Vaultwarden uses SQLite WAL mode, so copying db.sqlite3 alone can omit
    # transactions that have not yet been checkpointed from db.sqlite3-wal.
    # The built-in backup command uses SQLite VACUUM INTO to create a complete,
    # consistent point-in-time snapshot while Vaultwarden remains online.
    VW_PREVIOUS_SNAPSHOT=$(docker exec vaultwarden sh -c \
        'ls -1t /data/db_*.sqlite3 2>/dev/null | head -n 1' || true)
    docker exec vaultwarden /vaultwarden backup
    VW_SNAPSHOT=$(docker exec vaultwarden sh -c \
        'ls -1t /data/db_*.sqlite3 2>/dev/null | head -n 1')

    if [ -z "$VW_SNAPSHOT" ] || [ "$VW_SNAPSHOT" = "$VW_PREVIOUS_SNAPSHOT" ]; then
        log "ERROR: Vaultwarden did not create a new SQLite snapshot!"
        exit 1
    fi

    docker exec vaultwarden cat "$VW_SNAPSHOT" | gzip > "${BACKUP_DIR}/${VW_FILE}"

    if [ ! -s "${BACKUP_DIR}/${VW_FILE}" ]; then
        log "ERROR: Vaultwarden backup file is empty or missing!"
        exit 1
    fi

    if ! gzip -t "${BACKUP_DIR}/${VW_FILE}"; then
        log "ERROR: Vaultwarden backup gzip validation failed!"
        exit 1
    fi

    docker exec vaultwarden rm -f -- "$VW_SNAPSHOT"

    log "Vaultwarden backup created: ${VW_FILE} ($(du -h "${BACKUP_DIR}/${VW_FILE}" | cut -f1))"

    # Back up the non-database recovery data (RSA key, attachments, Sends, and
    # config if present). The database has its own consistent snapshot above,
    # and the icon cache is disposable and regenerated automatically.
    docker exec vaultwarden tar \
        --exclude='./db.sqlite3' \
        --exclude='./db.sqlite3-shm' \
        --exclude='./db.sqlite3-wal' \
        --exclude='./db_*.sqlite3' \
        --exclude='./icon_cache' \
        -C /data -czf - . > "${BACKUP_DIR}/${VW_DATA_FILE}"

    if [ ! -s "${BACKUP_DIR}/${VW_DATA_FILE}" ] || \
        ! tar -tzf "${BACKUP_DIR}/${VW_DATA_FILE}" >/dev/null; then
        log "ERROR: Vaultwarden recovery-data archive validation failed!"
        exit 1
    fi

    log "Vaultwarden recovery data created: ${VW_DATA_FILE} ($(du -h "${BACKUP_DIR}/${VW_DATA_FILE}" | cut -f1))"

    # Retain only the last 3 Vaultwarden backups locally
    log "Cleaning old local Vaultwarden backups (keeping last 3)..."
    cd "$BACKUP_DIR"
    ls -1t vaultwarden-db-*.sqlite3.gz 2>/dev/null | tail -n +4 | xargs -r rm -f
    ls -1t vaultwarden-data-*.tar.gz 2>/dev/null | tail -n +4 | xargs -r rm -f
    cd ~/nextcloud-aws

    VW_BACKED_UP=true
else
    log "Vaultwarden container not running — skipping SQLite backup"
fi

# ── Upload to S3 ────────────────────────────────────────────────────────────

if [ -n "${S3_DB_BACKUP_BUCKET:-}" ]; then
    # Dedicated bucket: separate prefixes per database
    log "Uploading MariaDB backup to s3://${S3_DB_BACKUP_BUCKET}/mariadb/..."
    aws s3 cp "${BACKUP_DIR}/${MARIADB_FILE}" \
        "s3://${S3_DB_BACKUP_BUCKET}/mariadb/${MARIADB_FILE}"

    if [ "$VW_BACKED_UP" = true ]; then
        log "Uploading Vaultwarden backup to s3://${S3_DB_BACKUP_BUCKET}/vaultwarden/..."
        aws s3 cp "${BACKUP_DIR}/${VW_FILE}" \
            "s3://${S3_DB_BACKUP_BUCKET}/vaultwarden/${VW_FILE}"
        aws s3 cp "${BACKUP_DIR}/${VW_DATA_FILE}" \
            "s3://${S3_DB_BACKUP_BUCKET}/vaultwarden/${VW_DATA_FILE}"
    fi

    log "S3 upload complete (bucket: ${S3_DB_BACKUP_BUCKET})"

elif [ -n "${S3_BUCKET:-}" ]; then
    # Legacy fallback: sync MariaDB backups to backups/ prefix
    log "Syncing MariaDB backups to s3://${S3_BUCKET}/backups/ (legacy S3_BUCKET)..."
    aws s3 sync "$BACKUP_DIR" "s3://${S3_BUCKET}/backups/" \
        --exclude "*" --include "nextcloud-db-*.sql.gz" \
        --exclude "backup.log"
    log "S3 sync complete"

else
    log "WARNING: Neither S3_DB_BACKUP_BUCKET nor S3_BUCKET set in .env — skipping S3 upload"
fi

log "Backup process finished successfully"
