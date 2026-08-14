# Quick Start Guide - Nextcloud on AWS Lightsail

Your Nextcloud will be accessible at: **https://cloud.thonbecker.biz**

## Step 1: Create AWS Lightsail Resources

### A. Create Lightsail Instance

1. Go to [AWS Lightsail Console](https://lightsail.aws.amazon.com/)
2. Click **Create instance**
3. Select:
   - **Region**: US East (N. Virginia) or your preferred region
   - **Platform**: Linux/Unix
   - **Blueprint**: Ubuntu 22.04 LTS
   - **Plan**: 16 GB RAM, 4 vCPU
   - **Name**: `nextcloud-prod`
4. Click **Create instance**

### B. Database (Included)

The database is included as a local MariaDB container in docker-compose.yml — no external database setup needed.

## Step 2: Configure DNS

1. Go to your domain registrar (where you manage `thonbecker.biz`)
2. Add an A record:
   - **Name/Host**: `cloud`
   - **Type**: A
   - **Value**: Your Lightsail instance's static IP (get from instance details)
   - **TTL**: 300 (5 minutes)

**Note:** Create a static IP for your instance first:
- Go to instance → Networking tab → Create static IP

For the complete stack, also create proxied DNS records for `search`, `photos`, `photos-api`, `app`, `booking`, `status`, and `vault` pointing to the same static IP.

## Step 3: Setup Nextcloud on Instance

SSH into your instance:

```bash
ssh ubuntu@<your-instance-ip>
```

Clone the repository:

```bash
git clone https://github.com/SnapPetal/nextcloud-aws.git
cd nextcloud-aws
```

Run the setup script:

```bash
chmod +x scripts/setup-server.sh
./scripts/setup-server.sh
```

The script will:
- Install Docker
- Create necessary directories
- Set up `.env` file

## Step 4: Configure Environment

Edit `.env` file:

```bash
nano .env
```

Update with your actual values:

```env
DOMAIN=cloud.thonbecker.biz

# SearXNG secret (generate with: openssl rand -hex 32)
SEARXNG_SECRET=your_random_searxng_secret

# Database (local MariaDB container - just set passwords)
DB_HOST=db
DB_NAME=nextcloud
DB_USER=nextcloud
DB_PASSWORD=your_secure_password
MYSQL_ROOT_PASSWORD=your_secure_root_password

# Data storage path
DATA_PATH=/var/lib/nextcloud/data
```

Save and exit (Ctrl+X, Y, Enter)

## Step 5: Setup Nginx Reverse Proxy

Install Nginx:

```bash
sudo apt install nginx -y
```

Create Nginx configuration:

```bash
sudo nano /etc/nginx/sites-available/nextcloud
```

Paste this configuration:

```nginx
server {
    listen 80;
    server_name cloud.thonbecker.biz;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        client_max_body_size 10G;
        proxy_request_buffering off;
    }
}
```

Save and exit (Ctrl+X, Y, Enter)

Enable the site:

```bash
sudo ln -s /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
```

## Step 6: Deploy Nextcloud

Start the containers:

```bash
cd ~/nextcloud-aws
docker compose up -d

# Configure Nextcloud to use shared Valkey database 0
./scripts/configure-nextcloud-valkey.sh
```

Check logs:

```bash
docker compose logs -f
```

Wait until you see "Nextcloud is accessible" messages. Press Ctrl+C to exit logs.

## Step 7: Install SSL Certificate

Install Certbot and the Cloudflare DNS plugin:

```bash
sudo apt install python3-certbot-nginx python3-certbot-dns-cloudflare -y
```

Create a restricted Cloudflare API token for the `thonbecker.biz` zone with DNS write access, then store it server-side:

```bash
sudo install -d -m 700 /root/.secrets/certbot
sudo nano /root/.secrets/certbot/cloudflare.ini
sudo chmod 600 /root/.secrets/certbot/cloudflare.ini
```

The credentials file should contain:

```ini
dns_cloudflare_api_token = your_cloudflare_api_token
```

Request the certificate with DNS-01 validation:

```bash
sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \
  -d cloud.thonbecker.biz
```

The certificate will auto-renew via `certbot.timer`. Test renewal with `sudo certbot renew --dry-run --no-random-sleep-on-renew`.

## Step 8: Access Nextcloud

1. Open browser and go to: **https://cloud.thonbecker.biz**
2. Create admin account
3. Database is already configured via environment variables
4. Complete setup wizard

## Step 9: Configure GitHub Actions (Optional)

Generate SSH key for automated deployments:

```bash
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github-actions -N ""
cat ~/.ssh/github-actions.pub >> ~/.ssh/authorized_keys
cat ~/.ssh/github-actions
```

Copy the private key output.

Add GitHub secrets:
1. Go to https://github.com/SnapPetal/nextcloud-aws/settings/secrets/actions
2. Add:
   - `LIGHTSAIL_HOST`: Your instance's static IP
   - `LIGHTSAIL_USER`: `ubuntu`
   - `LIGHTSAIL_SSH_KEY`: The private key you just copied

Now pushes to main branch will auto-deploy!

## Maintenance

Use the maintenance script:

```bash
cd ~/nextcloud-aws
./scripts/maintenance.sh
```

This provides a menu for:
- View logs
- Restart containers
- Update Nextcloud
- Backups
- And more

## Cost Summary

- Instance (16 GB, 4 vCPU): $80/month
- S3 Storage: ~$0.023/GB/month (optional)
- Database: Included (local MariaDB)
- Static IP: Free
- **Total: ~$80/month** (plus S3 if used)

## Need Help?

- Check the full [README.md](README.md)
- Check logs: `docker compose logs -f`

## Your Nextcloud URLs

- **Main URL**: https://cloud.thonbecker.biz
- **Admin**: https://cloud.thonbecker.biz/settings/admin
- **Files**: https://cloud.thonbecker.biz/apps/files
