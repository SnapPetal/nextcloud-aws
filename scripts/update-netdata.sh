#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Updating Netdata"
echo "=========================================="
echo ""

if ! command -v apt-get >/dev/null 2>&1; then
    echo "This script requires apt-get."
    exit 1
fi

echo "Step 1: Refreshing apt package metadata..."
sudo apt-get update

echo ""
echo "Step 2: Upgrading Netdata package..."
sudo apt-get install --only-upgrade -y netdata

echo ""
echo "Step 3: Restarting Netdata..."
sudo systemctl restart netdata

echo ""
echo "Step 4: Verifying service status..."
sudo systemctl --no-pager --full status netdata
