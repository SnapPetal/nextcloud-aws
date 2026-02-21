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
ENTE_DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')

echo ""

# Prompt for S3 configuration
read -rp "S3 bucket name for Ente photos: " S3_BUCKET
read -rp "S3 region [us-east-1]: " S3_REGION
S3_REGION="${S3_REGION:-us-east-1}"
read -rp "S3 access key: " S3_ACCESS_KEY
read -rsp "S3 secret key: " S3_SECRET_KEY
echo ""

# Prompt for Postgres configuration
read -rp "Ente Postgres user [ente]: " PG_USER
PG_USER="${PG_USER:-ente}"
read -rp "Ente Postgres database [ente_db]: " PG_DB
PG_DB="${PG_DB:-ente_db}"

# Prompt for SMTP configuration
read -rp "SMTP email (Gmail address): " SMTP_USERNAME
read -rsp "SMTP app password: " SMTP_PASSWORD
echo ""

echo ""
echo "Updating .env..."

# Append Ente variables to .env if not already present
if grep -q "ENTE_POSTGRES_USER" "$ENV_FILE" 2>/dev/null; then
    echo "Ente variables already exist in .env — updating..."
    sed -i "s/^ENTE_POSTGRES_USER=.*/ENTE_POSTGRES_USER=$PG_USER/" "$ENV_FILE"
    sed -i "s/^ENTE_POSTGRES_PASSWORD=.*/ENTE_POSTGRES_PASSWORD=$ENTE_DB_PASSWORD/" "$ENV_FILE"
    sed -i "s/^ENTE_POSTGRES_DB=.*/ENTE_POSTGRES_DB=$PG_DB/" "$ENV_FILE"
    sed -i "s/^ENTE_S3_BUCKET=.*/ENTE_S3_BUCKET=$S3_BUCKET/" "$ENV_FILE"
    sed -i "s|^ENTE_S3_REGION=.*|ENTE_S3_REGION=$S3_REGION|" "$ENV_FILE"
    sed -i "s/^ENTE_S3_ACCESS_KEY=.*/ENTE_S3_ACCESS_KEY=$S3_ACCESS_KEY/" "$ENV_FILE"
    sed -i "s|^ENTE_S3_SECRET_KEY=.*|ENTE_S3_SECRET_KEY=$S3_SECRET_KEY|" "$ENV_FILE"
    sed -i "s/^ENTE_SMTP_USERNAME=.*/ENTE_SMTP_USERNAME=$SMTP_USERNAME/" "$ENV_FILE"
    sed -i "s|^ENTE_SMTP_PASSWORD=.*|ENTE_SMTP_PASSWORD=$SMTP_PASSWORD|" "$ENV_FILE"
else
    cat >> "$ENV_FILE" << EOF

# Ente Configuration
ENTE_POSTGRES_USER=$PG_USER
ENTE_POSTGRES_PASSWORD=$ENTE_DB_PASSWORD
ENTE_POSTGRES_DB=$PG_DB
ENTE_S3_BUCKET=$S3_BUCKET
ENTE_S3_REGION=$S3_REGION
ENTE_S3_ACCESS_KEY=$S3_ACCESS_KEY
ENTE_S3_SECRET_KEY=$S3_SECRET_KEY
ENTE_JWT_SECRET=$JWT_SECRET
ENTE_KEY_ENCRYPTION=$KEY_ENCRYPTION
ENTE_KEY_HASH=$KEY_HASH
ENTE_SMTP_USERNAME=$SMTP_USERNAME
ENTE_SMTP_PASSWORD=$SMTP_PASSWORD
EOF
fi

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
sudo ln -sf "$NGINX_DIR/photos.thonbecker.biz" /etc/nginx/sites-enabled/photos.thonbecker.biz
sudo ln -sf "$NGINX_DIR/api.photos.thonbecker.biz" /etc/nginx/sites-enabled/api.photos.thonbecker.biz

echo "Testing Nginx configuration..."
sudo nginx -t

echo "Reloading Nginx..."
sudo systemctl reload nginx

echo ""
echo "Run certbot to enable SSL:"
echo "  sudo certbot --nginx -d photos.thonbecker.biz -d api.photos.thonbecker.biz"
echo ""

echo "Starting Ente containers..."
cd "$PROJECT_DIR"
docker compose up -d ente-postgres ente-museum ente-web

echo ""
echo "=== Setup Complete ==="
echo "Access Ente Photos at: https://photos.thonbecker.biz (after Nginx/SSL setup)"
