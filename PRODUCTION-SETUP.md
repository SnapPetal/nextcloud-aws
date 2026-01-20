# Production Setup Documentation

This file documents the actual production configuration of cloud.thonbecker.biz.

## Current Infrastructure

**Deployed:** January 2026
**Domain:** https://cloud.thonbecker.biz
**Location:** AWS Lightsail us-east-1a

### Resources

| Resource | Name | Specs | Cost |
|----------|------|-------|------|
| Instance | nextcloud-prod | Ubuntu 22.04, 4 GB RAM, 2 vCPU | $20/month |
| Block Storage | nextcloud-prod-data-300gb | 300 GB SSD | $30/month |
| Database | nextcloud-prod-db | MySQL 8.0 Standard | $15/month |
| Static IP | nextcloud-prod-ip | IPv4 | Free |
| **Total** | | | **$65/month** |

### Storage Breakdown

**Total capacity:** 300 GB
**Currently used:** ~36 GB
**Available:** ~246 GB

**Contents:**
- Nextcloud application files (~12 GB)
- User data migrated from Google Drive (~12 GB)
- Database overhead
- Photos ready to upload (157 GB planned)

### Disk Details

- **Device:** /dev/nvme1n1
- **UUID:** 9295b677-3030-4e4c-9e14-cd1e09846620
- **Filesystem:** ext4
- **Mount:** /mnt/nextcloud-data
- **Resized from:** 128 GB → 300 GB (January 2026)

## Network Configuration

**SSL/TLS:** Let's Encrypt (auto-renews)
**Web Server:** Nginx reverse proxy
**Container Ports:**
- Nginx: 443 (HTTPS), 80 (HTTP redirect)
- Nextcloud: 127.0.0.1:8080 (internal only)
- Redis: Internal container network

**Firewall (Lightsail):**
- Port 22 (SSH): Restricted to admin IP
- Port 80 (HTTP): Open (redirects to HTTPS)
- Port 443 (HTTPS): Open

## Nginx Configuration

**Location:** `/etc/nginx/sites-available/nextcloud`

**Key features:**
- SSL termination
- CalDAV/CardDAV redirects for iOS/Android sync
- 10 GB upload limit
- Security headers
- Proxy buffering disabled for large uploads

See [docs/NGINX-SETUP.md](docs/NGINX-SETUP.md) for complete configuration.

## Docker Configuration

**Containers:**
- `nextcloud-app`: Official nextcloud:apache image
- `nextcloud-redis`: redis:alpine for caching

**Volumes:**
- `/mnt/nextcloud-data/nextcloud` → `/var/www/html`
- `/mnt/nextcloud-data/data` → `/var/www/html/data`

**Environment:**
- Database: External Lightsail MySQL
- Redis: Internal container
- Domain: cloud.thonbecker.biz
- Trusted proxies configured for Nginx

## Database Configuration

**Engine:** MySQL 8.0
**Host:** ls-02b194f7be6f5666fb48421a5c2c5da2e7a1fead.cmldxjsfqvn4.us-east-1.rds.amazonaws.com
**Database:** nextcloud
**User:** dbmasteruser
**Connection:** TLS encrypted
**Backups:** Automated daily snapshots by Lightsail

## Installed Nextcloud Apps

- ✅ Calendar (CalDAV sync)
- ✅ Contacts (CardDAV sync)
- ✅ Photos (timeline view)
- ✅ Nextcloud Office (Collabora Online - document editing)
- Additional apps can be enabled as needed

## Sync Clients

**iOS:**
- Calendar sync via CalDAV
- Contacts sync via CardDAV
- Photos app for mobile uploads

**Desktop:**
- Nextcloud desktop client configured
- Sync folder: Local → Cloud

**MultCloud:**
- Configured for cloud-to-cloud transfers
- Used for Google Drive migration

## Backup Strategy

**Automated Lightsail snapshots:**
- Instance snapshots: Manual as needed
- Disk snapshots: Available for quick recovery
- Database backups: Daily automated by Lightsail

**Retention:**
- Keep disk snapshots after major changes
- Clean up old snapshots after verification

## Maintenance

**Regular updates:**
```bash
cd ~/nextcloud-aws
docker compose pull
docker compose up -d
```

**Maintenance script:**
```bash
cd ~/nextcloud-aws
./scripts/maintenance.sh
```

**Certificate renewal:** Automatic via Certbot cron

## Performance Settings

**PHP:**
- Memory limit: 2G (optimized for 4 GB instance)
- Upload limit: 10G
- Execution time: 3600s
- Opcache: Enabled (256 MB)

**Apache:**
- Body limit: 10 GB

**Nginx:**
- Client max body size: 10G
- Timeouts: 600s

**Redis:**
- File locking and caching enabled

## GitHub Actions

**Workflow:** `.github/workflows/deploy.yml`

**Triggers:**
- Push to main branch
- Manual workflow dispatch

**Actions:**
- Pull latest code on server
- Pull latest Docker images
- Restart containers
- Health check

**Secrets configured:**
- LIGHTSAIL_HOST: Instance static IP
- LIGHTSAIL_USER: ubuntu
- LIGHTSAIL_SSH_KEY: ED25519 key for automated access

## Access Credentials

**Admin user:** thonbecker
**Additional users:** Can be created in Nextcloud admin panel

**App passwords:** Configured for:
- iOS sync clients
- Desktop sync client
- MultCloud integration

## Monitoring

**Health checks:**
- Docker container health: `/status.php`
- Disk usage: `df -h /mnt/nextcloud-data`
- Container stats: `docker stats`

**Logs:**
- Nginx: `/var/log/nginx/nextcloud_*.log`
- Docker: `docker compose logs`
- Nextcloud: Via OCC commands

## Known Issues & Solutions

**iOS sync requires CalDAV/CardDAV redirects:**
- ✅ Resolved: Nginx handles `.well-known` redirects

**Lightsail disk resizing:**
- ⚠️ Requires snapshot method (no direct resize)
- ✅ Completed: 128 GB → 300 GB resize (January 2026)

**Instance upgrade:**
- ✅ Upgraded: 2 GB RAM → 4 GB RAM (January 2026)
- ✅ Performance boost for photo/video handling

## Photo & Video Optimizations

**Performance improvements for 157 GB photo collection:**
- PHP memory increased to 2G
- Opcache enabled for faster page loads
- Preview generation script available: `./scripts/generate-previews.sh`
- Memories app recommended (better than default Photos)
- Video transcoding support via Memories app

**See:** [docs/PHOTO-VIDEO-OPTIMIZATION.md](docs/PHOTO-VIDEO-OPTIMIZATION.md) for complete guide

## Future Considerations

- Monitor storage usage as photo collection grows (currently 246 GB available)
- Can expand to 512 GB disk if needed (~$50/month)
- Consider 8 GB RAM upgrade if performance degrades with heavy usage

## Support Resources

- **Repository:** https://github.com/SnapPetal/nextcloud-aws
- **Nextcloud Docs:** https://docs.nextcloud.com/
- **AWS Lightsail:** https://lightsail.aws.amazon.com/

---

**Last updated:** January 18, 2026
**Deployed by:** thonbecker
**Status:** Production ✅
