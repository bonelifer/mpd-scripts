#!/bin/bash

# Runs mpd-notifier.sh once per MPD player-state change (song change,
# play/pause/stop), blocking on `mpc idle player` between events instead of
# polling. Reads MPD_HOST from mpd-notifier's own config so it watches the
# same server the notifier queries. Skips re-notifying on seeks within the
# same track (see get_signature below).
#
# Usage: run this in the background (e.g. from a session autostart entry)
# instead of calling mpd-notifier.sh directly.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NOTIFIER="$SCRIPT_DIR/mpd-notifier.sh"

if ! command -v mpc &>/dev/null; then
    echo "Error: 'mpc' is required but not installed." >&2
    exit 1
fi

config_file="$HOME/.config/mpd-scripts/mpd-notifier/mpd-notifier.conf"
MPD_HOST=""
if [ -f "$config_file" ]; then
    # shellcheck source=/dev/null
    source "$config_file"
fi

mpc_base=(mpc)
if [ -n "${MPD_HOST}" ]; then
    mpc_base=(mpc -h "${MPD_HOST}" -p 6600)
fi

# MPD's "player" idle event also fires on seeks within the current track, not
# just on track/play-state changes, which would otherwise re-notify on every
# scrub. Build a signature of "current file|play state" (deliberately
# excluding elapsed time) and only notify when it actually changes.
get_signature() {
    local file state raw
    file=$("${mpc_base[@]}" -f "%file%" current 2>/dev/null)
    raw=$("${mpc_base[@]}" 2>/dev/null)
    if echo "$raw" | grep -q '\[playing\]'; then
        state=playing
    elif echo "$raw" | grep -q '\[paused\]'; then
        state=paused
    else
        state=stopped
    fi
    echo "${file}|${state}"
}

last_signature=""

while true; do
    "${mpc_base[@]}" idle player >/dev/null 2>&1

    # A non-zero exit here usually means MPD isn't reachable; back off
    # briefly instead of busy-looping until it comes back.
    if [ $? -ne 0 ]; then
        sleep 2
        continue
    fi

    current_signature="$(get_signature)"
    if [ "$current_signature" != "$last_signature" ]; then
        last_signature="$current_signature"
        "$NOTIFIER"
    fi
done
