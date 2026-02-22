# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure-as-configuration repository for a self-hosted Nextcloud instance on AWS Lightsail. No application source code, build system, or test suite — this is Docker config, shell scripts, and documentation.

**Production:** https://cloud.thonbecker.biz

## Architecture

```
Internet (HTTPS 443) → Nginx (host, SSL via Certbot) → Docker bridge (nextcloud-net)
  cloud.thonbecker.biz        → 127.0.0.1:8080 (Nextcloud)
  photos.thonbecker.biz       → 127.0.0.1:3000 (Ente Web)
  api.photos.thonbecker.biz   → 127.0.0.1:8082 (Ente Museum API)
  status.thonbecker.biz       → 127.0.0.1:19999 (Netdata)
  vault.thonbecker.biz        → 127.0.0.1:3002 (Vaultwarden)
```

Eight containers in docker-compose.yml:

**Nextcloud:**
- **nextcloud-app** — Custom Dockerfile (nextcloud:apache + ffmpeg/ghostscript/imagemagick/supervisor), binds 127.0.0.1:8080
- **nextcloud-db** — MariaDB 10.11, data at /var/lib/nextcloud/mysql
- **nextcloud-redis** — Redis Alpine, caching + file locking
- **nextcloud-clamav** — ClamAV antivirus daemon on port 3310

**Observability (native host service, not containerized):**
- **netdata** — Native systemd service (installed via apt from Netdata repo), binds 127.0.0.1:19999 (proxied at status.thonbecker.biz). Alerts via AWS SNS. Config symlinked from `netdata/` into `/etc/netdata/`. AWS credentials injected via `/etc/systemd/system/netdata.service.d/override.conf`.

**Ente Photos:**
- **ente-museum** — Ente API server, binds 127.0.0.1:8082 (proxied at api.photos.thonbecker.biz)
- **ente-postgres** — PostgreSQL 15 for Ente metadata
- **ente-web** — Ente Photos web app, binds 127.0.0.1:3000 (proxied at photos.thonbecker.biz)

**Vaultwarden:**
- **vaultwarden** — Bitwarden-compatible password manager (vaultwarden/server), binds 127.0.0.1:3002 (proxied at vault.thonbecker.biz)

**Storage split:** Root filesystem holds app files (`/var/lib/nextcloud/app`) and DB (`/var/lib/nextcloud/mysql`). A 300 GB Lightsail block storage volume at `/mnt/nextcloud-data` holds user data and backups.

## Key Commands

```bash
# Build and deploy
docker compose up -d
docker compose build --pull app        # rebuild custom image with latest base

# OCC commands (Nextcloud CLI) — always as www-data
docker compose exec -u www-data app php occ <command>
docker compose exec -u www-data app php occ status
docker compose exec -u www-data app php occ maintenance:mode --on
docker compose exec -u www-data app php occ maintenance:mode --off

# Interactive maintenance menu
./scripts/maintenance.sh

# Update (pull latest images + rebuild app)
./scripts/update-server.sh

# Database backup to S3 (MariaDB + PostgreSQL)
./scripts/backup-to-s3.sh

# Reload nginx after config changes
sudo systemctl reload nginx

# Netdata (native systemd service — not containerized)
sudo systemctl status netdata
sudo systemctl restart netdata   # after config changes in netdata/
sudo systemctl stop netdata
sudo systemctl start netdata

# SSL certificate renewal (automatic via certbot.timer, twice daily)
sudo certbot renew --dry-run   # test
sudo certbot renew             # force manual renewal

# Ente Photos setup (one-time)
./scripts/setup-ente.sh
```

## Configuration

`.env` (gitignored, copy from `.env.example`) provides: DOMAIN, DB_ROOT_PASSWORD, DB_NAME, DB_USER, DB_PASSWORD, DATA_PATH, S3_BUCKET, S3_DB_BACKUP_BUCKET, and ENTE_* variables for Ente Photos (Postgres, S3, JWT, SMTP).

PHP is tuned for 8 GB RAM: `PHP_MEMORY_LIMIT=4G`, `PHP_UPLOAD_LIMIT=10G`, Opcache 512 MB. MariaDB runs with `--transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW` as Nextcloud requires.

## Nginx

All five virtual host configs live in `nginx/` and are symlinked into `/etc/nginx/sites-enabled/`. SSL is managed by Certbot (`authenticator = nginx` for all domains). Do not edit configs in `/etc/nginx/sites-available/` — edit the repo copies in `nginx/` instead.

```
nginx/nextcloud                  → cloud.thonbecker.biz
nginx/status.thonbecker.biz      → status.thonbecker.biz
nginx/photos.thonbecker.biz      → photos.thonbecker.biz
nginx/api.photos.thonbecker.biz  → api.photos.thonbecker.biz
nginx/vault.thonbecker.biz       → vault.thonbecker.biz
```

Vaultwarden serves internally on HTTP port 80. Use the official Bitwarden clients (browser extension, mobile, desktop) pointed at `https://vault.thonbecker.biz`. Admin panel at `https://vault.thonbecker.biz/admin`.

## Vaultwarden User Management

**Admin panel:** `https://vault.thonbecker.biz/admin` — token is `VAULTWARDEN_ADMIN_TOKEN` in `.env`.

**Inviting a user:**
1. Admin panel → **Users** → enter email → **Invite**
2. User receives email, clicks link, creates their account

**Admin diagnostics (`https://vault.thonbecker.biz/admin/diagnostics`):**
- Run in a **private/incognito window** — browser extensions (user-agent spoofers, fingerprint defenders, etc.) intercept XHR responses and cause false "header missing" failures in the HTTP Response Validation section
- All required security headers (`x-frame-options`, `x-content-type-options`, `referrer-policy`, `x-xss-protection`, `x-robots-tag`, `cross-origin-resource-policy`, `content-security-policy`) are set by Vaultwarden natively; nginx only overrides `x-frame-options` and `x-content-type-options` for the main `location /` block
- Connector pages (`*-connector.html`) intentionally omit `x-frame-options` and `content-security-policy` so they can be embedded in iframes for 2FA flows

## Backups

`scripts/backup-to-s3.sh` runs nightly at 02:00 via cron. Backs up all three databases and uploads to S3:
- MariaDB → `s3://${S3_DB_BACKUP_BUCKET}/mariadb/`
- PostgreSQL (Ente) → `s3://${S3_DB_BACKUP_BUCKET}/postgres/`
- SQLite (Vaultwarden) → `s3://${S3_DB_BACKUP_BUCKET}/vaultwarden/`

Keeps last 3 local copies in `/mnt/nextcloud-data/backups/`. Cron log at `/mnt/nextcloud-data/backups/cron.log`.

## CI/CD

`.github/workflows/deploy.yml` — On push to `main`, SSHes into the Lightsail instance, pulls code, pulls latest Docker images, rebuilds app image, restarts stack, reloads nginx, then verifies all 8 containers are running. Uses secrets: `LIGHTSAIL_HOST`, `LIGHTSAIL_USER`, `LIGHTSAIL_SSH_KEY`.

**Deployment safety notes:**
- `docker compose up -d` only restarts containers whose image or config actually changed — services with unchanged images are not touched
- nginx reload runs `nginx -t` first; if any virtual host config has a syntax error the reload is aborted and the existing config stays live (no other services are affected)
- Each nginx virtual host config (`nginx/`) is independent — changes to one virtual host cannot affect any other

Dependabot checks weekly for GitHub Actions and Docker base image updates.

## SSH Access

> **Note for Claude Code:** When running with the working directory `/home/ubuntu/nextcloud-aws`, you are already on the Lightsail server. Do not SSH — run commands directly.

```bash
# SSH into Lightsail instance (only needed from a remote machine)
ssh -i ~/.ssh/lightsail.pem ubuntu@18.213.161.133

# AWS CLI with credentials
aws-vault exec thonbecker -- <command>
```

## Conventions

- Uses `docker compose` v2 plugin syntax (no hyphen), not legacy `docker-compose`
- All scripts assume they run from `~/nextcloud-aws` on the server
- The app container is always rebuilt (not just pulled) on deploy to get the latest nextcloud:apache base
- `supervisord.conf` runs both apache2 and cron inside the app container (runs as root explicitly to suppress supervisord warning)
- Nginx runs on the host (not containerized) handling SSL termination and reverse proxy
- Netdata runs on the host (not containerized) as a native systemd service for true host-level observability
- Trusted proxies configured for RFC-1918 ranges to handle Nginx forwarding
- All nginx virtual host configs are version-controlled in `nginx/` — symlinked from `/etc/nginx/sites-enabled/`
- Netdata configs are version-controlled in `netdata/` — symlinked from `/etc/netdata/` (`netdata.conf`, `health_alarm_notify.conf`, `go.d/httpcheck.conf`)
