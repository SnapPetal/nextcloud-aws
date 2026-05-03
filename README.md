# Self-Hosted Services on AWS Lightsail

Multi-service self-hosted stack on AWS Lightsail using Docker, Nginx, and Cloudflare.

## Architecture

```
Internet → Cloudflare (proxy) → Nginx (host, SSL via Certbot) → Docker bridge (nextcloud-net)
  cloud.thonbecker.biz        → 127.0.0.1:8080 (Nextcloud)
  thonbecker.biz              → 127.0.0.1:3003 (Personal Website)
  photos.thonbecker.biz       → 127.0.0.1:3000 (Ente Web)
  photos-api.thonbecker.biz   → 127.0.0.1:8082 (Ente Museum API)
  status.thonbecker.biz       → 127.0.0.1:19999 (Netdata)
  vault.thonbecker.biz        → 127.0.0.1:3002 (Vaultwarden)
```

### Services

**Nextcloud** — Self-hosted cloud storage and collaboration
- **nextcloud-app** — Custom Dockerfile (nextcloud:apache + ffmpeg/ghostscript/imagemagick/supervisor)
- **nextcloud-db** — MariaDB 10.11
- **nextcloud-redis** — Redis Alpine, caching + file locking
- **nextcloud-clamav** — ClamAV antivirus scanning for uploaded files

**Ente Photos** — End-to-end encrypted photo storage
- **ente-museum** — Ente API server
- **ente-postgres** — PostgreSQL 15
- **ente-web** — Ente Photos web app

**Personal Website** — [thonbecker.biz](https://thonbecker.biz)
- **personal-website** — Spring Boot app from public ECR, uses external RDS PostgreSQL and consumes `PERSONAL_*` plus `SKATETRICKS_*` env vars for OpenAI-backed AI features and skateboard video upload/transcoding/frame analysis

**Vaultwarden** — Self-hosted Bitwarden-compatible password manager
- **vaultwarden** — Password vault with browser extension, mobile, and desktop client support

**Netdata** — Host-level observability (native systemd service, not containerized)
- Alerts via AWS SNS → email
- HTTP health checks for all services (localhost)
- Upgrade with `./scripts/update-netdata.sh`

All six domains are Cloudflare-proxied. SSL terminates at nginx via Certbot.

## PersonalWeb OpenAI Secret

The PersonalWeb OpenAI API key is stored in AWS Secrets Manager as `personalweb/openai-api-key`.
Before restarting `personal-website`, sync it into the local `.env` file:

```bash
./scripts/sync-personalweb-openai-secret.sh
```

The script uses `PERSONAL_AWS_ACCESS_KEY_ID`, `PERSONAL_AWS_SECRET_ACCESS_KEY`, and `PERSONAL_AWS_REGION` from `.env` to read the secret, then writes `PERSONAL_OPENAI_API_KEY` and default model variables for Docker Compose.

## Prerequisites

1. AWS Lightsail account
2. Domain: `thonbecker.biz` with Cloudflare DNS
3. GitHub account (for automated deployments)

## Quick Start

**See [QUICKSTART.md](QUICKSTART.md)** for step-by-step setup instructions.

```bash
# Clone and configure
git clone https://github.com/SnapPetal/nextcloud-aws.git
cd nextcloud-aws
cp .env.example .env
# Edit .env with your values

# Deploy
docker compose up -d
```

## Management

### Common Commands

```bash
# Build and deploy
docker compose up -d
docker compose build --pull app

# Nextcloud OCC commands (always as www-data)
docker compose exec -u www-data app php occ status
docker compose exec -u www-data app php occ maintenance:mode --on
docker compose exec -u www-data app php occ maintenance:mode --off

# Interactive maintenance menu
./scripts/maintenance.sh

# Update (pull latest images + rebuild app)
./scripts/update-server.sh

# Database backup to S3 (MariaDB + PostgreSQL + Vaultwarden SQLite)
./scripts/backup-to-s3.sh

# Reload nginx after config changes
sudo systemctl reload nginx

# Netdata
sudo systemctl restart netdata
./scripts/update-netdata.sh

# SSL certificate renewal
sudo certbot renew --dry-run
```

## Backups

`scripts/backup-to-s3.sh` runs nightly at 02:00 via cron:
- MariaDB → S3
- PostgreSQL (Ente) → S3
- SQLite (Vaultwarden) → S3

Keeps last 3 local copies in `/var/lib/nextcloud/data/backups/`.

## CI/CD

Push to `main` triggers GitHub Actions deployment:
1. Pulls latest code on server
2. Restarts Netdata if config changed
3. Pulls latest Docker images
4. Rebuilds Nextcloud app image
5. Restarts changed containers
6. Reloads nginx
7. Verifies all 9 containers are running

Uses secrets: `LIGHTSAIL_HOST`, `LIGHTSAIL_USER`, `LIGHTSAIL_SSH_KEY`.

Dependabot checks weekly for GitHub Actions and Docker base image updates.

## Infrastructure

### Instance

| Resource | Specification | Cost |
|----------|--------------|------|
| Lightsail Instance | 16 GB RAM, 4 vCPU | $80/mo |
| Root Disk | 320 GB SSD (included) | $0 |
| Static IP | IPv4 | Free |
| SSL Certificates | Let's Encrypt (Certbot) | Free |
| RDS (Personal Website) | PostgreSQL | Variable |
| **Total** | | **~$80/mo + RDS** |

### Storage

- **Root filesystem** — All data under `/var/lib/nextcloud/`: app files, databases, user data, and backups

### Nginx

Virtual host configs in `nginx/`, symlinked to `/etc/nginx/sites-enabled/`:

```
nginx/nextcloud                  → cloud.thonbecker.biz
nginx/www.thonbecker.biz         → thonbecker.biz
nginx/photos.thonbecker.biz      → photos.thonbecker.biz
nginx/photos-api.thonbecker.biz  → photos-api.thonbecker.biz
nginx/status.thonbecker.biz      → status.thonbecker.biz
nginx/vault.thonbecker.biz       → vault.thonbecker.biz
```

## Project Structure

```
nextcloud-aws/
├── .github/workflows/
│   └── deploy.yml              # GitHub Actions deployment
├── netdata/
│   ├── netdata.conf            # Netdata configuration
│   ├── health_alarm_notify.conf # SNS alert notifications
│   └── go.d/httpcheck.conf     # HTTP health checks (localhost)
├── nginx/
│   ├── nextcloud               # cloud.thonbecker.biz
│   ├── www.thonbecker.biz      # thonbecker.biz
│   ├── photos.thonbecker.biz   # photos.thonbecker.biz
│   ├── photos-api.thonbecker.biz # photos-api.thonbecker.biz
│   ├── status.thonbecker.biz   # status.thonbecker.biz
│   └── vault.thonbecker.biz    # vault.thonbecker.biz
├── scripts/
│   ├── backup-to-s3.sh         # Database backup to S3
│   ├── generate-museum-yaml.sh # Ente Museum config generator
│   ├── maintenance.sh          # Interactive maintenance menu
│   ├── setup-ente.sh           # Ente Photos setup (one-time)
│   ├── setup-server.sh         # Initial server setup
│   └── update-server.sh        # Server update script
├── docker-compose.yml          # All 9 containers
├── Dockerfile                  # Custom Nextcloud image
├── supervisord.conf            # Apache + cron in app container
├── .env.example                # Environment variables template
├── CLAUDE.md                   # Claude Code project instructions
├── QUICKSTART.md               # Setup guide
└── README.md                   # This file
```

## SSH Access

```bash
ssh -i ~/.ssh/lightsail.pem ubuntu@18.213.161.133
```

## Resources

- **Nextcloud**: https://cloud.thonbecker.biz
- **Personal Website**: https://thonbecker.biz
- **Photos**: https://photos.thonbecker.biz
- **Password Vault**: https://vault.thonbecker.biz
- **Monitoring**: https://status.thonbecker.biz
- **GitHub**: https://github.com/SnapPetal/nextcloud-aws

## License

MIT
