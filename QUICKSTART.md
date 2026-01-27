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
   - **Plan**: $10/month (2 GB RAM, 1 vCPU, 60 GB SSD)
   - **Name**: `nextcloud-prod`
4. Click **Create instance**

### B. Create Block Storage Volume

1. In Lightsail console, click **Storage** tab
2. Click **Create disk**
3. Configure:
   - **Size**: 100 GB
   - **Availability Zone**: Same as your instance
   - **Name**: `nextcloud-prod-data`
   - **Attach to instance**: `nextcloud-prod`
4. Click **Create**

### C. Database (Included)

The database is now included as a local MariaDB container in the docker-compose.yml - no external database setup needed!

## Step 2: Configure DNS

1. Go to your domain registrar (where you manage `thonbecker.biz`)
2. Add an A record:
   - **Name/Host**: `cloud`
   - **Type**: A
   - **Value**: Your Lightsail instance's static IP (get from instance details)
   - **TTL**: 300 (5 minutes)

**Note:** Create a static IP for your instance first:
- Go to instance → Networking tab → Create static IP

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
- Mount your block storage volume
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

# Database (local MariaDB container - just set passwords)
DB_HOST=db
DB_NAME=nextcloud
DB_USER=nextcloud
DB_PASSWORD=your_secure_password
MYSQL_ROOT_PASSWORD=your_secure_root_password

DATA_PATH=/mnt/nextcloud-data
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
```

Check logs:

```bash
docker compose logs -f
```

Wait until you see "Nextcloud is accessible" messages. Press Ctrl+C to exit logs.

## Step 7: Install SSL Certificate

Install Certbot with Nginx plugin:

```bash
sudo apt install python3-certbot-nginx -y
```

Get SSL certificate:

```bash
sudo certbot --nginx -d cloud.thonbecker.biz
```

Follow the prompts:
- Enter your email
- Agree to terms
- Choose to redirect HTTP to HTTPS (option 2)

The certificate will auto-renew via cron.

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

- Instance (8 GB): $40/month
- Block Storage (300 GB): $30/month
- Database: Included (local MariaDB)
- Static IP: Free
- **Total: ~$70/month**

## Need Help?

- Check the full [README.md](README.md)
- Review [CloudFront/ALB Setup Guide](docs/CLOUDFRONT-ALB-SETUP.md) if you want SSL at AWS level
- Check logs: `docker compose logs -f`

## Your Nextcloud URLs

- **Main URL**: https://cloud.thonbecker.biz
- **Admin**: https://cloud.thonbecker.biz/settings/admin
- **Files**: https://cloud.thonbecker.biz/apps/files
