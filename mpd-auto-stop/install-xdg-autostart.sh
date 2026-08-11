#!/usr/bin/bash

# mpd-auto-stop Installer -- XDG autostart entry
#
# Installs mpd-auto-stop.py to ~/bin and creates a
# ~/.config/autostart/mpd-auto-stop.desktop entry so it starts
# automatically at login. See install-systemd.sh for a systemd --user
# service alternative instead. Don't run both installers -- pick one.

set -e  # Exit on error

INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="mpd-auto-stop.py"
CONF_EXAMPLE="mpd-auto-stop.conf.example"
TEMPLATE="index.html"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
AUTOSTART_ENTRY="$SCRIPT_PATH"  # Autostart entry for the daemon (already executable with its own shebang)
DESKTOP_FILE="$HOME/.config/autostart/mpd-auto-stop.desktop"

echo "Installing mpd-auto-stop..."

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

# Copy daemon script and its companion files to ~/bin
echo "Copying daemon script to $SCRIPT_PATH..."
cp "$SCRIPT_NAME" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"
cp "$CONF_EXAMPLE" "$INSTALL_DIR/$CONF_EXAMPLE"
cp "$TEMPLATE" "$INSTALL_DIR/$TEMPLATE"

# Ensure the autostart directory exists
mkdir -p "$HOME/.config/autostart"

# Check if the autostart entry already exists
if ! grep -q "Exec=$AUTOSTART_ENTRY" "$DESKTOP_FILE" 2>/dev/null; then
    echo "Adding mpd-auto-stop to autostart..."

    # Create the autostart entry
    echo "[Desktop Entry]" > "$DESKTOP_FILE"
    echo "Type=Application" >> "$DESKTOP_FILE"
    echo "Exec=$AUTOSTART_ENTRY" >> "$DESKTOP_FILE"
    echo "Name=mpd-auto-stop" >> "$DESKTOP_FILE"
    echo "Comment=Starts mpd-auto-stop at login" >> "$DESKTOP_FILE"
else
    echo "mpd-auto-stop is already in autostart."
fi

echo "Installation complete! Please restart your shell or run:"
echo "  source ~/.bashrc"
echo "mpd-auto-stop is now configured to start on login."
