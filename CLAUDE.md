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
  status.thonbecker.biz       → 127.0.0.1:3001 (Uptime Kuma)
```

Eight containers in docker-compose.yml:

**Nextcloud:**
- **nextcloud-app** — Custom Dockerfile (nextcloud:apache + ffmpeg/ghostscript/imagemagick/supervisor), binds 127.0.0.1:8080
- **nextcloud-db** — MariaDB 10.11, data at /var/lib/nextcloud/mysql
- **nextcloud-redis** — Redis Alpine, caching + file locking
- **nextcloud-clamav** — ClamAV antivirus daemon on port 3310
- **nextcloud-kuma** — Uptime Kuma monitoring, binds 127.0.0.1:3001 (proxied at status.thonbecker.biz)

**Ente Photos:**
- **ente-museum** — Ente API server, binds 127.0.0.1:8082 (proxied at api.photos.thonbecker.biz)
- **ente-postgres** — PostgreSQL 15 for Ente metadata
- **ente-web** — Ente Photos web app, binds 127.0.0.1:3000 (proxied at photos.thonbecker.biz)

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

# Database backup to S3
./scripts/backup-to-s3.sh

# Ente Photos setup (one-time)
./scripts/setup-ente.sh
```

## Configuration

`.env` (gitignored, copy from `.env.example`) provides: DOMAIN, DB_ROOT_PASSWORD, DB_NAME, DB_USER, DB_PASSWORD, DATA_PATH, S3_BUCKET, and ENTE_* variables for Ente Photos (Postgres, S3).

PHP is tuned for 8 GB RAM: `PHP_MEMORY_LIMIT=4G`, `PHP_UPLOAD_LIMIT=10G`, Opcache 512 MB. MariaDB runs with `--transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW` as Nextcloud requires.

## CI/CD

`.github/workflows/deploy.yml` — On push to `main`, SSHes into the Lightsail instance, pulls code, rebuilds app image, restarts stack, verifies 8 containers are running. Uses secrets: `LIGHTSAIL_HOST`, `LIGHTSAIL_USER`, `LIGHTSAIL_SSH_KEY`.

Dependabot checks weekly for GitHub Actions and Docker base image updates.

## SSH Access

```bash
# SSH into Lightsail instance
ssh -i ~/.ssh/lightsail.pem ubuntu@18.213.161.133

# AWS CLI with credentials
aws-vault exec thonbecker -- <command>
```

## Conventions

- Uses `docker compose` v2 plugin syntax (no hyphen), not legacy `docker-compose`
- All scripts assume they run from `~/nextcloud-aws` on the server
- The app container is always rebuilt (not just pulled) on deploy to get the latest nextcloud:apache base
- `supervisord.conf` runs both apache2 and cron inside the app container
- Nginx runs on the host (not containerized) handling SSL termination and reverse proxy
- Trusted proxies configured for RFC-1918 ranges to handle Nginx forwarding
