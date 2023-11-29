#!/bin/bash

# Script Name: mpd-installer.sh
# Description: This script installs the MPD web server components, including the necessary Python files and service configuration.
# Author: [Your Name]
# Usage: ./mpd-installer.sh
# Dependencies: Python 3.x, systemctl
# Last Modified: [Date]

# Instructions:
# - Ensure Python 3.x is installed on the system.
# - Set appropriate paths for the files (image_server.py, image_server.service).
# - Run this script using './mpd-installer.sh'.

# BEGIN User Editable Block
WEB_SERVER_DIR="~/mpd-web-server"
# END User Editable Block

# Set paths for files
IMAGE_SERVER_PY="image_server.py"
IMAGE_SERVER_SERVICE="image_server.service"

# Script logic:
# - Checks for Python 3.x, installs it if not found.
# - Creates a directory for the web server files if it doesn't exist.
# - Copies required files (image_server.py, image_server.service) to appropriate locations.
# - Enables and starts the image_server service using systemctl.

# Install Python if not already installed
if ! command -v python3 &>/dev/null; then
    echo "Installing Python..."
    sudo apt-get update
    sudo apt-get install -y python3
fi

# Create a directory for the web server files if it doesn't exist
if [ ! -d "$WEB_SERVER_DIR" ]; then
    mkdir -p "$WEB_SERVER_DIR"
fi

# Copy necessary files to the web server directory
cp "$IMAGE_SERVER_PY" "$WEB_SERVER_DIR/"
cp "$IMAGE_SERVER_SERVICE" /etc/systemd/system/

# Check if file copies were successful
if [ $? -ne 0 ]; then
    echo "Error copying files. Exiting."
    exit 1
fi

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable image_server
sudo systemctl start image_server

if [ $? -eq 0 ]; then
    echo "MPD web server installation complete."
else
    echo "Failed to start the MPD web server."
fi

