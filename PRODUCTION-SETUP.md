# Production Setup Documentation

This file documents the actual production configuration of cloud.thonbecker.biz.

## Current Infrastructure

**Deployed:** January 2026
**Domain:** https://cloud.thonbecker.biz
**Location:** AWS Lightsail us-east-1a

### Resources

| Resource | Name | Specs | Cost |
|----------|------|-------|------|
| Instance | nextcloud-prod | Ubuntu 22.04, 16 GB RAM, 4 vCPU | $80/month |
| S3 Storage | External storage | ~$0.023/GB/month | Variable |
| Database | Local MariaDB | Container (included) | $0 |
| Static IP | nextcloud-prod-ip | IPv4 | Free |
| RDS | Personal Website DB | PostgreSQL | Variable |
| **Total** | | | **~$80/month + RDS + S3** |

### Storage

All data lives on the root filesystem under `/var/lib/nextcloud/`:

- `app/` — Nextcloud application files
- `mysql/` — MariaDB data
- `data/` — User files and backups (`DATA_PATH` in `.env`)

S3 available for overflow storage if needed.

## Network Configuration

**SSL/TLS:** Let's Encrypt (auto-renews via Certbot)
**Web Server:** Nginx reverse proxy on host
**CDN/Proxy:** Cloudflare (all six domains proxied)

**Container Ports (localhost only):**
- Nextcloud: 127.0.0.1:8080
- Ente Web: 127.0.0.1:3000
- Ente API: 127.0.0.1:8082
- Personal Website: 127.0.0.1:3003
- Vaultwarden: 127.0.0.1:3002
- Netdata: 127.0.0.1:19999 (native service)

**Firewall (Lightsail):**
- Port 22 (SSH): Restricted to admin IP
- Port 80 (HTTP): Open (redirects to HTTPS)
- Port 443 (HTTPS): Open

## Docker Configuration

**Containers (9 total):**
- `nextcloud-app`: Custom Dockerfile (nextcloud:apache + ffmpeg/ghostscript/imagemagick/supervisor)
- `nextcloud-db`: MariaDB 10.11
- `nextcloud-redis`: Redis Alpine (caching + file locking)
- `nextcloud-clamav`: ClamAV antivirus
- `ente-museum`: Ente API server
- `ente-postgres`: PostgreSQL 15
- `ente-web`: Ente Photos web app
- `personal-website`: Spring Boot app from public ECR, configured by `PERSONAL_*` and `SKATETRICKS_*` env vars from `.env`
- `vaultwarden`: Bitwarden-compatible password manager

**Volumes:**
- `/var/lib/nextcloud/app` → `/var/www/html` (application files)
- `/var/lib/nextcloud/data/data` → `/var/www/html/data` (user files)
- `/var/lib/nextcloud/mysql` → `/var/lib/mysql` (MariaDB data)
- `/var/lib/personal-website/videos` → `/app/videos` (video processing)

## Installed Nextcloud Apps

- Calendar (CalDAV sync)
- Contacts (CardDAV sync)
- Photos (timeline view)
- Nextcloud Office (Collabora Online - document editing)
- Files Antivirus (ClamAV integration)
- Files External (S3 storage integration)

## Performance Settings

**PHP:**
- Memory limit: 4G
- Upload limit: 10G
- Execution time: 3600s
- Opcache: Enabled (512 MB)

**Apache:**
- Body limit: 10 GB

**Nginx:**
- Client max body size: 10G
- Timeouts: 600s

**Redis:**
- File locking and caching enabled

## Backup Strategy

**Automated S3 backups (daily at 2:00 AM):**
- MariaDB → `s3://${S3_DB_BACKUP_BUCKET}/mariadb/`
- PostgreSQL → `s3://${S3_DB_BACKUP_BUCKET}/postgres/`
- Vaultwarden SQLite → `s3://${S3_DB_BACKUP_BUCKET}/vaultwarden/`
- 3 local copies retained in `/var/lib/nextcloud/data/backups/`
- S3 objects expire after 7 days (CDK lifecycle rule)

**Instance snapshots:** Manual as needed via Lightsail console

## Monitoring

**Netdata** (native systemd service at status.thonbecker.biz):
- HTTP health checks for all services (via localhost)
- Alerts via AWS SNS → email
- Config in `netdata/`, symlinked to `/etc/netdata/`

**Health checks:**
- Docker container health: `/status.php`
- Disk usage: `df -h /`
- Container stats: `docker stats`

**Logs:**
- Nginx: `/var/log/nginx/`
- Docker: `docker compose logs`
- Nextcloud: Via OCC commands
- Backups: `/var/lib/nextcloud/data/backups/cron.log`

## GitHub Actions

**Workflow:** `.github/workflows/deploy.yml`

**Triggers:** Push to main, manual dispatch

**Actions:**
1. Pull latest code
2. Restart Netdata if config changed
3. Pull latest Docker images
4. Rebuild Nextcloud app image
5. Restart changed containers
6. Reload nginx
7. Verify all 9 containers running

## Access

**Admin user:** thonbecker
**SSH:** `ssh -i ~/.ssh/lightsail.pem ubuntu@18.213.161.133`

## Support Resources

- **Repository:** https://github.com/SnapPetal/nextcloud-aws
- **Nextcloud Docs:** https://docs.nextcloud.com/
- **AWS Lightsail:** https://lightsail.aws.amazon.com/

---

**Last updated:** March 2026
**Instance:** 16 GB RAM, 4 vCPU
**Storage:** Root filesystem + S3
**Status:** Production
