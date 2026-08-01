#!/usr/bin/bash

# mpd-notifier Installer
#
# Copies mpd-notifier.sh, mpd-notifier-watch.sh, mpd-notifier.conf.example,
# and unknown.jpg to ~/bin, then adds an autostart entry that runs the watch
# loop (which fires mpd-notifier.sh on every MPD player-state change) at
# login. Run ../install.sh first if ~/bin isn't already on your PATH.

set -e  # Exit on error

INSTALL_DIR="$HOME/bin"
DESKTOP_FILE="$HOME/.config/autostart/mpd-notifier.desktop"

echo "Installing mpd-notifier..."

mkdir -p "$INSTALL_DIR"

echo "Copying files to $INSTALL_DIR..."
cp mpd-notifier.sh mpd-notifier-watch.sh mpd-notifier.conf.example unknown.jpg "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/mpd-notifier.sh" "$INSTALL_DIR/mpd-notifier-watch.sh"

mkdir -p "$HOME/.config/autostart"

if ! grep -q "Exec=$INSTALL_DIR/mpd-notifier-watch.sh" "$DESKTOP_FILE" 2>/dev/null; then
    echo "Adding mpd-notifier to autostart..."
    {
        echo "[Desktop Entry]"
        echo "Type=Application"
        echo "Exec=$INSTALL_DIR/mpd-notifier-watch.sh"
        echo "Name=MPD Notifier"
        echo "Comment=Shows a desktop notification when the currently playing MPD track changes"
    } > "$DESKTOP_FILE"
else
    echo "mpd-notifier is already in autostart."
fi

echo "Installation complete! Log out and back in for it to start automatically,"
echo "or run this now: $INSTALL_DIR/mpd-notifier-watch.sh &"
