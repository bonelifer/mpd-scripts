#!/usr/bin/bash

# alarmpd Installer -- XDG autostart entry
#
# Installs alarmpd.py to ~/bin and creates a
# ~/.config/autostart/alarmpd.desktop entry so it starts automatically at
# login. See install-systemd.sh for a systemd --user service alternative
# instead. Don't run both installers -- pick one.

set -e  # Exit on error

INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="alarmpd.py"
CONF_EXAMPLE="alarmpd.conf.example"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
AUTOSTART_ENTRY="$SCRIPT_PATH"  # Autostart entry for the daemon (already executable with its own shebang)
DESKTOP_FILE="$HOME/.config/autostart/alarmpd.desktop"

echo "Installing alarmpd..."

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

# Copy daemon script and its config template to ~/bin
echo "Copying daemon script to $SCRIPT_PATH..."
cp "$SCRIPT_NAME" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"
cp "$CONF_EXAMPLE" "$INSTALL_DIR/$CONF_EXAMPLE"

# Ensure the autostart directory exists
mkdir -p "$HOME/.config/autostart"

# Check if the autostart entry already exists
if ! grep -q "Exec=$AUTOSTART_ENTRY" "$DESKTOP_FILE" 2>/dev/null; then
    echo "Adding alarmpd to autostart..."

    # Create the autostart entry
    echo "[Desktop Entry]" > "$DESKTOP_FILE"
    echo "Type=Application" >> "$DESKTOP_FILE"
    echo "Exec=$AUTOSTART_ENTRY" >> "$DESKTOP_FILE"
    echo "Name=alarmpd" >> "$DESKTOP_FILE"
    echo "Comment=Starts alarmpd at login" >> "$DESKTOP_FILE"
else
    echo "alarmpd is already in autostart."
fi

echo "Installation complete! Please restart your shell or run:"
echo "  source ~/.bashrc"
echo "alarmpd is now configured to start on login."
