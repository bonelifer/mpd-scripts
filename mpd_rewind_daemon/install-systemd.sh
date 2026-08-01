#!/usr/bin/bash

# MPD Rewind Daemon systemd --user service installer
#
# Alternative to install-xdg-autostart.sh's XDG autostart .desktop entry:
# installs and enables mpd_rewind_daemon.py as a systemd --user service
# instead, giving auto-restart on crash and journald logging. Run
# ../install.sh first if ~/bin isn't already on your PATH. Don't run
# both installers -- pick one.

set -e  # Exit on error

INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="mpd_rewind_daemon.py"
UNIT_NAME="mpd-rewind-daemon.service"
UNIT_DIR="$HOME/.config/systemd/user"  # Per-user systemd unit search path

echo "Installing MPD Rewind Daemon (systemd --user service)..."

mkdir -p "$INSTALL_DIR"

echo "Installing python-mpd2..."
pip3 install --user python-mpd2

echo "Copying daemon script to $INSTALL_DIR/$SCRIPT_NAME..."
cp "$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

mkdir -p "$UNIT_DIR"
echo "Installing systemd unit to $UNIT_DIR/$UNIT_NAME..."
cp "$UNIT_NAME" "$UNIT_DIR/$UNIT_NAME"

# Re-scan unit files for the new one, then start it now and mark it to
# start automatically on every future login.
systemctl --user daemon-reload
systemctl --user enable --now "$UNIT_NAME"

echo "Installation complete! Check status with:"
echo "  systemctl --user status $UNIT_NAME"
echo "View logs with:"
echo "  journalctl --user -u $UNIT_NAME -f"
