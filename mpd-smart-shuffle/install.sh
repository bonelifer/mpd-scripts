#!/usr/bin/bash

# mpd-smart-shuffle installer
#
# Installs client.py/db.py/paths.py/monitor.py/randomtrack.py/db_admin.py
# (and their .example config/list templates) to ~/bin, then offers to also
# install monitor.py as an optional systemd --user background service (see
# install-systemd.sh). randomtrack.py and db_admin.py work standalone
# without the daemon -- randomtrack.py is meant to be run periodically via
# cron (see README.md), db_admin.py is a manual maintenance CLI.

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/bin"

SCRIPT_FILES="client.py db.py paths.py monitor.py randomtrack.py db_admin.py"
TEMPLATE_FILES="config.ini.example exclude_files.txt.example exclude_artists.txt.example exclude_genres.txt.example notify_urls.txt.example"

echo "Installing mpd-smart-shuffle..."

echo "Installing Python dependencies (python-mpd2, lmdb, mutagen, python-dateutil)..."
pip3 install --user python-mpd2 lmdb mutagen python-dateutil

echo
read -r -p "Also install apprise (only needed for the low_eligible_alert notification feature)? [y/N] " REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    pip3 install --user apprise
fi

mkdir -p "$INSTALL_DIR"

echo
echo "Copying scripts to $INSTALL_DIR..."
for f in $SCRIPT_FILES; do
    cp "$SCRIPT_DIR/$f" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/$f"
done

echo "Copying config/list templates to $INSTALL_DIR..."
for f in $TEMPLATE_FILES; do
    cp "$SCRIPT_DIR/$f" "$INSTALL_DIR/"
done

echo
echo "Installed. config.ini and the exclude/notify list files get seeded into"
echo "~/.config/mpd-scripts/mpd-smart-shuffle/ the first time you run any script"
echo "(monitor.py, randomtrack.py, or db_admin.py) - edit the copies there."
echo
echo "Set music_dir (and anything else you want to change) in that config"
echo "before running randomtrack.py for real."

echo
read -r -p "Also install monitor.py as a systemd --user background service (records play history automatically)? [y/N] " REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    "$SCRIPT_DIR/install-systemd.sh"
else
    echo "Skipped. Run install-systemd.sh later if you change your mind, or invoke monitor.py manually."
fi

echo
echo "Add randomtrack.py to your crontab to periodically top up the MPD queue - see README.md for an example."
