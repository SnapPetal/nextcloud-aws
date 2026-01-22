#!/bin/bash
# Safe server reboot script for Nextcloud

echo "=========================================="
echo "Safe Nextcloud Server Reboot"
echo "=========================================="
echo ""

cd ~/nextcloud-aws

echo "Step 1: Checking for running processes..."
docker compose ps

echo ""
echo "Step 2: Gracefully stopping containers..."
docker compose down

echo ""
echo "Step 3: Checking if reboot is needed..."
if [ -f /var/run/reboot-required ]; then
    echo "✅ Reboot is required (kernel updates, etc.)"
    cat /var/run/reboot-required.pkgs 2>/dev/null
else
    echo "ℹ️  No reboot required, but proceeding anyway..."
fi

echo ""
echo "Step 4: Server will reboot in 10 seconds..."
echo "   Press Ctrl+C to cancel"
sleep 10

echo ""
echo "Rebooting now..."
sudo reboot
