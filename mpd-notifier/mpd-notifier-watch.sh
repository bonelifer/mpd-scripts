#!/bin/bash

# Runs mpd-notifier.sh once per MPD player-state change (song change,
# play/pause/stop), blocking on `mpc idle player` between events instead of
# polling. Reads MPD_HOST from mpd-notifier's own config so it watches the
# same server the notifier queries.
#
# Usage: run this in the background (e.g. from a session autostart entry)
# instead of calling mpd-notifier.sh directly.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NOTIFIER="$SCRIPT_DIR/mpd-notifier.sh"

if ! command -v mpc &>/dev/null; then
    echo "Error: 'mpc' is required but not installed." >&2
    exit 1
fi

config_file="$HOME/.config/mpd-notifier/mpd-notifier.conf"
MPD_HOST=""
if [ -f "$config_file" ]; then
    # shellcheck source=/dev/null
    source "$config_file"
fi

while true; do
    if [ -n "${MPD_HOST}" ]; then
        mpc -h "${MPD_HOST}" -p 6600 idle player >/dev/null 2>&1
    else
        mpc idle player >/dev/null 2>&1
    fi

    # A non-zero exit here usually means MPD isn't reachable; back off
    # briefly instead of busy-looping until it comes back.
    if [ $? -ne 0 ]; then
        sleep 2
        continue
    fi

    "$NOTIFIER"
done
