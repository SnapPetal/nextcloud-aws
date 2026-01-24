FROM nextcloud:apache

# Install additional tools for preview generation and process management
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        ghostscript \
        imagemagick \
        procps \
        supervisor \
    ; \
    rm -rf /var/lib/apt/lists/*

# Create supervisor directories
RUN mkdir -p \
    /var/log/supervisord \
    /var/run/supervisord \
;

COPY supervisord.conf /
COPY cron.sh /
RUN chmod +x /cron.sh

ENV NEXTCLOUD_UPDATE=1

CMD ["/usr/bin/supervisord", "-c", "/supervisord.conf"]
