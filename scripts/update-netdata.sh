#!/bin/bash
set -euo pipefail

get_installed_version() {
    dpkg-query -W -f='${Version}\n' netdata 2>/dev/null || true
}

wait_for_netdata() {
    local attempts=15
    local delay=2
    local url="http://127.0.0.1:19999"

    for ((i=1; i<=attempts; i++)); do
        if curl -fsS -o /dev/null "$url"; then
            echo "Netdata is responding on $url"
            return 0
        fi
        sleep "$delay"
    done

    echo "Netdata did not become ready on $url after $((attempts * delay)) seconds."
    return 1
}

echo "=========================================="
echo "Updating Netdata"
echo "=========================================="
echo ""

if ! command -v apt-get >/dev/null 2>&1; then
    echo "This script requires apt-get."
    exit 1
fi

CURRENT_VERSION="$(get_installed_version)"
if [ -z "$CURRENT_VERSION" ]; then
    echo "Netdata is not installed on this host."
    echo "Install it first, then rerun this script."
    exit 1
fi

echo "Step 1: Refreshing apt package metadata..."
sudo apt-get update

echo ""
echo "Step 2: Checking available Netdata version..."
CANDIDATE_VERSION="$(apt-cache policy netdata | awk '/Candidate:/ {print $2}')"
if [ -z "$CANDIDATE_VERSION" ] || [ "$CANDIDATE_VERSION" = "(none)" ]; then
    echo "No Netdata package candidate is available from apt."
    exit 1
fi

echo "Installed: $CURRENT_VERSION"
echo "Candidate: $CANDIDATE_VERSION"

if [ "$CURRENT_VERSION" = "$CANDIDATE_VERSION" ]; then
    echo ""
    echo "Netdata is already up to date."
    exit 0
fi

echo ""
echo "Step 3: Upgrading Netdata package..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y netdata

echo ""
echo "Step 4: Restarting Netdata..."
sudo systemctl restart netdata

echo ""
echo "Step 5: Verifying service status..."
NEW_VERSION="$(get_installed_version)"
echo "Updated: $CURRENT_VERSION -> $NEW_VERSION"
sudo systemctl --no-pager --full status netdata

echo ""
echo "Step 6: Waiting for Netdata HTTP endpoint..."
wait_for_netdata
