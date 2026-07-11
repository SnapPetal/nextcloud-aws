# Self-Hosted Services on AWS Lightsail

Multi-service self-hosted stack on AWS Lightsail using Docker, Nginx, and Cloudflare.

## Architecture

```
Internet → Cloudflare (proxy) → Nginx (host, SSL via Certbot) → Docker bridge (nextcloud-net)
  cloud.thonbecker.biz        → 127.0.0.1:8080 (Nextcloud)
  thonbecker.biz              → /var/www/thonbecker-static (Static Website)
  app.thonbecker.biz          → 127.0.0.1:3003 (Personal Web Apps)
  booking.thonbecker.biz      → 127.0.0.1:3003 (Booking)
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

All eight domains are Cloudflare-proxied. SSL terminates at nginx via Certbot.

## PersonalWeb Runtime Secrets

The PersonalWeb OpenAI API key is stored in AWS Secrets Manager as `personalweb/openai-api-key`; booking administrator credentials are stored as `personalweb/admin-credentials`.
Before restarting `personal-website`, sync it into the local `.env` file:

```bash
./scripts/sync-personalweb-openai-secret.sh
```

The script uses `PERSONAL_AWS_ACCESS_KEY_ID`, `PERSONAL_AWS_SECRET_ACCESS_KEY`, and `PERSONAL_AWS_REGION` from `.env`, then writes the OpenAI model variables and `PERSONAL_ADMIN_USERNAME`/`PERSONAL_ADMIN_PASSWORD` for Docker Compose.

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

# Ente Photos: set all account quotas to self-hosted "no limit" values
./scripts/ente-set-unlimited-storage.sh -a <admin-email>
```

### Vaultwarden Admin Token

The admin panel is `https://vault.thonbecker.biz/admin`. The plaintext admin token is not stored on the server or in Git; it is kept locally in:

```bash
.vaultwarden-admin-token-*.txt
```

The server `.env` stores only an Argon2 PHC hash in `VAULTWARDEN_ADMIN_TOKEN`. Keep the hash quoted in `.env` so Docker Compose does not interpolate the dollar signs:

```bash
VAULTWARDEN_ADMIN_TOKEN='$argon2id$v=19$m=19456,t=2,p=1$...'
```

If the plaintext token is lost, rotate it by generating a new token, hashing it with `argon2`, replacing `VAULTWARDEN_ADMIN_TOKEN` with the quoted PHC hash, and restarting Vaultwarden:

```bash
docker compose up -d vaultwarden
```

### Vaultwarden upgrades

The Vaultwarden image is pinned to a release tag so an unrelated deployment does not silently upgrade the password manager. Check the [Vaultwarden releases](https://github.com/dani-garcia/vaultwarden/releases) page periodically, and review security advisories and release notes before upgrading.

Before upgrading, confirm the nightly backup completed successfully:

```bash
tail -n 50 /var/lib/nextcloud/data/backups/backup.log
```

To upgrade, change the `vaultwarden/server:<version>` tag in `docker-compose.yml`, commit and deploy the change, then verify the container and web vault:

```bash
docker compose pull vaultwarden
docker compose up -d vaultwarden
docker compose ps vaultwarden
docker compose logs --since=5m vaultwarden
```

Keep the previous image tag available until login, browser-extension sync, invitations, and the admin panel have been tested.

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
│   ├── go.d/httpcheck.conf     # HTTP health checks (localhost)
│   └── health.d/               # Alert overrides for noisy alarms
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

The production checkout lives at `~/nextcloud-aws` on the Lightsail server:

```bash
ssh -i ~/.ssh/lightsail.pem ubuntu@18.213.161.133
cd ~/nextcloud-aws
```

### Ente Photos Admin Notes

The Ente web app is `https://photos.thonbecker.biz`; the Ente Museum API is
`https://photos-api.thonbecker.biz`.

The Ente CLI is installed on the server at `~/.local/bin/ente` and configured in
`~/.ente/config.yaml` with:

```yaml
endpoint:
  api: https://photos-api.thonbecker.biz
```

Because the server is headless, the CLI uses `ENTE_CLI_SECRETS_PATH=~/.ente/secrets.txt`
instead of a desktop keyring. This is exported from `~/.profile`.

Current Ente account quotas were set directly in PostgreSQL on 2026-06-06 to the
same values used by Ente CLI's `--no-limit` mode:

- `storage = 109951162777600` bytes, which is 100 TiB
- `expiry_time` around 2126-06-06

A pre-change backup of the `subscriptions` table was saved on the server at:

```bash
/home/ubuntu/ente-subscriptions-before-unlimited-20260606035656.sql
```

To verify current quotas:

```bash
cd ~/nextcloud-aws
set -a && . ./.env && set +a
docker compose exec -T ente-postgres psql -U "$ENTE_POSTGRES_USER" -d "$ENTE_POSTGRES_DB" \
  -c "SELECT COUNT(*) AS accounts, MIN(storage) AS min_storage, MAX(storage) AS max_storage, MIN(to_timestamp(expiry_time / 1000000.0)) AS earliest_expiry FROM subscriptions;"
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
