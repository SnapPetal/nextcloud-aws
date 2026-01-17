# Nextcloud on AWS Lightsail with Docker

Production-ready Nextcloud deployment on AWS Lightsail using Docker, with external managed database, Redis caching, and CloudFront/ALB integration for public HTTPS access.

## Architecture

```
Internet → CloudFront/ALB (HTTPS) → Lightsail Instance (HTTP, Private) → Nextcloud
                                                                        ↓
                                                                   Redis Cache
                                                                        ↓
                                                            Lightsail Managed Database
```

### Components
- **Nextcloud App**: `nextcloud:apache` container with built-in Apache web server
- **Redis Cache**: Lightweight caching for improved performance and file locking
- **Database**: AWS Lightsail managed database (MySQL or PostgreSQL)
- **Storage**: Separate Lightsail block storage volume for data persistence
- **Public Access**: CloudFront CDN or Application Load Balancer with SSL/TLS

## Features

- Private Lightsail instance (no public IP required)
- External managed database for reliability
- Redis caching for performance
- Automated GitHub Actions deployment
- SSL/TLS via CloudFront or ALB
- Persistent storage on separate volume
- Health checks and monitoring
- Backup scripts included

## Prerequisites

1. AWS account with Lightsail access
2. Domain name with DNS management
3. GitHub account (for automated deployments)
4. Basic knowledge of AWS services

## Quick Start

### 1. Create AWS Lightsail Resources

#### A. Create Lightsail Instance
- **OS**: Ubuntu 22.04 LTS
- **Plan**: At least $10/month (2 GB RAM recommended)
- **Networking**: Private IP only (no static IP needed)
- **Firewall**:
  - Port 22 (SSH) from your IP
  - Port 80 (HTTP) from ALB security group or VPC range

#### B. Create Lightsail Block Storage
- **Size**: 50-100 GB (depending on storage needs)
- **Attach** to your instance

#### C. Create Lightsail Managed Database
- **Engine**: MySQL 8.0 or PostgreSQL (your choice)
- **Plan**: At least $15/month (Standard)
- **Database name**: `nextcloud`
- **Master username**: `dbadmin`
- **Note** the connection endpoint and password
- **Networking**: Enable public mode OR add Lightsail instance to allowed connections

#### D. Set up CloudFront or ALB
See [CloudFront/ALB Setup Guide](docs/CLOUDFRONT-ALB-SETUP.md) for detailed instructions.

**Quick recommendation**: Use ALB for easier setup and better WebSocket support.

### 2. Initial Server Setup

SSH into your Lightsail instance:

```bash
ssh ubuntu@your-lightsail-private-ip
```

Clone this repository:

```bash
git clone https://github.com/yourusername/nextcloud-aws.git
cd nextcloud-aws
```

Run the automated setup script:

```bash
chmod +x scripts/setup-server.sh
./scripts/setup-server.sh
```

The script will:
- Install Docker and Docker Compose
- Format and mount your storage volume
- Create necessary directories
- Clone the repository
- Set up the `.env` file

### 3. Configure Environment

Edit the `.env` file:

```bash
nano .env
```

Update these values:

```env
# Your public domain name
DOMAIN=nextcloud.yourdomain.com

# Private IP of your Lightsail instance
PRIVATE_IP=10.0.0.10

# Lightsail database connection details
DB_HOST=ls-xxxxxxxxxxxxx.us-east-1.rds.amazonaws.com
DB_NAME=nextcloud
DB_USER=dbadmin
DB_PASSWORD=your_strong_database_password

# Data storage path (where you mounted the volume)
DATA_PATH=/mnt/nextcloud-data
```

### 4. Configure CloudFront or ALB

Follow the detailed guide: [CloudFront/ALB Setup Guide](docs/CLOUDFRONT-ALB-SETUP.md)

**TL;DR for ALB:**
1. Create Application Load Balancer in same VPC
2. Create Target Group pointing to your Lightsail instance on port 80
3. Request SSL certificate in ACM for your domain
4. Create HTTPS listener on ALB with your certificate
5. Configure security groups to allow ALB → Instance traffic
6. Point your domain's DNS to the ALB

### 5. Deploy Nextcloud

Start the containers:

```bash
cd ~/nextcloud-aws
docker compose up -d
```

Check logs:

```bash
docker compose logs -f
```

Verify containers are running:

```bash
docker compose ps
```

### 6. Initial Nextcloud Setup

1. Navigate to `https://your-domain.com` in your browser
2. Create admin account when prompted
3. Database configuration is automatic (via environment variables)
4. Complete the setup wizard

### 7. Post-Installation Configuration

Run these commands to optimize Nextcloud:

```bash
# Add missing database indices
docker compose exec -u www-data app php occ db:add-missing-indices

# Configure background jobs
docker compose exec -u www-data app php occ background:cron

# Disable maintenance mode if enabled
docker compose exec -u www-data app php occ maintenance:mode --off

# Check status
docker compose exec -u www-data app php occ status
```

## GitHub Actions Deployment

### Setup

1. **Generate SSH key for GitHub Actions:**

```bash
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github-actions -N ""
cat ~/.ssh/github-actions.pub >> ~/.ssh/authorized_keys
cat ~/.ssh/github-actions  # Copy this private key
```

2. **Add GitHub Repository Secrets:**

Go to: Repository → Settings → Secrets and variables → Actions

Add these secrets:
- `LIGHTSAIL_HOST`: Your Lightsail instance private IP
- `LIGHTSAIL_USER`: `ubuntu`
- `LIGHTSAIL_SSH_KEY`: The private key from step 1

### Usage

**Automatic deployment on push:**
```bash
git add .
git commit -m "Update configuration"
git push origin main
```

**Manual deployment:**
1. Go to repository → Actions tab
2. Select "Deploy to AWS Lightsail" workflow
3. Click "Run workflow"

The workflow will:
- Pull latest changes on your Lightsail instance
- Pull latest Docker images
- Restart containers with new configuration
- Run health checks

## Management

### Using the Maintenance Script

We provide an interactive maintenance script for common tasks:

```bash
cd ~/nextcloud-aws
chmod +x scripts/maintenance.sh
./scripts/maintenance.sh
```

This menu-driven script includes:
- View logs
- Check status
- Restart containers
- Update containers
- Enable/disable maintenance mode
- Database operations
- Backups
- And more...

### Manual Commands

#### View logs
```bash
docker compose logs -f           # All containers
docker compose logs -f app       # Nextcloud only
docker compose logs -f redis     # Redis only
```

#### Container management
```bash
docker compose ps                # Status
docker compose restart           # Restart all
docker compose restart app       # Restart Nextcloud only
docker compose down              # Stop all
docker compose up -d             # Start all
```

#### Update containers
```bash
docker compose pull              # Pull latest images
docker compose up -d             # Recreate with new images
docker image prune -f            # Clean old images
```

#### Nextcloud OCC commands
```bash
# Status
docker compose exec -u www-data app php occ status

# Maintenance mode
docker compose exec -u www-data app php occ maintenance:mode --on
docker compose exec -u www-data app php occ maintenance:mode --off

# Database operations
docker compose exec -u www-data app php occ db:add-missing-indices
docker compose exec -u www-data app php occ db:convert-filecache-bigint

# File operations
docker compose exec -u www-data app php occ files:scan --all
docker compose exec -u www-data app php occ files:cleanup

# User management
docker compose exec -u www-data app php occ user:list
docker compose exec -u www-data app php occ user:add newuser
```

### Backups

#### Database Backup

Install database client first:
```bash
# For MySQL
sudo apt install mysql-client -y

# For PostgreSQL
sudo apt install postgresql-client -y
```

Create backup:
```bash
# MySQL
mysqldump -h DB_HOST -u DB_USER -p DB_NAME > /mnt/nextcloud-data/backups/nextcloud-$(date +%Y%m%d).sql

# PostgreSQL
pg_dump -h DB_HOST -U DB_USER DB_NAME > /mnt/nextcloud-data/backups/nextcloud-$(date +%Y%m%d).sql
```

#### File Backup

```bash
sudo tar -czf /mnt/nextcloud-data/backups/nextcloud-files-$(date +%Y%m%d).tar.gz \
  -C /mnt/nextcloud-data \
  --exclude='backups' \
  nextcloud data
```

#### Automated Backups

Create a cron job:

```bash
crontab -e
```

Add these lines:

```cron
# Database backup daily at 2 AM
0 2 * * * mysqldump -h DB_HOST -u DB_USER -pPASSWORD DB_NAME > /mnt/nextcloud-data/backups/nextcloud-$(date +\%Y\%m\%d).sql

# File backup weekly on Sunday at 3 AM
0 3 * * 0 tar -czf /mnt/nextcloud-data/backups/nextcloud-files-$(date +\%Y\%m\%d).tar.gz -C /mnt/nextcloud-data --exclude='backups' nextcloud data

# Clean old backups (keep last 30 days)
0 4 * * * find /mnt/nextcloud-data/backups -name "*.sql" -mtime +30 -delete
0 4 * * * find /mnt/nextcloud-data/backups -name "*.tar.gz" -mtime +30 -delete
```

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

### Nextcloud Status
```bash
docker compose exec -u www-data app php occ status
```

### ALB Health
Check in AWS Console: EC2 → Load Balancers → Target Groups → Targets

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
- Verify `.env` file has correct credentials
- Check Lightsail database public mode is enabled OR instance is in allowed connections
- Test connection:
  ```bash
  mysql -h DB_HOST -u DB_USER -p
  # or
  psql -h DB_HOST -U DB_USER
  ```

### "Untrusted domain" error
```bash
docker compose exec -u www-data app php occ config:system:set trusted_domains 0 --value=nextcloud.yourdomain.com
docker compose exec -u www-data app php occ config:system:set trusted_proxies 0 --value=10.0.0.0/8
```

### 502 Bad Gateway from ALB
- Check containers are running: `docker compose ps`
- Verify ALB target health in AWS console
- Check security groups allow ALB → instance traffic on port 80

### Redis connection issues
```bash
docker compose restart redis
docker compose logs redis
```

## Security Best Practices

1. **Keep containers updated**:
   ```bash
   docker compose pull && docker compose up -d
   ```

2. **Enable automatic security updates**:
   ```bash
   sudo apt install unattended-upgrades -y
   sudo dpkg-reconfigure -plow unattended-upgrades
   ```

3. **Configure Lightsail firewall**:
   - SSH (22): Your IP only
   - HTTP (80): ALB security group only
   - No other ports open

4. **Use strong passwords**:
   - Database password
   - Nextcloud admin password
   - Enable 2FA in Nextcloud

5. **Regular backups**:
   - Lightsail instance snapshots (weekly)
   - Database backups (daily)
   - File backups (weekly)
   - Store critical backups in S3

6. **Monitor logs**:
   ```bash
   docker compose logs -f
   ```

## Performance Tuning

### For larger files/more users

Edit `docker-compose.yml` and adjust:

```yaml
environment:
  - PHP_MEMORY_LIMIT=1G
  - PHP_UPLOAD_LIMIT=20G
  - APACHE_BODY_LIMIT=21474836480
```

### Enable Redis for transactional file locking

Already configured! Redis is handling:
- File locking
- Memory caching
- Session storage

## Cost Estimation

Monthly AWS costs (approximate):

| Resource | Specs | Cost |
|----------|-------|------|
| Lightsail Instance | 2 GB RAM, Private | $10 |
| Block Storage | 100 GB | $10 |
| Managed Database | Standard MySQL/PostgreSQL | $15 |
| Application Load Balancer | - | $18 |
| **Total** | | **~$53/month** |

**With CloudFront instead of ALB**: ~$35-40/month (lower traffic)

## Project Structure

```
nextcloud-aws/
├── .github/
│   └── workflows/
│       └── deploy.yml          # GitHub Actions deployment
├── docs/
│   └── CLOUDFRONT-ALB-SETUP.md # CloudFront/ALB setup guide
├── scripts/
│   ├── setup-server.sh         # Initial server setup
│   └── maintenance.sh          # Maintenance menu
├── docker-compose.yml          # Docker Compose config
├── .env.example                # Environment template
├── .gitignore                  # Git ignore rules
└── README.md                   # This file
```

## Upgrading Nextcloud

### Minor Updates (Recommended)

```bash
docker compose pull
docker compose up -d
```

### Major Version Upgrades

1. Backup everything first
2. Enable maintenance mode:
   ```bash
   docker compose exec -u www-data app php occ maintenance:mode --on
   ```
3. Update container:
   ```bash
   docker compose pull
   docker compose up -d
   ```
4. Run upgrade:
   ```bash
   docker compose exec -u www-data app php occ upgrade
   ```
5. Disable maintenance mode:
   ```bash
   docker compose exec -u www-data app php occ maintenance:mode --off
   ```

## Support

- [Nextcloud Documentation](https://docs.nextcloud.com/)
- [Nextcloud Forums](https://help.nextcloud.com/)
- [AWS Lightsail Documentation](https://docs.aws.amazon.com/lightsail/)

## License

MIT

## Contributing

Pull requests welcome! Please open an issue first to discuss changes.
