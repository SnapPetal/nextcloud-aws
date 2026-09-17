#!/bin/bash
set -euo pipefail

# Ente Photos setup script
# Run once from ~/nextcloud-aws to configure Ente alongside Nextcloud

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

echo "=== Ente Photos Setup ==="
echo ""

# Check prerequisites
if ! command -v openssl &> /dev/null; then
    echo "Error: openssl is required but not installed."
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "Warning: aws CLI not found. Skipping S3 bucket creation."
    SKIP_S3=true
else
    SKIP_S3=false
fi

# Generate random secrets
echo "Generating secrets..."
JWT_SECRET=$(openssl rand -hex 32)
KEY_ENCRYPTION=$(openssl rand 32 | base64 | tr -d '\n')
KEY_HASH=$(openssl rand 32 | base64 | tr -d '\n')

echo ""

# Prompt for S3 configuration
read -rp "S3 bucket name for Ente photos: " S3_BUCKET
read -rp "S3 region [us-east-1]: " S3_REGION
S3_REGION="${S3_REGION:-us-east-1}"
read -rp "S3 access key: " S3_ACCESS_KEY
read -rsp "S3 secret key: " S3_SECRET_KEY
echo ""

# Prompt for managed Postgres configuration
read -rp "Ente Postgres host: " PG_HOST
if [ -z "$PG_HOST" ]; then
    echo "Error: an external PostgreSQL host is required." >&2
    exit 1
fi
read -rp "Ente Postgres port [5432]: " PG_PORT
PG_PORT="${PG_PORT:-5432}"
read -rp "Ente Postgres user [ente]: " PG_USER
PG_USER="${PG_USER:-ente}"
read -rp "Ente Postgres database [ente_db]: " PG_DB
PG_DB="${PG_DB:-ente_db}"
read -rsp "Ente Postgres password: " PG_PASSWORD
echo ""
if [ -z "$PG_PASSWORD" ]; then
    echo "Error: the external PostgreSQL password is required." >&2
    exit 1
fi

# Prompt for SMTP configuration
read -rp "SMTP email (Gmail address): " SMTP_USERNAME
read -rsp "SMTP app password: " SMTP_PASSWORD
echo ""

echo ""
echo "Updating .env..."

ENV_BACKUP="${ENV_FILE}.bak-$(date +%Y%m%d-%H%M%S)-$$"
if [ -f "$ENV_FILE" ]; then
    cp -p "$ENV_FILE" "$ENV_BACKUP"
    chmod 600 "$ENV_BACKUP"
    echo "Backed up existing .env to $ENV_BACKUP"
fi

touch "$ENV_FILE"

set_env_value() {
    local key="$1"
    local value="$2"
    local escaped="$value"

    escaped="${escaped//\\/\\\\}"
    escaped="${escaped//&/\\&}"
    escaped="${escaped//|/\\|}"

    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${escaped}|" "$ENV_FILE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
}

set_env_value ENTE_POSTGRES_HOST "$PG_HOST"
set_env_value ENTE_POSTGRES_PORT "$PG_PORT"
set_env_value ENTE_POSTGRES_USER "$PG_USER"
set_env_value ENTE_POSTGRES_PASSWORD "$PG_PASSWORD"
set_env_value ENTE_POSTGRES_DB "$PG_DB"
set_env_value ENTE_S3_BUCKET "$S3_BUCKET"
set_env_value ENTE_S3_REGION "$S3_REGION"
set_env_value ENTE_S3_ACCESS_KEY "$S3_ACCESS_KEY"
set_env_value ENTE_S3_SECRET_KEY "$S3_SECRET_KEY"
set_env_value ENTE_JWT_SECRET "$JWT_SECRET"
set_env_value ENTE_KEY_ENCRYPTION "$KEY_ENCRYPTION"
set_env_value ENTE_KEY_HASH "$KEY_HASH"
set_env_value ENTE_SMTP_USERNAME "$SMTP_USERNAME"
set_env_value ENTE_SMTP_PASSWORD "$SMTP_PASSWORD"

# Generate museum.yaml from template
"$SCRIPT_DIR/generate-museum-yaml.sh" "$PROJECT_DIR"

# Create S3 bucket
if [ "$SKIP_S3" = false ]; then
    echo "Creating S3 bucket: $S3_BUCKET..."
    if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        echo "Bucket $S3_BUCKET already exists."
    else
        if [ "$S3_REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "$S3_BUCKET"
        else
            aws s3api create-bucket --bucket "$S3_BUCKET" \
                --region "$S3_REGION" \
                --create-bucket-configuration LocationConstraint="$S3_REGION"
        fi
        echo "Bucket $S3_BUCKET created."
    fi
fi

echo ""
echo "=== Nginx Configuration ==="
echo ""

NGINX_DIR="$PROJECT_DIR/nginx"

echo "Symlinking Nginx configs..."
for config in photos.thonbecker.biz photos-api.thonbecker.biz; do
    target="/etc/nginx/sites-enabled/$config"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        echo "Refusing to replace regular nginx file: $target" >&2
        exit 1
    fi
    sudo ln -sfn "$NGINX_DIR/$config" "$target"
done

echo "Testing Nginx configuration..."
sudo nginx -t

echo "Reloading Nginx..."
sudo systemctl reload nginx

echo ""
echo "Ensure Let’s Encrypt certificates exist using Cloudflare DNS-01:"
echo "  sudo apt install python3-certbot-dns-cloudflare -y"
echo "  sudo certbot certonly --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini --cert-name photos.thonbecker.biz-0001 -d photos.thonbecker.biz -d photos-api.thonbecker.biz"
echo ""

echo "Starting Ente containers..."
cd "$PROJECT_DIR"
docker compose up -d ente-museum ente-web

echo ""
echo "=== Setup Complete ==="
echo "Access Ente Photos at: https://photos.thonbecker.biz (after Nginx/SSL setup)"
