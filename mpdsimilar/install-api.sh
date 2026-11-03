#!/usr/bin/bash

# mpdsimilar on/off switch API installer
#
# Installs mpdsimilar-api.py (and its api.conf.example template) to ~/bin
# and enables it as a systemd --user service, so mpdsimilar.sh can be
# switched on or off from a browser or curl at http://127.0.0.1:8095/.
# Optional: mpdsimilar.sh's -t/--on/--off options switch the same file
# without the daemon. Standard library Python only, so nothing else to
# install.

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="mpdsimilar-api.py"
TEMPLATE_NAME="api.conf.example"
UNIT_NAME="mpdsimilar-api.service"
UNIT_DIR="$HOME/.config/systemd/user"  # Per-user systemd unit search path

echo "Installing the mpdsimilar on/off switch API (systemd --user service)..."

mkdir -p "$INSTALL_DIR"

echo "Copying $SCRIPT_NAME and $TEMPLATE_NAME to $INSTALL_DIR..."
cp "$SCRIPT_DIR/$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
cp "$SCRIPT_DIR/$TEMPLATE_NAME" "$INSTALL_DIR/$TEMPLATE_NAME"

mkdir -p "$UNIT_DIR"
echo "Installing systemd unit to $UNIT_DIR/$UNIT_NAME..."
cp "$SCRIPT_DIR/$UNIT_NAME" "$UNIT_DIR/$UNIT_NAME"

# Re-scan unit files for the new one, then start it now and mark it to
# start automatically on every future login.
systemctl --user daemon-reload
systemctl --user enable --now "$UNIT_NAME"

echo "Installation complete! Open http://127.0.0.1:8095/ (port set in"
echo "$HOME/.config/mpd-scripts/mpdsimilar/api.conf). Check status with:"
echo "  systemctl --user status $UNIT_NAME"
echo "View logs with:"
echo "  journalctl --user -u $UNIT_NAME -f"
