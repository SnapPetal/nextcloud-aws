#!/bin/bash
set -euo pipefail

# Prepare a fresh Ubuntu Lightsail host for this repository. Run this script
# from an existing checkout; it does not deploy containers or provision the
# external PostgreSQL/S3 resources used by Ente and PersonalWeb.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Please run this as the regular deployment user, not root.${NC}"
    exit 1
fi

echo -e "${GREEN}Step 1: Installing host packages${NC}"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    awscli \
    certbot \
    curl \
    jq \
    nginx \
    python3-certbot-dns-cloudflare \
    sqlite3

echo -e "${GREEN}Step 2: Installing Docker${NC}"
if ! command -v docker >/dev/null 2>&1; then
    INSTALLER="$(mktemp)"
    trap 'rm -f "$INSTALLER"' EXIT
    curl -fsSL https://get.docker.com -o "$INSTALLER"
    sudo sh "$INSTALLER"
    sudo usermod -aG docker "$USER"
    echo -e "${YELLOW}Docker was installed. Log out and back in before deploying.${NC}"
fi

if ! docker compose version >/dev/null 2>&1; then
    sudo apt-get install -y docker-compose-plugin
fi

echo -e "${GREEN}Step 3: Creating persistent directories on the root filesystem${NC}"
sudo install -d -m 0755 \
    /var/lib/nextcloud/app \
    /var/lib/nextcloud/data \
    /var/lib/nextcloud/data/backups \
    /var/lib/nextcloud/data/data \
    /var/lib/nextcloud/mysql \
    /var/lib/personal-website/videos \
    /var/www/thonbecker-static
sudo chown -R 33:33 /var/lib/nextcloud/app /var/lib/nextcloud/data/data

echo -e "${GREEN}Step 4: Preparing the environment file${NC}"
cd "$PROJECT_DIR"
if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "${YELLOW}Created $PROJECT_DIR/.env from .env.example.${NC}"
else
    echo "Keeping existing $PROJECT_DIR/.env"
fi

echo ""
echo -e "${GREEN}Host preparation complete.${NC}"
echo "Next steps:"
echo "1. Fill every required value in $PROJECT_DIR/.env."
echo "2. Provision the external PostgreSQL/S3 dependencies documented in QUICKSTART.md."
echo "3. Generate ente/museum.yaml with ./scripts/generate-museum-yaml.sh."
echo "4. Issue the TLS certificates and enable the repo-managed nginx configs."
echo "5. Run docker compose config -q, then docker compose up -d --wait."
