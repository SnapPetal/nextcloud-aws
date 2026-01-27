# Photo & Video Optimization Guide

This guide covers optimizing Nextcloud for handling large photo and video collections on your 8 GB RAM / 2 vCPU instance.

## Current Optimizations

### Hardware
- **Instance**: 8 GB RAM, 2 vCPU
- **Storage**: 300 GB SSD + S3 external storage
- **Database**: Local MariaDB container

### Software Configuration
- **PHP Memory**: 4 GB
- **Opcache**: Enabled for faster PHP execution
- **Redis**: Caching enabled
- **Upload Limit**: 10 GB for large video files

## Recommended Apps for Photos

### 1. Preview Generator (Automatic Thumbnails)
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

### 2. Face Recognition via Recognize App
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

1. **View recognized faces:**
   - Go to https://cloud.thonbecker.biz/apps/photos
   - Browse by People/Faces
   - See all detected faces grouped by similarity

2. **Name people:**
   - Click on a face cluster
   - Assign a name to the person
   - All photos with that face are tagged

3. **Merge duplicate clusters:**
   - If same person appears in multiple clusters
   - Select and merge them
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

**Performance expectations (8 GB RAM / 2 vCPU instance):**
- Initial scan: Several hours for large collections
- Incremental scans: 5-15 minutes for new photos
- Accuracy: Good (same as high-end servers)
- Face recognition improves as you name more faces

## Performance Tips

### 1. Video Format Compatibility & Conversion

**Natively supported formats (play instantly in browser):**
- ✅ **MP4** (H.264/H.265) - Best compatibility
- ✅ **WebM** - Web-optimized format
- ✅ **MOV** (H.264) - iPhone videos

**Non-supported formats (won't play in browser):**
- ❌ **MTS** (AVCHD camcorder files)
- ❌ **AVI** (older format)
- ❌ **MKV** (Matroska container)

**Recommended: Convert to MP4 Before Uploading**

Converting MTS/AVI/MKV to MP4 before upload gives you:
- ✅ Instant playback in browser (no transcoding delay)
- ✅ Smaller file sizes (20-30% reduction typical)
- ✅ Better compatibility across all devices
- ✅ No server configuration needed

**How to Convert Videos to MP4:**

**Option 1: HandBrake (Easiest, Free)**
1. Download: https://handbrake.fr/
2. Drag your MTS/AVI/MKV files into HandBrake
3. Select preset: "Fast 1080p30" or "Very Fast 1080p30"
4. Click "Start Encode"
5. Upload the converted MP4 files to Nextcloud

**Option 2: VLC Media Player**
1. Open VLC → Media → Convert/Save
2. Add your video files
3. Profile: "Video - H.264 + MP3 (MP4)"
4. Choose destination filename
5. Click "Start"

**Option 3: FFmpeg Command Line** (if installed on your computer)
```bash
# Single file
ffmpeg -i video.mts -c:v libx264 -crf 23 -c:a aac video.mp4

# Batch convert all MTS files in a folder
for file in *.mts; do ffmpeg -i "$file" -c:v libx264 -crf 23 -c:a aac "${file%.mts}.mp4"; done
```

**Storage impact:**
- MTS videos are often larger than MP4
- Converting typically saves 20-30% space
- Example: 10 GB of MTS → ~7-8 GB of MP4

**After conversion:**
- Upload MP4 files to Nextcloud
- They play instantly in browser
- Work perfectly on all devices

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
2. Verify Redis is working: `docker compose logs redis`
3. Check available RAM: `free -h`

### Videos Won't Play
1. Check video format compatibility (MP4/H.264 works best)
2. Convert non-compatible formats to MP4 before upload
3. Check PHP memory limit is sufficient (currently 4G)

### Out of Memory Errors
```bash
# Check current memory usage
docker stats

# If needed, adjust PHP memory in docker-compose.yml
# Current: PHP_MEMORY_LIMIT=2G
# Can increase if you have available RAM
```

## Expected Performance

With your 8 GB RAM / 2 vCPU setup:

- **Photo browsing**: Fast with generated previews
- **Video playback**: Works well with MP4/H.264 format
- **Upload speeds**: Limited by network, not server
- **Face recognition**: Good performance via Recognize app
- **Concurrent users**: 5-10 users browsing simultaneously
- **Large uploads**: 10 GB files supported

## External Storage (S3)

S3 external storage is configured for cloud backup:
- Mount point: `/Cloud Storage`
- Use for archiving older photos
- Move files between local and S3 in Nextcloud UI
- Keeps primary storage lean while backing up to cloud

## Future Upgrades

If you need even better performance:

1. **Add CDN** (CloudFront)
   - Faster photo delivery globally
   - Reduced server load

2. **Expand S3 storage**
   - Lightsail buckets scale automatically
   - Cost-effective for large archives

## Quick Commands Reference

```bash
# Setup scripts (one-time)
./scripts/setup-auto-previews.sh       # Configure automatic thumbnails
./scripts/setup-face-recognition.sh    # Configure face recognition

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

1. Set up automatic preview generation: `./scripts/setup-auto-previews.sh`
2. Upload photos via desktop client or MultCloud
3. Run preview generation once uploaded: `./scripts/generate-previews.sh`
4. Set up face recognition: `./scripts/setup-face-recognition.sh`
5. Name faces in Photos app
6. Set up cron jobs for automatic processing
7. Use S3 Cloud Storage for backups and archives

---

**Last updated:** January 27, 2026
**Instance specs:** 8 GB RAM, 2 vCPU, 300 GB local storage + S3
