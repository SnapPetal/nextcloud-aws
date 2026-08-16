#!/bin/bash
# Update server with latest changes from GitHub

set -e

echo "=========================================="
echo "Updating Nextcloud Server"
echo "=========================================="
echo ""

cd ~/nextcloud-aws

echo "Step 1: Pulling latest code from GitHub..."
echo "-----------------------------------"
git pull origin main
echo "✅ Code updated"

echo ""
echo "Step 2: Updating Netdata..."
echo "-----------------------------------"
./scripts/update-netdata.sh
echo "✅ Netdata updated"

echo ""
echo "Step 3: Syncing PersonalWeb OpenAI secret..."
echo "-----------------------------------"
./scripts/sync-personalweb-openai-secret.sh
echo "✅ PersonalWeb OpenAI secret synced"

echo ""
echo "Step 4: Pulling latest images and rebuilding (including SearXNG)..."
echo "-----------------------------------"
if [ ! -f searxng/core-config/limiter.toml ]; then
    echo "ERROR: searxng/core-config/limiter.toml is missing"
    echo "SearXNG limiter configuration is required when SEARXNG_LIMITER=true."
    exit 1
fi
docker compose pull
docker compose build --pull --no-cache
docker compose up -d --remove-orphans

# SearXNG reads limiter.toml only during startup. Recreate it explicitly so
# weekly redeploys apply configuration changes even when the image is unchanged.
docker compose up -d --force-recreate searxng

echo ""
echo "Step 5: Waiting for Nextcloud to be ready..."
echo "-----------------------------------"
sleep 10

# Wait for healthcheck
for i in {1..30}; do
    if docker compose exec -T app curl -f http://localhost/status.php > /dev/null 2>&1; then
        echo "✅ Nextcloud is ready"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

./scripts/configure-nextcloud-valkey.sh
sudo systemctl reload nginx
docker image prune -f

echo ""
echo "=========================================="
echo "✅ Server Updated Successfully!"
echo "=========================================="
echo ""
echo "Access your Nextcloud:"
echo "  https://cloud.thonbecker.biz"
echo ""
