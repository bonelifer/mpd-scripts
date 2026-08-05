#!/usr/bin/bash

# mpd-algo-playlist monitor systemd --user service installer
#
# Installs and enables monitor.py as a systemd --user service, giving
# auto-restart on crash and journald logging. Run install.sh first (or make
# sure client.py/db.py/paths.py/monitor.py are already in ~/bin) - this
# script only installs the unit file, it doesn't copy the scripts itself.

set -e  # Exit on error

UNIT_NAME="mpd-algo-playlist-monitor.service"
UNIT_DIR="$HOME/.config/systemd/user"  # Per-user systemd unit search path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "$HOME/bin/monitor.py" ]; then
    echo "Warning: $HOME/bin/monitor.py not found. Run install.sh first." >&2
fi

mkdir -p "$UNIT_DIR"
echo "Installing systemd unit to $UNIT_DIR/$UNIT_NAME..."
cp "$SCRIPT_DIR/$UNIT_NAME" "$UNIT_DIR/$UNIT_NAME"

# Re-scan unit files for the new one, then start it now and mark it to
# start automatically on every future login.
systemctl --user daemon-reload
systemctl --user enable --now "$UNIT_NAME"

echo "Installation complete! Check status with:"
echo "  systemctl --user status $UNIT_NAME"
echo "View logs with:"
echo "  journalctl --user -u $UNIT_NAME -f"
echo "(or ~/.local/state/mpd-algo-playlist/monitor.log, which the daemon also writes itself)"
