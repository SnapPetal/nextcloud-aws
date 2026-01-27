# Nextcloud on AWS Lightsail with Docker

Production-ready Nextcloud deployment on AWS Lightsail using Docker, with local MariaDB database and Redis caching.

## Architecture

```
Internet → cloud.thonbecker.biz (HTTPS) → Lightsail Instance → Nextcloud + Redis + MariaDB
```

### Components
- **Nextcloud App**: Official `nextcloud:apache` Docker image
- **Redis Cache**: Lightweight caching for improved performance and file locking
- **Database**: Local MariaDB 10.11 container (no external database needed)
- **Storage**: Separate Lightsail block storage volume (300 GB) for persistent data

## Features

- Local MariaDB database for low latency
- Redis caching for optimal performance
- Automated GitHub Actions deployment
- SSL/TLS via Let's Encrypt (Certbot)
- Persistent storage on separate volume
- Health checks and monitoring
- Interactive maintenance scripts

## Quick Start

**See [QUICKSTART.md](QUICKSTART.md)** for step-by-step setup instructions tailored to your domain: `cloud.thonbecker.biz`

## Prerequisites

1. AWS Lightsail account
2. Domain name: `thonbecker.biz` (configured)
3. GitHub account (for automated deployments)

## Deployment Summary

1. **Create Resources** (15 min)
   - Lightsail instance: Ubuntu 22.04, 8 GB RAM ($44/month)
   - Block storage: 300 GB ($30/month)
   - S3 storage: ~$0.023/GB/month (optional, for external storage)
   - Database: Included (local MariaDB container)

2. **Configure DNS** (5 min)
   - Point `cloud.thonbecker.biz` to instance IP

3. **Run Setup Script** (10 min)
   - Installs Docker, mounts storage, configures environment

4. **Deploy Nextcloud** (5 min)
   - `docker compose up -d`

5. **Install SSL** (5 min)
   - Certbot for Let's Encrypt certificate

**Total time: ~40 minutes**
**Total cost: ~$74/month** (plus S3 if used)

## Management Commands

### Using the Maintenance Script (Recommended)

```bash
cd ~/nextcloud-aws
./scripts/maintenance.sh
```

Interactive menu provides:
- View logs
- Container management
- Updates
- Backups
- Database operations
- Disk usage monitoring

### Manual Commands

#### Container Management
```bash
# View logs
docker compose logs -f

# Restart containers
docker compose restart

# Update to latest Nextcloud
docker compose pull
docker compose up -d
```

#### Nextcloud OCC Commands
```bash
# Check status
docker compose exec -u www-data app php occ status

# Maintenance mode
docker compose exec -u www-data app php occ maintenance:mode --on
docker compose exec -u www-data app php occ maintenance:mode --off

# Add missing database indices
docker compose exec -u www-data app php occ db:add-missing-indices

# Scan files
docker compose exec -u www-data app php occ files:scan --all
```

## Backups

### Automated Backups with Cron

Create backup script:

```bash
nano ~/backup-nextcloud.sh
```

Add:

```bash
#!/bin/bash
DATE=$(date +%Y%m%d)
BACKUP_DIR="/mnt/nextcloud-data/backups"
mkdir -p $BACKUP_DIR

# Backup database
mysqldump -h YOUR_DB_HOST -u dbadmin -pYOUR_PASSWORD nextcloud > $BACKUP_DIR/db-$DATE.sql

# Backup files (optional - can be large)
tar -czf $BACKUP_DIR/files-$DATE.tar.gz -C /mnt/nextcloud-data --exclude='backups' nextcloud data

# Keep only last 30 days
find $BACKUP_DIR -name "*.sql" -mtime +30 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete
```

Make executable and add to cron:

```bash
chmod +x ~/backup-nextcloud.sh
crontab -e
```

Add line:

```
0 2 * * * /home/ubuntu/backup-nextcloud.sh
```

## GitHub Actions Automated Deployment

### Setup

1. Generate SSH key on your Lightsail instance:

```bash
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github-actions -N ""
cat ~/.ssh/github-actions.pub >> ~/.ssh/authorized_keys
cat ~/.ssh/github-actions  # Copy this
```

2. Add GitHub repository secrets:
   - Go to: https://github.com/SnapPetal/nextcloud-aws/settings/secrets/actions
   - Add:
     - `LIGHTSAIL_HOST`: Your instance static IP
     - `LIGHTSAIL_USER`: `ubuntu`
     - `LIGHTSAIL_SSH_KEY`: The private key from step 1

### Usage

Any push to `main` branch will:
- Pull latest changes on server
- Pull latest Docker images
- Restart containers
- Run health checks

Or trigger manually:
- Go to Actions tab → Run workflow

## Monitoring

### Disk Usage
```bash
df -h /mnt/nextcloud-data
du -sh /mnt/nextcloud-data/*
```

### Container Resources
```bash
docker stats
```

### Logs
```bash
# All containers
docker compose logs -f

# Just Nextcloud
docker compose logs -f app

# Just Redis
docker compose logs -f redis
```

## Troubleshooting

### Containers won't start
```bash
docker compose logs
docker compose down
docker compose up -d
```

### Permission issues
```bash
sudo chown -R 33:33 /mnt/nextcloud-data/nextcloud
sudo chown -R 33:33 /mnt/nextcloud-data/data
```

### Database connection failed
- Verify database container is running: `docker compose ps`
- Check database logs: `docker compose logs db`
- Test connection from app container:
  ```bash
  docker compose exec app mysql -h db -u nextcloud -p
  ```

### "Untrusted domain" error
```bash
docker compose exec -u www-data app php occ config:system:set trusted_domains 0 --value=cloud.thonbecker.biz
```

### SSL certificate issues
```bash
# Renew certificate
sudo certbot renew

# Force renewal
sudo certbot renew --force-renewal
```

## Security Best Practices

1. **Keep updated**:
   ```bash
   docker compose pull && docker compose up -d
   sudo apt update && sudo apt upgrade -y
   ```

2. **Enable automatic security updates**:
   ```bash
   sudo apt install unattended-upgrades -y
   sudo dpkg-reconfigure -plow unattended-upgrades
   ```

3. **Firewall rules** (Lightsail console):
   - SSH (22): Your IP only
   - HTTP (80): All (for Let's Encrypt challenges)
   - HTTPS (443): All

4. **Strong passwords**:
   - Database password (20+ characters)
   - Nextcloud admin password
   - Enable 2FA in Nextcloud settings

5. **Regular backups**:
   - Daily database backups
   - Weekly Lightsail snapshots
   - Store critical backups off-site (S3)

## Performance Tuning

For more users or larger files, edit `docker-compose.yml`:

```yaml
environment:
  - PHP_MEMORY_LIMIT=1G          # Default: 512M
  - PHP_UPLOAD_LIMIT=20G         # Default: 10G
  - APACHE_BODY_LIMIT=21474836480 # Default: 10G
```

Then restart:
```bash
docker compose up -d
```

## Upgrading Nextcloud

### Minor Updates
```bash
docker compose pull
docker compose up -d
```

### Major Version Upgrades
```bash
# 1. Backup first
./scripts/maintenance.sh  # Choose backup option

# 2. Enable maintenance mode
docker compose exec -u www-data app php occ maintenance:mode --on

# 3. Update
docker compose pull
docker compose up -d

# 4. Run upgrade
docker compose exec -u www-data app php occ upgrade

# 5. Disable maintenance mode
docker compose exec -u www-data app php occ maintenance:mode --off
```

## Cost Breakdown

Monthly AWS costs:

| Resource | Specification | Cost |
|----------|--------------|------|
| Lightsail Instance | 8 GB RAM, 2 vCPU, Ubuntu 22.04 | $44 |
| Block Storage | 300 GB SSD | $30 |
| S3 Storage | ~$0.023/GB/month (optional) | Variable |
| Database | Local MariaDB (included) | $0 |
| Static IP | IPv4 | Free |
| SSL Certificate | Let's Encrypt | Free |
| **Total** | | **$74/month + S3** |

## Photo & Video Performance

**Current setup optimized for large photo collections:**
- 8 GB RAM / 2 vCPU instance
- PHP memory: 4 GB
- Opcache enabled (512 MB) for faster performance
- Preview generation scripts included
- Recognize app for AI-powered face/object detection
- S3 external storage for cloud backup

**Features:**
- Fast photo browsing with automatic thumbnail generation
- AI face recognition and object detection via Recognize app
- Video preview support
- S3 cloud storage integration
- Mobile app support

**See:** [docs/PHOTO-VIDEO-OPTIMIZATION.md](docs/PHOTO-VIDEO-OPTIMIZATION.md) for complete optimization guide

## Scaling Options

**Current instance:** 8 GB RAM, 2 vCPUs ($44/month)

**Further scaling options:**

1. **Upgrade to 16 GB RAM** ($80/month):
   - Better for heavy concurrent usage
   - Faster face recognition
   - Better video transcoding

2. **Expand storage** (via snapshot method):
   - Current: 300 GB
   - Can expand to 512 GB (~$50/month) or more
   - See PRODUCTION-SETUP.md for resize procedure

## Project Structure

```
nextcloud-aws/
├── .github/workflows/
│   └── deploy.yml                    # GitHub Actions deployment
├── docs/
│   ├── NGINX-SETUP.md                # Nginx reverse proxy configuration
│   ├── PHOTO-VIDEO-OPTIMIZATION.md   # Photo/video performance guide
│   └── CLOUDFRONT-ALB-SETUP.md       # Advanced: CloudFront/ALB (optional)
├── scripts/
│   ├── setup-server.sh               # Initial server setup
│   ├── maintenance.sh                # Interactive maintenance menu
│   ├── generate-previews.sh          # Photo preview generation
│   ├── setup-auto-previews.sh        # Configure automatic thumbnails
│   └── setup-face-recognition.sh     # Configure AI face recognition
├── docker-compose.yml                # Docker Compose configuration
├── .env.example                      # Environment variables template
├── PRODUCTION-SETUP.md               # Production infrastructure docs
├── QUICKSTART.md                     # Quick start guide
└── README.md                         # This file
```

## Resources

- **Your Nextcloud**: https://cloud.thonbecker.biz
- **GitHub Repository**: https://github.com/SnapPetal/nextcloud-aws
- [Nextcloud Documentation](https://docs.nextcloud.com/)
- [AWS Lightsail Documentation](https://docs.aws.amazon.com/lightsail/)
- [Docker Documentation](https://docs.docker.com/)

## Support

For issues:
1. Check logs: `docker compose logs -f`
2. Review [Troubleshooting](#troubleshooting) section
3. Check Nextcloud forums: https://help.nextcloud.com/
4. Open issue on GitHub

## License

MIT

## Contributing

Pull requests welcome! Please open an issue first to discuss changes.
