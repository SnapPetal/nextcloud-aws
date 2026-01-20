# Custom Nextcloud image with ffmpeg for video transcoding
FROM nextcloud:apache

# Install ffmpeg and required dependencies for video transcoding
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ffmpeg \
    libmagickcore-6.q16-6-extra \
    ghostscript \
    && rm -rf /var/lib/apt/lists/*

# Re-enable ImageMagick policy for PDF (if needed)
RUN sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' \
    /etc/ImageMagick-6/policy.xml || true
