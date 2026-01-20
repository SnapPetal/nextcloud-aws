# Photo & Video Optimization Guide

This guide covers optimizing Nextcloud for handling large photo and video collections on your 4 GB RAM / 2 vCPU instance.

## Current Optimizations

### Hardware
- **Instance**: 4 GB RAM, 2 vCPU (upgraded from 2 GB)
- **Storage**: 300 GB SSD
- **Database**: External managed MySQL

### Software Configuration
- **PHP Memory**: 2 GB (increased from 512 MB)
- **Opcache**: Enabled for faster PHP execution
- **Redis**: Caching enabled
- **Upload Limit**: 10 GB for large video files

## Recommended Apps for Photos

### 1. Memories App (Highly Recommended)
**Install:** https://cloud.thonbecker.biz/settings/apps → Search "Memories"

**Why Memories over default Photos:**
- 🚀 Much faster performance with large libraries
- 🎭 AI-powered face recognition
- 📹 Video transcoding and streaming
- 🗺️ Map view with GPS data
- ⚡ Hardware acceleration support
- 📱 Better mobile experience

**After installation:**
1. Go to https://cloud.thonbecker.biz/apps/memories
2. It will automatically index your photos
3. Enable face recognition in Settings if desired

### 2. Preview Generator (Automatic Thumbnails)
Pre-generates thumbnails for faster browsing. Automatically creates previews for new images.

**One-time setup (installs app + configures automatic generation):**
```bash
# SSH to your server
ssh ubuntu@<your-ip>
cd ~/nextcloud-aws
./scripts/setup-auto-previews.sh
```

This script:
- Installs the Preview Generator app
- Configures optimal preview sizes
- Shows you how to set up automatic generation for new images

**Manual generation for existing photos:**
```bash
cd ~/nextcloud-aws
./scripts/generate-previews.sh
```

**Automatic generation for NEW images (recommended):**
After running setup script, add this to crontab to process new images every 15 minutes:
```bash
# SSH to your server
ssh ubuntu@<your-ip>

# Edit crontab
crontab -e

# Add this line (generates previews for new files every 15 minutes):
*/15 * * * * cd ~/nextcloud-aws && docker compose exec -u www-data app php occ preview:pre-generate >> /tmp/preview-generate.log 2>&1
```

This ensures new photos automatically get thumbnails within 15 minutes of upload.

## Performance Tips

### 1. Enable Video Transcoding (for Memories app)
Allows smooth video playback without downloading entire files.

**Requirements:**
- ffmpeg (included in Nextcloud container)
- Hardware acceleration optional (VA-API on your instance)

**Configure in Memories app settings:**
- Enable transcoding for videos
- Set quality: 1080p or 720p depending on your needs
- Let it process videos in background

### 2. Configure Preview Sizes
Optimize preview sizes for your usage:

```bash
# SSH to server
ssh ubuntu@<your-ip>
cd ~/nextcloud-aws

# Configure preview sizes
docker compose exec -u www-data app php occ config:system:set preview_max_x --value=2048
docker compose exec -u www-data app php occ config:system:set preview_max_y --value=2048
docker compose exec -u www-data app php occ config:system:set jpeg_quality --value=85
```

### 3. Enable File Locking with Redis
Already configured in your setup, but verify:

```bash
docker compose exec -u www-data app php occ config:system:get filelocking.enabled
# Should return: true
```

### 4. Disable Unnecessary Preview Providers
Save resources by only generating previews for formats you use:

```bash
# List current providers
docker compose exec -u www-data app php occ config:system:get enabledPreviewProviders

# If you don't use certain formats, disable them
# Example: Disable SVG previews if you don't use SVG files
docker compose exec -u www-data app php occ config:system:delete enabledPreviewProviders 3
```

## Uploading Large Photo Collections

### Best Practices for Your 157 GB Collection

**Option 1: Desktop Client (Recommended)**
- Install Nextcloud desktop client
- Add photos to sync folder
- It handles interruptions and resumes automatically
- Shows progress

**Option 2: MultCloud (Cloud-to-Cloud)**
- If photos are already in cloud storage
- Set up transfer and let it run
- No local bandwidth usage

**Option 3: Direct Upload via Web**
- Works for smaller batches
- Drag and drop folders
- 10 GB upload limit per file

**Option 4: Command Line (Advanced)**
```bash
# Using rsync if you have SSH access to both locations
rsync -avz --progress /path/to/photos/ ubuntu@your-ip:/mnt/nextcloud-data/data/username/files/Photos/

# Then scan files
ssh ubuntu@your-ip
cd ~/nextcloud-aws
docker compose exec -u www-data app php occ files:scan --all
```

## Monitoring Performance

### Check Photo Indexing Status
```bash
docker compose exec -u www-data app php occ photos:update-1000-cities
docker compose logs -f app | grep -i memory
```

### Check Preview Generation Status
```bash
docker compose exec -u www-data app php occ preview:generate-all --dry-run
```

### Monitor Resource Usage
```bash
# On your Lightsail instance
docker stats
htop  # or top
df -h /mnt/nextcloud-data
```

## Troubleshooting

### Photos Not Showing Up
```bash
# Rescan all files
docker compose exec -u www-data app php occ files:scan --all

# Rebuild photo index
docker compose exec -u www-data app php occ photos:update
```

### Slow Photo Loading
1. Run preview generation: `./scripts/generate-previews.sh`
2. Check if Memories app is installed (much faster)
3. Verify Redis is working: `docker compose logs redis`
4. Check available RAM: `free -h`

### Videos Won't Play
1. Install Memories app (has built-in transcoding)
2. Check video format compatibility (MP4/H.264 works best)
3. Enable transcoding in Memories settings
4. Check PHP memory limit is sufficient (currently 2G)

### Out of Memory Errors
```bash
# Check current memory usage
docker stats

# If needed, adjust PHP memory in docker-compose.yml
# Current: PHP_MEMORY_LIMIT=2G
# Can increase if you have available RAM
```

## Expected Performance

With your 4 GB RAM / 2 vCPU setup:

- **Photo browsing**: Fast with Memories app + previews
- **Video streaming**: Smooth with transcoding enabled
- **Upload speeds**: Limited by network, not server
- **Face recognition**: Works, but slower than high-end servers
- **Concurrent users**: 3-5 users browsing simultaneously
- **Large uploads**: 10 GB files supported

## Future Upgrades

If you need even better performance:

1. **Upgrade to 8 GB RAM** ($40/month instance)
   - Faster face recognition
   - More concurrent users
   - Better video transcoding

2. **Add CDN** (CloudFront)
   - Faster photo delivery globally
   - Reduced server load

3. **External Storage** (S3 for archives)
   - Keep recent photos on SSD
   - Archive old photos to cheaper S3 storage

## Quick Commands Reference

```bash
# Generate all previews
./scripts/generate-previews.sh

# Scan new files
docker compose exec -u www-data app php occ files:scan --all

# Check Nextcloud status
docker compose exec -u www-data app php occ status

# Restart containers (apply config changes)
docker compose restart

# Check logs
docker compose logs -f app

# Check resource usage
docker stats
```

## Recommended Workflow

1. ✅ Install Memories app
2. ✅ Upload photos via desktop client or MultCloud
3. ✅ Run preview generation once uploaded
4. ✅ Enable face recognition if desired
5. ✅ Set up automatic preview generation (cron)
6. ✅ Enjoy fast photo browsing!

---

**Last updated:** January 19, 2026
**Instance specs:** 4 GB RAM, 2 vCPU, 300 GB storage
