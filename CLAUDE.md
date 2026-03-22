# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure-as-configuration repository for a self-hosted Nextcloud instance on AWS Lightsail. No application source code, build system, or test suite — this is Docker config, shell scripts, and documentation.

**Production:** https://cloud.thonbecker.biz

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

All six domains are **Cloudflare-proxied** (orange cloud). Cloudflare handles DDoS protection and caching; SSL terminates at nginx (Certbot certs). Incoming IPs seen by nginx are Cloudflare ranges — trusted proxies are configured for RFC-1918 ranges which covers the nginx→container hop. Certbot uses the `nginx` authenticator (HTTP-01 challenge), which works through Cloudflare proxy.

**Cloudflare feature settings:**

| Feature | Setting | Notes |
|---|---|---|
| HTTP/2 to Origin | ✅ On | nginx supports it |
| HTTP/3 (with QUIC) | ✅ On | Faster connections |
| 0-RTT Connection Resumption | Off | Minor replay attack risk, little benefit |
| Always Use HTTPS | ✅ On | Belt-and-suspenders with nginx |
| TLS 1.3 | ✅ On | nginx supports it |
| Normalize incoming URLs | ✅ On | Prevents path confusion attacks |
| WebSockets | ✅ On | Required for Nextcloud Office and Vaultwarden |
| Onion Routing | Off | Not needed |
| Browser Integrity Check | Caution | Can block Nextcloud desktop/mobile sync clients — test after enabling |
| Hotlink Protection | ❌ Off | Breaks Nextcloud file sharing and public links |
| Web Analytics (RUM) | Off | Injects JS into pages, can interfere with Nextcloud's CSP headers |
| Rocket Loader | ❌ Off | Breaks Nextcloud's JavaScript — never enable |
| Mirage / Polish | ❌ Off | Can corrupt file transfers and break previews |

Nine containers in docker-compose.yml:

**Nextcloud:**
- **nextcloud-app** — Custom Dockerfile (nextcloud:apache + ffmpeg/ghostscript/imagemagick/supervisor), binds 127.0.0.1:8080
- **nextcloud-db** — MariaDB 10.11, data at /var/lib/nextcloud/mysql
- **nextcloud-redis** — Redis Alpine, caching + file locking
- **nextcloud-clamav** — ClamAV antivirus daemon on port 3310

**Observability (native host service, not containerized):**
- **netdata** — Native systemd service (installed via apt from Netdata repo), binds 127.0.0.1:19999 (proxied at status.thonbecker.biz). Alerts via AWS SNS (`NextcloudRecoveryTopic`). Config symlinked from `netdata/` into `/etc/netdata/`. AWS credentials injected via `/etc/systemd/system/netdata.service.d/override.conf` (loads `.env` as EnvironmentFile).

**Ente Photos:**
- **ente-museum** — Ente API server, binds 127.0.0.1:8082 (proxied at photos-api.thonbecker.biz)
- **ente-postgres** — PostgreSQL 15 for Ente metadata
- **ente-web** — Ente Photos web app, binds 127.0.0.1:3000 (proxied at photos.thonbecker.biz)

**Personal Website:**
- **personal-website** — Personal web app (Spring Boot) from public ECR (`public.ecr.aws/p0w8z2j2/personal`), binds 127.0.0.1:3003 (proxied at thonbecker.biz). Uses external RDS PostgreSQL, not a local container. Has a bind mount at `/var/lib/personal-website/videos` → `/app/videos` for temporary skateboard video processing.

**Vaultwarden:**
- **vaultwarden** — Bitwarden-compatible password manager (vaultwarden/server), binds 127.0.0.1:3002 (proxied at vault.thonbecker.biz)

**Storage split:** Root filesystem holds app files (`/var/lib/nextcloud/app`) and DB (`/var/lib/nextcloud/mysql`). A 300 GB Lightsail block storage volume at `/mnt/nextcloud-data` holds user data and backups.

## Nextcloud App Notes

**Removed apps (do not reinstall):**
- **recognize** and **memories** — removed in favor of Ente Photos.

**Nextcloud Office (bundled Collabora CODE):**
Apps `richdocuments` + `richdocumentscode` provide in-browser document editing. The following occ config is required (not version-controlled — set manually):

```bash
docker compose exec -u www-data app php occ config:app:set richdocuments wopi_url \
  --value="https://cloud.thonbecker.biz/custom_apps/richdocumentscode/proxy.php?req="
docker compose exec -u www-data app php occ config:app:set richdocuments public_wopi_url \
  --value="https://cloud.thonbecker.biz"
docker compose exec -u www-data app php occ config:app:set richdocuments wopi_callback_url \
  --value=""
```

Why: `proxy.php` constructs discovery XML URLs from `$_SERVER['HTTP_HOST']`. It must be fetched via the public URL so it returns `https://cloud.thonbecker.biz` URLs (not `http://localhost`) in the discovery XML. The `extra_hosts: cloud.thonbecker.biz:host-gateway` entry in `docker-compose.yml` lets the container reach nginx on the host without going through Cloudflare. `wopi_callback_url` left empty so WOPISrc uses the browser's URL rather than `http://localhost`.

If document editing breaks (browser console shows `http://localhost` form-action errors), check these three settings and flush Redis: `docker compose exec redis redis-cli FLUSHALL`. Note: bundled Collabora takes 2–3 minutes to fully initialize after container start.

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

`.env` (gitignored, copy from `.env.example`) provides: DOMAIN, DB_ROOT_PASSWORD, DB_NAME, DB_USER, DB_PASSWORD, DATA_PATH, S3_BUCKET, S3_DB_BACKUP_BUCKET, ENTE_* variables for Ente Photos (Postgres, S3, JWT, SMTP), and PERSONAL_* variables for the personal website (AWS Bedrock, Cognito, Nextcloud CalDAV, Perenual API).

The Lightsail instance is 4 vCPU / 16 GB RAM. PHP is tuned with `PHP_MEMORY_LIMIT=4G`, `PHP_UPLOAD_LIMIT=10G`, Opcache 512 MB. MariaDB runs with `--transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW` as Nextcloud requires.

## Nginx

All five virtual host configs live in `nginx/` and are symlinked into `/etc/nginx/sites-enabled/`. SSL is managed by Certbot (`authenticator = nginx` for all domains). Do not edit configs in `/etc/nginx/sites-available/` — edit the repo copies in `nginx/` instead.

```
nginx/nextcloud                  → cloud.thonbecker.biz
nginx/www.thonbecker.biz         → thonbecker.biz
nginx/status.thonbecker.biz      → status.thonbecker.biz
nginx/photos.thonbecker.biz      → photos.thonbecker.biz
nginx/photos-api.thonbecker.biz  → photos-api.thonbecker.biz
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

## Netdata Alerting

Notifications go via `alarm-notify.sh` → AWS SNS → email. The IAM user (`netdata-sns-user`) has only `sns:Publish` permission. The SNS topic is `NextcloudRecoveryTopic` (ARN in `.env` as `NETDATA_SNS_TOPIC_ARN`).

**Known Netdata v2.x notification behavior:**
- **CLEAR → WARNING**: alarm-notify.sh is **not invoked** — no notification sent for initial warning-level alerts
- **WARNING → CRITICAL**: alarm-notify.sh is invoked; historically returns `exec_code=1` (fails to publish)
- **CRITICAL → WARNING (recovery)**: alarm-notify.sh is invoked and succeeds (`exec_code=0`)

In practice this means you will receive recovery notifications but not initial alert notifications. This is a v2.x behavior change from v1.x.

**Noisy alarms to be aware of:**
- `apps_group_file_descriptors_utilization` (role: `sysadmin`) — fires constantly for short-lived processes (cron jobs, certbot, etc.) hitting per-process fd limits. These are transient and harmless; they clear within seconds and never notify.

**Diagnosing notification failures:**

```bash
# Test the full notification pipeline manually
SNS_ARN=$(grep NETDATA_SNS_TOPIC_ARN /home/ubuntu/nextcloud-aws/.env | cut -d= -f2)
sudo env AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_DEFAULT_REGION=us-east-1 \
  NETDATA_SNS_TOPIC_ARN="$SNS_ARN" \
  /usr/libexec/netdata/plugins.d/alarm-notify.sh test sysadmin

# Check recent alarm notification history (requires sqlite3)
sudo -u netdata sqlite3 /var/cache/netdata/netdata-meta.db "
SELECT hld.unique_id, hl.name, hl.recipient, hld.new_status, hld.old_status,
  datetime(hld.when_key, 'unixepoch') as alarm_time, hld.exec_run_timestamp, hld.exec_code
FROM health_log_detail hld
JOIN health_log hl ON hld.health_log_id = hl.health_log_id
WHERE hld.new_status NOT IN (-3,-2,-1,0)
ORDER BY hld.unique_id DESC LIMIT 20;"

# Verify SNS publish works directly
aws sns publish --topic-arn "$SNS_ARN" --message "test" --subject "test"
```

**SNS subscription:** The topic has a confirmed email subscription. To check/manage subscriptions, use the AWS console — the IAM user on the server lacks `sns:ListSubscriptions` permission.

## Backups

`scripts/backup-to-s3.sh` runs nightly at 02:00 via cron. Backs up all three databases and uploads to S3:
- MariaDB → `s3://${S3_DB_BACKUP_BUCKET}/mariadb/`
- PostgreSQL (Ente) → `s3://${S3_DB_BACKUP_BUCKET}/postgres/`
- SQLite (Vaultwarden) → `s3://${S3_DB_BACKUP_BUCKET}/vaultwarden/`

Keeps last 3 local copies in `/mnt/nextcloud-data/backups/`. Cron log at `/mnt/nextcloud-data/backups/cron.log`.

## CI/CD

`.github/workflows/deploy.yml` — On push to `main`, SSHes into the Lightsail instance, pulls code, pulls latest Docker images, rebuilds app image, restarts stack, reloads nginx, then verifies all 9 containers are running. Uses secrets: `LIGHTSAIL_HOST`, `LIGHTSAIL_USER`, `LIGHTSAIL_SSH_KEY`.

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
- All six domains are Cloudflare-proxied; nginx sees Cloudflare IPs, not real client IPs
- Trusted proxies configured for RFC-1918 ranges to handle Nginx forwarding
- `nextcloud-app` has `extra_hosts: cloud.thonbecker.biz:host-gateway` so internal server-to-self requests route via the Docker bridge to nginx rather than through Cloudflare
- All nginx virtual host configs are version-controlled in `nginx/` — symlinked from `/etc/nginx/sites-enabled/`
- Netdata configs are version-controlled in `netdata/` — symlinked from `/etc/netdata/` (`netdata.conf`, `health_alarm_notify.conf`, `go.d/httpcheck.conf`)
- Netdata httpcheck uses localhost URLs (not public domains) to avoid adding load through Cloudflare
