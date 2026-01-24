FROM nextcloud:apache

# Install ffmpeg for video preview generation
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*
