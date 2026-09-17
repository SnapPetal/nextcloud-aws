# Production Bootstrap Guide

This repository describes the production stack at `thonbecker.biz`. It is not a
generic one-container Nextcloud installer: the full deployment also expects an
external PostgreSQL service, S3 buckets, AWS credentials, Cloudflare DNS, and
TLS certificates matching the paths in `nginx/`.

## 1. Create the Lightsail host

Create an Ubuntu 22.04 Lightsail instance with 16 GB RAM, 4 vCPU, a static IP,
and enough root-disk capacity for `/var/lib/nextcloud`. MariaDB runs locally in
Docker; do not create a separate database for Nextcloud.

Create Cloudflare-proxied DNS records pointing at the static IP for:

- `thonbecker.biz` and `www.thonbecker.biz`
- `cloud.thonbecker.biz`
- `app.thonbecker.biz` and `booking.thonbecker.biz`
- `photos.thonbecker.biz` and `photos-api.thonbecker.biz`
- `status.thonbecker.biz`
- `vault.thonbecker.biz`
- `search.thonbecker.biz`

## 2. Prepare the host

```bash
ssh ubuntu@<your-instance-ip>
git clone https://github.com/SnapPetal/nextcloud-aws.git
cd nextcloud-aws
./scripts/setup-server.sh
```

The setup script installs the host packages, installs Docker when needed,
creates the persistent root-filesystem directories, and copies `.env.example`
to `.env`. If it adds the current user to the Docker group, log out and back in
before continuing.

## 3. Configure dependencies and secrets

Edit `.env` and replace every placeholder needed by the enabled services:

```bash
nano .env
```

The core Nextcloud values are:

```env
DOMAIN=cloud.thonbecker.biz
DB_ROOT_PASSWORD=<strong-local-mariadb-root-password>
DB_NAME=nextcloud
DB_USER=nextcloud
DB_PASSWORD=<strong-local-mariadb-password>
DATA_PATH=/var/lib/nextcloud/data
SEARXNG_SECRET=<output-of-openssl-rand-hex-32>
```

There is no `DB_HOST` or `MYSQL_ROOT_PASSWORD` setting: Compose uses the local
`db` service and reads `DB_ROOT_PASSWORD`.

Before starting the full stack, also configure:

- Ente's external PostgreSQL database, S3 bucket, encryption keys, and SMTP
  values (`ENTE_*`). The external database and credentials must already exist.
- PersonalWeb's external PostgreSQL database, AWS/media settings, Nextcloud app
  password, and optional PostHog settings (`PERSONAL_*`, `SKATETRICKS_*`).
- Vaultwarden SMTP and Argon2 admin-token hash (`VAULTWARDEN_*`).
- Backup and Netdata AWS settings when those features are enabled.

Generate the ignored Ente configuration after `.env` is complete:

```bash
./scripts/generate-museum-yaml.sh
```

For production, sync the PersonalWeb runtime secrets before each restart:

```bash
./scripts/sync-personalweb-openai-secret.sh
```

## 4. Issue TLS certificates

Install a narrowly scoped Cloudflare API token at
`/etc/letsencrypt/cloudflare.ini`:

```ini
dns_cloudflare_api_token = <cloudflare-dns-token>
```

```bash
sudo chown root:root /etc/letsencrypt/cloudflare.ini
sudo chmod 600 /etc/letsencrypt/cloudflare.ini
```

The certificate names must match the paths committed in the nginx files. Issue
or restore these certificates before enabling the virtual hosts:

```bash
CF_ARGS="--dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini"

sudo certbot certonly $CF_ARGS --cert-name cloud.thonbecker.biz \
  -d cloud.thonbecker.biz
sudo certbot certonly $CF_ARGS --cert-name thonbecker.biz \
  -d thonbecker.biz -d www.thonbecker.biz -d app.thonbecker.biz \
  -d booking.thonbecker.biz
sudo certbot certonly $CF_ARGS --cert-name photos.thonbecker.biz-0001 \
  -d photos.thonbecker.biz -d photos-api.thonbecker.biz
sudo certbot certonly $CF_ARGS --cert-name status.thonbecker.biz \
  -d status.thonbecker.biz
sudo certbot certonly $CF_ARGS --cert-name vault.thonbecker.biz \
  -d vault.thonbecker.biz
sudo certbot certonly $CF_ARGS --cert-name search.thonbecker.biz \
  -d search.thonbecker.biz
```

Test automatic renewal with `sudo certbot renew --dry-run`.

On a new installation, `./scripts/setup-ente.sh` can populate the Ente values,
generate `museum.yaml`, link the two Ente nginx files, and start Ente. Run it
only after the photos certificate above exists.

## 5. Enable nginx

The repo copies are authoritative; do not edit files under
`/etc/nginx/sites-available`.

```bash
if [ -L /etc/nginx/sites-enabled/default ]; then
  sudo unlink /etc/nginx/sites-enabled/default
elif [ -e /etc/nginx/sites-enabled/default ]; then
  sudo mv /etc/nginx/sites-enabled/default \
    "/etc/nginx/sites-enabled/default.disabled-$(date +%Y%m%d-%H%M%S)"
fi
for config in nginx/*; do
  target="/etc/nginx/sites-enabled/$(basename "$config")"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "Refusing to replace regular nginx file: $target" >&2
    exit 1
  fi
  sudo ln -sfn "$PWD/$config" "$target"
done
sudo nginx -t
sudo systemctl reload nginx
```

The static-site virtual host expects content at `/var/www/thonbecker-static`.
Netdata is a native service expected to listen on `127.0.0.1:19999`; its tracked
configuration lives in `netdata/`.

## 6. Validate and deploy

```bash
docker compose config -q
docker compose pull db valkey clamav ente-museum ente-web vaultwarden personal-website searxng
docker compose build --pull app
docker compose up -d --remove-orphans --wait --wait-timeout 180
./scripts/configure-nextcloud-valkey.sh
docker compose ps
```

Open `https://cloud.thonbecker.biz` and finish the initial Nextcloud admin
setup. Then configure Client Push:

```bash
./scripts/setup-notify-push.sh
```

For Nextcloud Office, apply the three `richdocuments` settings documented in
`AGENTS.md`.

## 7. Finish operational setup

```bash
./scripts/setup-clamav.sh
./scripts/setup-s3-backup.sh
./scripts/ensure-autostart.sh
./scripts/configure-lightsail-cloudflare-firewall.sh
```

The firewall script restricts public HTTP/HTTPS ingress to Cloudflare's current
published ranges. Review its SSH rule before running it if SSH should be limited
to an administrator address.

For automated deployment, add the repository secrets `LIGHTSAIL_HOST`,
`LIGHTSAIL_USER`, and `LIGHTSAIL_SSH_KEY`. Pull requests run the validation
workflow (including actionlint); pushes to `main` validate before deploying through
`.github/workflows/deploy.yml`.

See `README.md` for routine commands and `PRODUCTION-SETUP.md` for the current
production inventory.
