# CloudFront or ALB Setup for Nextcloud

This guide covers setting up AWS CloudFront or Application Load Balancer (ALB) to provide public HTTPS access to your private Nextcloud instance.

## Architecture

```
Internet → CloudFront/ALB (HTTPS) → Private Lightsail Instance (HTTP:80) → Nextcloud
                                   ↓
                              Lightsail Database
```

## Option 1: Application Load Balancer (ALB) - Recommended for Lightsail

### Why ALB?
- Native integration with Lightsail
- Automatic SSL/TLS certificate management with ACM
- Health checks and auto-recovery
- WebSocket support (needed for Nextcloud Talk)

### Setup Steps

#### 1. Create Target Group

```bash
# Using AWS CLI (or use AWS Console)
aws elbv2 create-target-group \
  --name nextcloud-targets \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-xxxxxxxx \
  --health-check-enabled \
  --health-check-path /status.php \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3
```

#### 2. Register Lightsail Instance

```bash
# Get your Lightsail instance ID
aws lightsail get-instance --instance-name your-instance-name

# Register target
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:region:account:targetgroup/nextcloud-targets/xxx \
  --targets Id=i-xxxxxxxxx
```

#### 3. Create Application Load Balancer

```bash
aws elbv2 create-load-balancer \
  --name nextcloud-alb \
  --subnets subnet-xxxxxxxx subnet-yyyyyyyy \
  --security-groups sg-xxxxxxxx \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4
```

#### 4. Request SSL Certificate (ACM)

1. Go to AWS Certificate Manager (ACM)
2. Request a public certificate
3. Domain name: `nextcloud.yourdomain.com`
4. Validation method: DNS validation
5. Add the CNAME records to your DNS
6. Wait for validation (usually 5-10 minutes)

#### 5. Create HTTPS Listener

```bash
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:region:account:loadbalancer/app/nextcloud-alb/xxx \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=arn:aws:acm:region:account:certificate/xxx \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:region:account:targetgroup/nextcloud-targets/xxx
```

#### 6. Create HTTP to HTTPS Redirect

```bash
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:region:account:loadbalancer/app/nextcloud-alb/xxx \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=redirect,RedirectConfig='{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}'
```

#### 7. Configure Security Groups

**ALB Security Group:**
- Inbound: Port 443 (HTTPS) from 0.0.0.0/0
- Inbound: Port 80 (HTTP) from 0.0.0.0/0
- Outbound: Port 80 to Lightsail instance security group

**Lightsail Instance Firewall:**
- Inbound: Port 80 from ALB security group only
- Inbound: Port 22 for SSH (from your IP only)

#### 8. Update DNS

Point your domain to the ALB:
```
nextcloud.yourdomain.com → CNAME → nextcloud-alb-xxxxxxxxx.region.elb.amazonaws.com
```

Or use an A record with ALIAS (Route53 only):
```
nextcloud.yourdomain.com → A ALIAS → ALB DNS name
```

### Cost: ~$16-20/month for ALB

---

## Option 2: CloudFront CDN

### Why CloudFront?
- Global CDN for faster access worldwide
- DDoS protection with AWS Shield
- Lower cost than ALB for low traffic
- Better for static file caching

### Setup Steps

#### 1. Request SSL Certificate in us-east-1

**IMPORTANT:** CloudFront requires certificates in us-east-1 region.

```bash
aws acm request-certificate \
  --domain-name nextcloud.yourdomain.com \
  --validation-method DNS \
  --region us-east-1
```

Validate the certificate using DNS validation.

#### 2. Create CloudFront Distribution

```bash
# Create distribution config file
cat > cloudfront-config.json << 'EOF'
{
  "CallerReference": "nextcloud-$(date +%s)",
  "Aliases": {
    "Quantity": 1,
    "Items": ["nextcloud.yourdomain.com"]
  },
  "DefaultRootObject": "index.php",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "nextcloud-origin",
        "DomainName": "your-lightsail-private-ip",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only",
          "OriginSslProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
          }
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "nextcloud-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 7,
      "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "ForwardedValues": {
      "QueryString": true,
      "Cookies": {
        "Forward": "all"
      },
      "Headers": {
        "Quantity": 4,
        "Items": ["Host", "Origin", "Authorization", "Content-Type"]
      }
    },
    "MinTTL": 0,
    "DefaultTTL": 0,
    "MaxTTL": 86400,
    "Compress": true
  },
  "ViewerCertificate": {
    "ACMCertificateArn": "arn:aws:acm:us-east-1:account:certificate/xxx",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  },
  "Enabled": true
}
EOF

aws cloudfront create-distribution --distribution-config file://cloudfront-config.json
```

#### 3. Configure Cache Behaviors for Nextcloud

Nextcloud needs special cache rules. Create additional cache behaviors:

**No-Cache paths** (must NOT be cached):
- `/index.php/*`
- `/status.php`
- `/ocs/*`
- `/remote.php/*`
- `/cron.php`

**Cacheable paths**:
- `/core/css/*`
- `/core/js/*`
- `/apps/*/css/*`
- `/apps/*/js/*`

#### 4. Update DNS

```
nextcloud.yourdomain.com → CNAME → d1234567890abc.cloudfront.net
```

### Cost: ~$1-5/month for low traffic + data transfer costs

---

## Console Setup (Easier Alternative)

### ALB via AWS Console

1. **EC2 Console** → Load Balancers → Create Load Balancer
2. Choose **Application Load Balancer**
3. Name: `nextcloud-alb`
4. Scheme: Internet-facing
5. IP address type: IPv4
6. Listeners: Add HTTPS:443 and HTTP:80
7. Availability Zones: Select your VPC and subnets
8. Security groups: Create/select appropriate security group
9. Target group: Create new, HTTP:80, health check path: `/status.php`
10. Register targets: Add your Lightsail instance
11. SSL certificate: Select from ACM or upload
12. Review and create

### CloudFront via AWS Console

1. **CloudFront Console** → Create Distribution
2. Origin domain: Your Lightsail private IP
3. Protocol: HTTP only
4. Enable Origin Shield: No
5. Default cache behavior:
   - Viewer protocol policy: Redirect HTTP to HTTPS
   - Allowed HTTP methods: GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE
   - Cache policy: CachingDisabled (or custom)
   - Origin request policy: AllViewer
6. Settings:
   - Alternate domain names (CNAMEs): `nextcloud.yourdomain.com`
   - Custom SSL certificate: Select from ACM (us-east-1)
7. Create distribution

---

## Testing

### Test ALB/CloudFront Setup

```bash
# Test HTTPS connection
curl -I https://nextcloud.yourdomain.com

# Check headers
curl -v https://nextcloud.yourdomain.com/status.php

# Verify origin IP is hidden
dig nextcloud.yourdomain.com
```

### Verify Nextcloud Configuration

```bash
# Check trusted domains
docker compose exec -u www-data app php occ config:system:get trusted_domains

# Check trusted proxies
docker compose exec -u www-data app php occ config:system:get trusted_proxies

# Test from Nextcloud side
docker compose exec app curl -I http://localhost/status.php
```

---

## Troubleshooting

### 502 Bad Gateway
- Check Lightsail instance is running: `docker compose ps`
- Verify security group allows ALB → Instance traffic on port 80
- Check target health in ALB console

### Nextcloud "Untrusted Domain"
Update `config.php`:
```bash
docker compose exec -u www-data app php occ config:system:set trusted_domains 0 --value=nextcloud.yourdomain.com
docker compose exec -u www-data app php occ config:system:set trusted_proxies 0 --value=10.0.0.0/8
```

### CloudFront Caching Issues
- Clear CloudFront cache: Create invalidation for `/*`
- Check cache behavior settings
- Verify headers are being forwarded

### SSL Certificate Not Working
- Verify certificate is in `us-east-1` (CloudFront only)
- Check certificate status in ACM
- Ensure DNS validation is complete

---

## Recommendations

**For most Nextcloud deployments: Use ALB**
- Better for dynamic content
- WebSocket support
- Easier configuration
- Native health checks

**Use CloudFront if:**
- You have global users
- You want DDoS protection
- Cost is a concern (very low traffic)
- You need edge caching for static files

**Best of both worlds:**
CloudFront → ALB → Nextcloud (expensive but provides all benefits)
