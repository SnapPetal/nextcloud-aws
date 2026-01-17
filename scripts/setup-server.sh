#!/bin/bash
set -e

echo "========================================="
echo "Nextcloud AWS Lightsail Setup Script"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Please do not run as root. Run as your regular user.${NC}"
    exit 1
fi

echo -e "${GREEN}Step 1: Updating system packages${NC}"
sudo apt update && sudo apt upgrade -y

echo ""
echo -e "${GREEN}Step 2: Installing Docker${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    echo -e "${YELLOW}Docker installed. You may need to log out and back in for group changes to take effect.${NC}"
else
    echo "Docker is already installed"
fi

echo ""
echo -e "${GREEN}Step 3: Installing Docker Compose${NC}"
if ! docker compose version &> /dev/null; then
    sudo apt install docker-compose-plugin -y
else
    echo "Docker Compose is already installed"
fi

echo ""
echo -e "${GREEN}Step 4: Finding attached storage volume${NC}"
echo "Available disks:"
lsblk
echo ""
read -p "Enter the device name for your data volume (e.g., xvdf, sdb) or press Enter to skip: " DEVICE_NAME

if [ -n "$DEVICE_NAME" ]; then
    DEVICE_PATH="/dev/${DEVICE_NAME}"

    if [ ! -b "$DEVICE_PATH" ]; then
        echo -e "${RED}Device $DEVICE_PATH not found!${NC}"
        exit 1
    fi

    # Check if device has a filesystem
    if ! sudo blkid "$DEVICE_PATH" | grep -q "TYPE="; then
        echo -e "${YELLOW}No filesystem detected on $DEVICE_PATH${NC}"
        read -p "Format this device? This will ERASE ALL DATA! (yes/no): " CONFIRM
        if [ "$CONFIRM" = "yes" ]; then
            echo -e "${GREEN}Formatting $DEVICE_PATH...${NC}"
            sudo mkfs.ext4 "$DEVICE_PATH"
        else
            echo "Exiting without formatting"
            exit 1
        fi
    fi

    echo ""
    echo -e "${GREEN}Step 5: Mounting storage volume${NC}"
    DATA_MOUNT="/mnt/nextcloud-data"
    sudo mkdir -p "$DATA_MOUNT"

    # Mount the device
    if ! mountpoint -q "$DATA_MOUNT"; then
        sudo mount "$DEVICE_PATH" "$DATA_MOUNT"
        echo "Mounted $DEVICE_PATH to $DATA_MOUNT"
    fi

    # Add to fstab for persistence
    DEVICE_UUID=$(sudo blkid -s UUID -o value "$DEVICE_PATH")
    FSTAB_ENTRY="UUID=$DEVICE_UUID $DATA_MOUNT ext4 defaults,nofail 0 2"

    if ! grep -q "$DEVICE_UUID" /etc/fstab; then
        echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab
        echo "Added entry to /etc/fstab for automatic mounting"
    fi
else
    DATA_MOUNT="/mnt/nextcloud-data"
    echo -e "${YELLOW}Skipping volume setup. Using $DATA_MOUNT${NC}"
    sudo mkdir -p "$DATA_MOUNT"
fi

echo ""
echo -e "${GREEN}Step 6: Creating directory structure${NC}"
sudo mkdir -p "$DATA_MOUNT"/{nextcloud,data,certs,backups}
sudo chown -R 33:33 "$DATA_MOUNT"/{nextcloud,data}
sudo chmod 755 "$DATA_MOUNT"

echo ""
echo -e "${GREEN}Step 7: Cloning repository${NC}"
if [ ! -d "$HOME/nextcloud-aws" ]; then
    read -p "Enter your GitHub repository URL: " REPO_URL
    git clone "$REPO_URL" "$HOME/nextcloud-aws"
    cd "$HOME/nextcloud-aws"
else
    echo "Repository already exists at $HOME/nextcloud-aws"
    cd "$HOME/nextcloud-aws"
fi

echo ""
echo -e "${GREEN}Step 8: Setting up environment file${NC}"
if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "${YELLOW}Please edit .env file with your configuration:${NC}"
    echo "  - Set your domain name"
    echo "  - Set your Lightsail database connection details (DB_HOST, DB_NAME, DB_USER, DB_PASSWORD)"
    echo "  - Update DATA_PATH if needed (current: $DATA_MOUNT)"
    echo ""
    read -p "Press Enter to edit .env file..."
    ${EDITOR:-nano} .env
else
    echo ".env file already exists"
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Create a Lightsail managed database (MySQL or PostgreSQL)"
echo "2. Update .env file with database connection details"
echo "3. Configure your DNS to point to this server's IP"
echo "4. Start Nextcloud: cd ~/nextcloud-aws && docker compose up -d"
echo "5. Check logs: docker compose logs -f"
echo "6. Access Nextcloud at: https://your-domain.com"
echo ""
echo -e "${YELLOW}Note: If you just added yourself to the docker group, log out and back in before running docker commands.${NC}"
