#!/bin/bash

# Configure Nextcloud to use the shared Valkey service.

set -euo pipefail

cd "$(dirname "$0")/.."

for attempt in {1..30}; do
    if docker compose exec -T -u www-data app php occ status >/dev/null 2>&1; then
        docker compose exec -T -u www-data app php occ config:system:set redis host --value=valkey
        docker compose exec -T -u www-data app php occ config:system:set redis dbindex --type=integer --value=0
        echo "Nextcloud configured to use shared Valkey (database 0)."
        exit 0
    fi
    sleep 2
done

echo "Nextcloud did not become ready while configuring shared Valkey." >&2
exit 1
