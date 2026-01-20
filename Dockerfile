# Custom Nextcloud image with ffmpeg for video transcoding
FROM nextcloud:apache

# Install ffmpeg for video transcoding (MTS, AVI, MKV support)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*
