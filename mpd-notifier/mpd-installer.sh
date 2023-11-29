#!/bin/bash
# Script Name: mpd-installer.sh
# Description: This script installs the MPD web server components, including the necessary Python files and service configuration.
# Author: [Your Name]
# Usage: ./mpd-installer.sh
# Dependencies: Python 3.x, systemctl
# Last Modified: [Date]

# BEGIN User Editable Block
USER_MUSIC_DIR="$HOME/Music"
USER_CACHE_DIR="$HOME/.mpd-cache"
USER_IMAGE_DIR="$HOME/Images/AlbumCovers"
# END User Editable Block

# Set paths for files
IMAGE_SERVER_PY="image_server.py"
IMAGE_SERVER_SERVICE="image_server.service"
MPD_NOTIFIER_SH="mpd-notifier.sh"
MPD_WEBSERVER_PY="mpd-webserver.py"

# Define installation directory
INSTALL_DIR="$HOME/bin/mpd/mpd-web-server"

# Copy original files to installation directory
sudo mkdir -p "$INSTALL_DIR"
sudo cp "$IMAGE_SERVER_PY" "$INSTALL_DIR/"
sudo cp "$MPD_NOTIFIER_SH" "$INSTALL_DIR/"
sudo cp "$MPD_WEBSERVER_PY" "$INSTALL_DIR/"
sudo cp "$IMAGE_SERVER_SERVICE" /etc/systemd/system/

# Replace placeholders in copied files
sudo sed -i "s/placeholder_dir/$USER_MUSIC_DIR/g" "$INSTALL_DIR/$MPD_NOTIFIER_SH"
sudo sed -i "s/placeholder_cache_dir/$USER_CACHE_DIR/g" "$INSTALL_DIR/$MPD_NOTIFIER_SH"
sudo sed -i "s/placeholder_image_dir/$USER_IMAGE_DIR/g" "$INSTALL_DIR/$MPD_WEBSERVER_PY"
sudo sed -i "s|placeholder_path_to_image_server.py|$INSTALL_DIR/$MPD_WEBSERVER_PY|g" "/etc/systemd/system/$IMAGE_SERVER_SERVICE"

# Create cache directory if it doesn't exist
mkdir -p "$USER_CACHE_DIR"

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable image_server
sudo systemctl start image_server

if [ $? -eq 0 ]; then
    echo "MPD web server installation complete."
else
    echo "Failed to start the MPD web server."
fi

