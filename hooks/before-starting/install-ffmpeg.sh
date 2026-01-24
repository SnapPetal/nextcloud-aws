#!/bin/bash
# Install ffmpeg if not already installed
if ! command -v ffmpeg &> /dev/null; then
    echo "Installing ffmpeg..."
    apt-get update && apt-get install -y --no-install-recommends ffmpeg
    rm -rf /var/lib/apt/lists/*
    echo "ffmpeg installed successfully"
fi
