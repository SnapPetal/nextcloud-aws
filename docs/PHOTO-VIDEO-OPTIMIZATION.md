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

### 3. Face Recognition (AI-Powered People Detection)
Automatically detect and group faces in your photo collection using AI.

**One-time setup (installs Recognize app + runs initial scan):**
```bash
# SSH to your server
ssh ubuntu@<your-ip>
cd ~/nextcloud-aws
./scripts/setup-face-recognition.sh
```

This interactive script:
- Installs the Recognize app (AI face detection engine)
- Downloads AI models for face recognition
- Runs initial face classification on all photos
- Shows how to set up automatic processing for new photos

**What happens during initial scan:**
- Scans all your photos for faces
- Groups similar faces together
- Takes several hours for large collections (157 GB = possibly overnight)
- CPU intensive but runs in background
- Your 4 GB instance handles it fine

**After setup - Using face recognition:**

1. **View face clusters:**
   - Go to https://cloud.thonbecker.biz/apps/memories
   - Click the **"People"** tab (face icon)
   - See all detected faces grouped by similarity

2. **Name people:**
   - Click on a face cluster
   - Click "Rename" or the edit icon
   - Type the person's name
   - All photos with that face are now tagged

3. **Merge duplicate clusters:**
   - If same person appears in multiple clusters
   - Select clusters and merge them
   - Improves accuracy over time

**Automatic face recognition for NEW photos:**
Add to crontab to process new photos nightly:
```bash
# Edit crontab
crontab -e

# Add this line (runs every night at 2 AM):
0 2 * * * cd ~/nextcloud-aws && docker compose exec -u www-data app php occ recognize:classify >> /tmp/recognize.log 2>&1
```

**Monitor progress:**
```bash
# View face recognition logs
tail -f /tmp/recognize.log

# Check what's happening
docker compose logs -f app | grep -i recognize

# Check resource usage during processing
docker stats
```

**Performance expectations (4 GB RAM / 2 vCPU instance):**
- Initial scan: Several hours to overnight for 157 GB
- Incremental scans: 5-15 minutes for new photos
- Accuracy: Good (same as high-end servers)
- Speed: Slower than powerful servers but totally usable
- Face recognition improves as you name more faces

## Performance Tips

### 1. Enable Video Transcoding (Essential for MTS/AVI/MKV files)
Allows smooth video playback without downloading entire files. **Required for camcorder MTS files** and other non-web formats.

**One-time setup (automated script):**
```bash
# SSH to your server
ssh ubuntu@<your-ip>
cd ~/nextcloud-aws
./scripts/setup-video-transcoding.sh
```

This script automatically:
- Verifies ffmpeg is installed
- Enables video preview providers (MP4, MTS, AVI, MKV, MOV, etc.)
- Configures Memories for transcoding
- Sets transcoding quality to 1080p
- Tests the setup

**Supported video formats after setup:**
- ✅ **MTS** (AVCHD camcorder files) - auto-transcoded to MP4
- ✅ **MP4** (plays natively)
- ✅ **MOV** (iPhone/QuickTime)
- ✅ **AVI** (older format) - auto-transcoded
- ✅ **MKV** (Matroska) - auto-transcoded
- ✅ **WebM, FLV** and more

**How it works:**
1. Upload videos to Nextcloud (any format)
2. Play in Memories app
3. First playback: Takes 30-60 seconds to transcode (one-time)
4. Subsequent playback: Instant from cache

**Performance expectations (4GB RAM / 2 vCPU):**
- 1080p videos: Smooth transcoding and playback
- 4K videos: Slower transcoding but works
- MTS camcorder files: Convert to H.264 MP4 automatically
- Cache stored in Nextcloud data directory

**Monitor transcoding progress:**
```bash
# Watch transcoding in real-time
docker compose logs -f app | grep -i ffmpeg

# Check resource usage
docker stats
```

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
# Setup scripts (one-time)
./scripts/setup-auto-previews.sh       # Configure automatic thumbnails
./scripts/setup-face-recognition.sh    # Configure face recognition
./scripts/setup-video-transcoding.sh   # Configure video transcoding (MTS, AVI, MKV)

# Generate all previews
./scripts/generate-previews.sh

# Run face recognition
docker compose exec -u www-data app php occ recognize:classify

# Scan new files
docker compose exec -u www-data app php occ files:scan --all

# Check Nextcloud status
docker compose exec -u www-data app php occ status

# Restart containers (apply config changes)
docker compose restart

# Check logs
docker compose logs -f app
tail -f /tmp/recognize.log            # Face recognition logs
tail -f /tmp/preview-generate.log     # Preview generation logs

# Check resource usage
docker stats
```

## Recommended Workflow

1. ✅ Install Memories app
2. ✅ Set up automatic preview generation: `./scripts/setup-auto-previews.sh`
3. ✅ Upload photos via desktop client or MultCloud
4. ✅ Run preview generation once uploaded: `./scripts/generate-previews.sh`
5. ✅ Set up face recognition: `./scripts/setup-face-recognition.sh`
6. ✅ Name faces in Memories People tab
7. ✅ Set up cron jobs for automatic processing
8. ✅ Enjoy fast photo browsing with AI-powered face recognition!

---

**Last updated:** January 19, 2026
**Instance specs:** 4 GB RAM, 2 vCPU, 300 GB storage
