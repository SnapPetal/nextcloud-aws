#!/bin/bash

# Automated Database Backup to S3
# Backs up MariaDB (Nextcloud), PostgreSQL (Ente), and SQLite (Vaultwarden),
# retains last 3 local copies, and uploads to S3.
#
# Bucket priority:
#   S3_DB_BACKUP_BUCKET  — dedicated bucket (setup-db-backup-bucket.sh); uploads to
#                          mariadb/ and postgres/ prefixes
#   S3_BUCKET            — legacy fallback; uploads to backups/ (MariaDB only)

set -e

cd ~/nextcloud-aws || exit 1
source .env

BACKUP_DIR="/var/lib/nextcloud/data/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
MARIADB_FILE="nextcloud-db-${TIMESTAMP}.sql.gz"
PG_FILE="ente-db-${TIMESTAMP}.sql.gz"
VW_FILE="vaultwarden-db-${TIMESTAMP}.sqlite3.gz"
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

# ── PostgreSQL backup (Ente) ────────────────────────────────────────────────

PG_BACKED_UP=false

if [ -n "${ENTE_POSTGRES_DB:-}" ] && [ -n "${ENTE_POSTGRES_USER:-}" ]; then
    log "Starting PostgreSQL backup (Ente)..."

    docker compose exec -T ente-postgres pg_dump \
        -U "${ENTE_POSTGRES_USER}" \
        "${ENTE_POSTGRES_DB}" | gzip > "${BACKUP_DIR}/${PG_FILE}"

    if [ ! -s "${BACKUP_DIR}/${PG_FILE}" ]; then
        log "ERROR: PostgreSQL backup file is empty or missing!"
        exit 1
    fi

    log "PostgreSQL backup created: ${PG_FILE} ($(du -h "${BACKUP_DIR}/${PG_FILE}" | cut -f1))"

    # Retain only the last 3 PostgreSQL backups locally
    log "Cleaning old local PostgreSQL backups (keeping last 3)..."
    cd "$BACKUP_DIR"
    ls -1t ente-db-*.sql.gz 2>/dev/null | tail -n +4 | xargs -r rm -f
    cd ~/nextcloud-aws

    PG_BACKED_UP=true
else
    log "ENTE_POSTGRES_DB or ENTE_POSTGRES_USER not set — skipping PostgreSQL backup"
fi

REMAINING=$(ls -1 "${BACKUP_DIR}"/nextcloud-db-*.sql.gz 2>/dev/null | wc -l)
log "Local MariaDB backups remaining: ${REMAINING}"

# ── Vaultwarden SQLite backup ────────────────────────────────────────────────

VW_BACKED_UP=false

if docker ps --format '{{.Names}}' | grep -q '^vaultwarden$'; then
    log "Starting Vaultwarden SQLite backup..."

    docker cp vaultwarden:/data/db.sqlite3 - | gzip > "${BACKUP_DIR}/${VW_FILE}"

    if [ ! -s "${BACKUP_DIR}/${VW_FILE}" ]; then
        log "ERROR: Vaultwarden backup file is empty or missing!"
        exit 1
    fi

    log "Vaultwarden backup created: ${VW_FILE} ($(du -h "${BACKUP_DIR}/${VW_FILE}" | cut -f1))"

    # Retain only the last 3 Vaultwarden backups locally
    log "Cleaning old local Vaultwarden backups (keeping last 3)..."
    cd "$BACKUP_DIR"
    ls -1t vaultwarden-db-*.sqlite3.gz 2>/dev/null | tail -n +4 | xargs -r rm -f
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

    if [ "$PG_BACKED_UP" = true ]; then
        log "Uploading PostgreSQL backup to s3://${S3_DB_BACKUP_BUCKET}/postgres/..."
        aws s3 cp "${BACKUP_DIR}/${PG_FILE}" \
            "s3://${S3_DB_BACKUP_BUCKET}/postgres/${PG_FILE}"
    fi

    if [ "$VW_BACKED_UP" = true ]; then
        log "Uploading Vaultwarden backup to s3://${S3_DB_BACKUP_BUCKET}/vaultwarden/..."
        aws s3 cp "${BACKUP_DIR}/${VW_FILE}" \
            "s3://${S3_DB_BACKUP_BUCKET}/vaultwarden/${VW_FILE}"
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
