#!/bin/bash
set -euo pipefail

# Install and configure Nextcloud Client Push. The push daemon is managed by
# supervisord inside the app container and is published on localhost:7867.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PUBLIC_URL="${1:-https://cloud.thonbecker.biz/push}"

cd "$PROJECT_DIR"

occ() {
    docker compose exec -T -u www-data app php occ "$@"
}

if ! docker compose ps --status running --services | grep -qx app; then
    echo "Error: the app service is not running." >&2
    exit 1
fi

if ! occ app:list | grep -qE '^  - notify_push:'; then
    echo "Installing notify_push..."
    occ app:install notify_push
fi
occ app:enable notify_push

BINARY="/var/www/html/custom_apps/notify_push/bin/x86_64/notify_push"
if ! docker compose exec -T app test -x "$BINARY"; then
    echo "Error: notify_push binary is missing or not executable at $BINARY" >&2
    exit 1
fi

# Supervisor may have exhausted its retries before the app was installed.
echo "Restarting the app container so supervisord starts notify_push..."
docker compose restart app

for _ in $(seq 1 60); do
    if occ status >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

if ! occ status >/dev/null 2>&1; then
    echo "Error: Nextcloud did not become ready after the restart." >&2
    exit 1
fi

occ notify_push:setup "$PUBLIC_URL"
docker compose exec -T app supervisorctl -c /supervisord.conf status notify_push

echo "Client Push configured at $PUBLIC_URL"
echo "The tracked nginx/nextcloud config already proxies /push/ to port 7867."
