#!/bin/bash
set -euo pipefail

# Generates ente/museum.yaml from the template using .env values.
# Run from ~/nextcloud-aws or pass PROJECT_DIR as first argument.

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ENV_FILE="$PROJECT_DIR/.env"
TEMPLATE="$PROJECT_DIR/ente/museum.yaml.template"
OUTPUT="$PROJECT_DIR/ente/museum.yaml"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE not found" >&2
    exit 1
fi

# Source .env (handle lines with special characters)
set -a
source "$ENV_FILE"
set +a

# Verify required variables
for var in ENTE_POSTGRES_USER ENTE_POSTGRES_PASSWORD ENTE_S3_ACCESS_KEY \
           ENTE_S3_SECRET_KEY ENTE_S3_REGION ENTE_S3_BUCKET ENTE_JWT_SECRET \
           ENTE_KEY_ENCRYPTION ENTE_KEY_HASH ENTE_SMTP_USERNAME ENTE_SMTP_PASSWORD; do
    if [ -z "${!var:-}" ]; then
        echo "Error: $var is not set in $ENV_FILE" >&2
        exit 1
    fi
done

sed -e "s|ENTE_DB_USER_PLACEHOLDER|$ENTE_POSTGRES_USER|g" \
    -e "s|ENTE_DB_PASSWORD_PLACEHOLDER|$ENTE_POSTGRES_PASSWORD|g" \
    -e "s|ENTE_S3_ACCESS_KEY_PLACEHOLDER|$ENTE_S3_ACCESS_KEY|g" \
    -e "s|ENTE_S3_SECRET_KEY_PLACEHOLDER|$ENTE_S3_SECRET_KEY|g" \
    -e "s|ENTE_S3_REGION_PLACEHOLDER|$ENTE_S3_REGION|g" \
    -e "s|ENTE_S3_BUCKET_PLACEHOLDER|$ENTE_S3_BUCKET|g" \
    -e "s|ENTE_JWT_SECRET_PLACEHOLDER|$ENTE_JWT_SECRET|g" \
    -e "s|ENTE_KEY_ENCRYPTION_PLACEHOLDER|$ENTE_KEY_ENCRYPTION|g" \
    -e "s|ENTE_KEY_HASH_PLACEHOLDER|$ENTE_KEY_HASH|g" \
    -e "s|ENTE_SMTP_USERNAME_PLACEHOLDER|$ENTE_SMTP_USERNAME|g" \
    -e "s|ENTE_SMTP_PASSWORD_PLACEHOLDER|$ENTE_SMTP_PASSWORD|g" \
    "$TEMPLATE" > "$OUTPUT"

echo "Generated $OUTPUT"
