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

### C. Create Managed Database

1. In Lightsail console, click **Databases** tab
2. Click **Create database**
3. Configure:
   - **Database engine**: MySQL 8.0
   - **Plan**: Standard ($15/month)
   - **Name**: `nextcloud-prod-db`
   - **Master username**: `dbadmin`
   - **Master password**: Create a strong password (save it!)
4. Click **Create database**
5. Wait for database to be ready (5-10 minutes)
6. Note the **Endpoint** (looks like: `ls-xxxxx.us-east-1.rds.amazonaws.com`)

### D. Configure Database Access

1. Go to your database → **Networking** tab
2. Enable **Public mode** (needed for Lightsail instance to connect)
3. Or add your instance's private IP to allowed connections

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

# From your Lightsail database
DB_HOST=ls-xxxxxxxxxxxxx.us-east-1.rds.amazonaws.com
DB_NAME=nextcloud
DB_USER=dbadmin
DB_PASSWORD=your_actual_database_password

DATA_PATH=/mnt/nextcloud-data
```

Save and exit (Ctrl+X, Y, Enter)

## Step 5: Deploy Nextcloud

Start the containers:

```bash
docker compose up -d
```

Check logs:

```bash
docker compose logs -f
```

Wait until you see "Nextcloud is accessible" messages.

## Step 6: Install SSL Certificate

Install Certbot:

```bash
sudo apt install certbot python3-certbot-apache -y
```

Get SSL certificate:

```bash
sudo certbot --apache -d cloud.thonbecker.biz
```

Follow the prompts:
- Enter your email
- Agree to terms
- Choose to redirect HTTP to HTTPS (option 2)

## Step 7: Access Nextcloud

1. Open browser and go to: **https://cloud.thonbecker.biz**
2. Create admin account
3. Database is already configured via environment variables
4. Complete setup wizard

## Step 8: Configure GitHub Actions (Optional)

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

- Instance (2 GB): $10/month
- Block Storage (100 GB): $10/month
- Managed Database: $15/month
- Static IP: Free
- **Total: ~$35/month**

## Need Help?

- Check the full [README.md](README.md)
- Review [CloudFront/ALB Setup Guide](docs/CLOUDFRONT-ALB-SETUP.md) if you want SSL at AWS level
- Check logs: `docker compose logs -f`

## Your Nextcloud URLs

- **Main URL**: https://cloud.thonbecker.biz
- **Admin**: https://cloud.thonbecker.biz/settings/admin
- **Files**: https://cloud.thonbecker.biz/apps/files
