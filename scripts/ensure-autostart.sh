#!/bin/bash
# Ensure Docker and Nextcloud start automatically on boot

echo "Setting up automatic startup..."
echo ""

# Enable Docker service
sudo systemctl enable docker
echo "✅ Docker will start on boot"

# Create systemd service for Nextcloud
cat << 'EOF' | sudo tee /etc/systemd/system/nextcloud-docker.service
[Unit]
Description=Nextcloud Docker Compose
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/ubuntu/nextcloud-aws
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
sudo systemctl daemon-reload
sudo systemctl enable nextcloud-docker.service

echo "✅ Nextcloud containers will start automatically on boot"
echo ""
echo "To test:"
echo "  sudo systemctl status nextcloud-docker"
echo ""
