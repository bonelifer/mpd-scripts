#!/usr/bin/bash

# MPD Rewind Daemon Installer

set -e  # Exit on error

INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="mpd_rewind_daemon.py"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
USER_HOME=$(eval echo ~$USER)  # Dynamically get the user's home directory
AUTOSTART_ENTRY="/usr/bin/python3 $SCRIPT_PATH"  # Autostart entry for the daemon
DESKTOP_FILE="$HOME/.config/autostart/mpd-rewind.desktop"
USERNAME=$(whoami)

echo "Installing MPD Rewind Daemon..."

# Ensure ~/bin exists and add it to PATH
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Creating $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    
    # Since ~/bin didn't exist, assume it's not in PATH and add it
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/bin to PATH in .bashrc"
fi

# Ensure ~/.local/bin is in PATH for pip installs
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/.local/bin to PATH in .bashrc"
fi

# Install dependencies
echo "Installing python-mpd2..."
pip3 install --user python-mpd2

# Copy daemon script to ~/bin
echo "Copying daemon script to $SCRIPT_PATH..."
cp "$SCRIPT_NAME" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

# Ensure the autostart directory exists
mkdir -p "$HOME/.config/autostart"

# Check if the autostart entry already exists
if ! grep -q "Exec=$AUTOSTART_ENTRY" "$DESKTOP_FILE" 2>/dev/null; then
    echo "Adding MPD Rewind Daemon to autostart..."

    # Create the autostart entry
    echo "[Desktop Entry]" > "$DESKTOP_FILE"
    echo "Type=Application" >> "$DESKTOP_FILE"
    echo "Exec=$AUTOSTART_ENTRY" >> "$DESKTOP_FILE"
    echo "Name=MPD Rewind Daemon" >> "$DESKTOP_FILE"
    echo "Comment=Starts MPD rewind daemon at login" >> "$DESKTOP_FILE"
else
    echo "MPD Rewind Daemon is already in autostart."
fi

# Set permissions for the log file
echo "Creating Log file and setting permissions..."
sudo touch /var/log/mpd_rewind_daemon.log
sudo chmod 666 /var/log/mpd_rewind_daemon.log

echo "Installation complete! Please restart your shell or run:"
echo "  source ~/.bashrc"
echo "MPD Rewind Daemon is now configured to start on login."

