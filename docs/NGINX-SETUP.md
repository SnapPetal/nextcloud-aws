# Nginx Reverse Proxy Setup for Nextcloud

This deployment uses Nginx as a reverse proxy to handle SSL/TLS termination with Let's Encrypt certificates.

## Architecture

```
Internet (HTTPS) → Nginx (port 443) → Docker Nextcloud (port 8080) → Nextcloud + Redis
```

## Why Nginx?

- Handles SSL/TLS certificates via Certbot
- Easy certificate auto-renewal
- Better performance for static files
- Industry standard for Docker deployments

## Installation Steps

### 1. Install Nginx

```bash
sudo apt install nginx -y
```

### 2. Configure Docker to Use Internal Port

The `docker-compose.yml` exposes Nextcloud only to localhost on port 8080:

```yaml
ports:
  - "127.0.0.1:8080:80"
```

This prevents direct external access to Docker container.

### 3. Create Nginx Configuration

Create `/etc/nginx/sites-available/nextcloud`:

```nginx
server {
    listen 80;
    server_name cloud.thonbecker.biz;

    # Redirect to HTTPS (Certbot will handle this)
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name cloud.thonbecker.biz;

    # SSL certificates (managed by Certbot)
    ssl_certificate /etc/letsencrypt/live/cloud.thonbecker.biz/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/cloud.thonbecker.biz/privkey.pem;

    # Logging
    access_log /var/log/nginx/nextcloud_access.log;
    error_log /var/log/nginx/nextcloud_error.log;

    # Max upload size
    client_max_body_size 10G;
    client_body_timeout 300s;
    fastcgi_buffers 64 4K;

    # Add headers for Nextcloud
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Download-Options "noopen" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Permitted-Cross-Domain-Policies "none" always;
    add_header X-Robots-Tag "noindex, nofollow" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # CalDAV and CardDAV redirects (required for iOS/Android sync)
    location = /.well-known/carddav {
        return 301 $scheme://$host/remote.php/dav;
    }

    location = /.well-known/caldav {
        return 301 $scheme://$host/remote.php/dav;
    }

    # Webfinger and NodeInfo (required for Nextcloud federation)
    location = /.well-known/webfinger {
        return 301 $scheme://$host/index.php/.well-known/webfinger;
    }

    location = /.well-known/nodeinfo {
        return 301 $scheme://$host/index.php/.well-known/nodeinfo;
    }

    # OCM provider (Open Cloud Mesh for federation)
    location = /ocm-provider/ {
        return 301 $scheme://$host/index.php/ocm-provider/;
    }

    # Proxy to Nextcloud container
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        proxy_buffering off;
        proxy_request_buffering off;
        proxy_max_temp_file_size 0;

        proxy_connect_timeout 600s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;
    }
}
```

Enable the site:

```bash
sudo ln -s /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
```

### 4. Install SSL Certificate

```bash
# Install Certbot Nginx plugin
sudo apt install python3-certbot-nginx -y

# Get certificate
sudo certbot --nginx -d cloud.thonbecker.biz
```

Certbot automatically:
- Obtains certificate from Let's Encrypt
- Configures Nginx for HTTPS
- Sets up auto-renewal

### 5. Verify SSL

Visit: https://cloud.thonbecker.biz

## Certificate Renewal

Certificates auto-renew via cron. Test renewal:

```bash
sudo certbot renew --dry-run
```

## Troubleshooting

### Check Nginx Status
```bash
sudo systemctl status nginx
```

### Test Nginx Configuration
```bash
sudo nginx -t
```

### View Nginx Logs
```bash
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

### Restart Services
```bash
# Restart Nginx
sudo systemctl restart nginx

# Restart Nextcloud containers
cd ~/nextcloud-aws
docker compose restart
```

### Force Certificate Renewal
```bash
sudo certbot renew --force-renewal
```

## Nginx Configuration Reference

The full Nginx config (after Certbot) is located at:
- `/etc/nginx/sites-available/nextcloud`
- `/etc/nginx/sites-enabled/nextcloud`

Certbot adds SSL configuration automatically.

## Performance Tuning

For better performance with large files, add to Nginx config:

```nginx
location / {
    proxy_pass http://127.0.0.1:8080;

    # Existing headers...

    # Performance improvements
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_max_temp_file_size 0;

    # Timeouts for large uploads
    proxy_connect_timeout 600s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
}
```

Then restart: `sudo systemctl restart nginx`
