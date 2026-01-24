#!/bin/bash
set -eu

while true; do
    php -f /var/www/html/cron.php
    sleep 300
done
