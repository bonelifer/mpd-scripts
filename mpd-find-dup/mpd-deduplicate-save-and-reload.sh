#!/usr/bin/bash

# Script: MPD Duplicate Removal (Save Current Queue to Playlist)
# Purpose: This script saves the current MPD queue to a playlist, removes duplicates, and reloads the cleaned playlist.
#
# Usage:
#   mpd-deduplicate-save-and-reload.sh [-h|--help]
#
# Configuration:
#   PLAYLIST_DIR and PLAYLIST_NAME live in
#   ~/.config/mpd-scripts/mpd-find-dup/mpd-deduplicate-save-and-reload.conf,
#   seeded from mpd-deduplicate-save-and-reload.conf.example on first run.
#
#   PLAYLIST_DIR must match MPD's own configured playlist_directory: mpc
#   save/load/rm operate through MPD's own config, independent of this
#   script's PLAYLIST_DIR, which is only used to edit the saved playlist file
#   directly during the dedup step. If the two don't match, that step edits
#   a different file than the one MPD actually reloads.

set -e

display_help() {
    cat <<HELP
Usage: $(basename "$0") [OPTIONS]

Saves the current MPD queue to a playlist, removes duplicate entries from
that playlist file (preserving order), then clears the queue and reloads
the cleaned playlist.

Options:
  -h, --help  Show this help message.
HELP
    exit 0
}

case "${1:-}" in
    -h|--help) display_help ;;
    "") ;;
    *)
        echo "Unknown option: $1" >&2
        display_help
        ;;
esac

# Config lives in
# ~/.config/mpd-scripts/mpd-find-dup/mpd-deduplicate-save-and-reload.conf,
# seeded from the mpd-deduplicate-save-and-reload.conf.example template
# shipped alongside this script on first run.
CONFIG_DIR="$HOME/.config/mpd-scripts/mpd-find-dup"
CONFIG_FILE="$CONFIG_DIR/mpd-deduplicate-save-and-reload.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    mkdir -p "$CONFIG_DIR"
    cp "$(dirname "$0")/mpd-deduplicate-save-and-reload.conf.example" "$CONFIG_FILE"
    echo "Created $CONFIG_FILE -- edit it with your playlist directory, then run this again."
    exit 1
fi

# shellcheck source=mpd-deduplicate-save-and-reload.conf.example
source "$CONFIG_FILE"

if [[ "$PLAYLIST_DIR" == "/path/to/your/mpd/playlists/" ]]; then
    echo "Error: $CONFIG_FILE still has a placeholder PLAYLIST_DIR value. Edit it first."
    exit 1
fi

PLAYLIST_FILE="${PLAYLIST_DIR}/${PLAYLIST_NAME}.m3u"

# Function: save_current_queue_to_playlist
# Purpose: Saves the current MPD queue to a playlist file.
# Input: None
# Output: None
save_current_queue_to_playlist() {
  echo "Saving current queue to playlist file..."

  # Check if the playlist exists before deleting
  if mpc lsplaylists | grep -Fxq "$PLAYLIST_NAME"; then
    mpc rm "$PLAYLIST_NAME"
  fi

  # Check if the queue is empty before saving
  if mpc playlist | grep -q .; then
    mpc save "$PLAYLIST_NAME"
  else
    echo "Error: The current queue is empty. Aborting."
    exit 1
  fi
}

# Function: remove_duplicates_from_playlist
# Purpose: Processes the playlist file to remove duplicate entries.
# Input: None
# Output: None
remove_duplicates_from_playlist() {
  echo "Removing duplicates from playlist file..."
  # Use awk to remove duplicates while preserving order
  awk '!seen[$0]++' "$PLAYLIST_FILE" > "${PLAYLIST_FILE}.cleaned"
  mv "${PLAYLIST_FILE}.cleaned" "$PLAYLIST_FILE"
}

# Function: reload_playlist
# Purpose: Clears the current MPD queue and reloads the cleaned playlist.
# Input: None
# Output: None
reload_playlist() {
  echo "Clearing current MPD queue..."
  mpc clear  # Clear the current queue

  echo "Reloading cleaned playlist into MPD..."
  mpc load "$PLAYLIST_NAME"  # Load the cleaned playlist
  echo "Playlist reloaded."
}

# Main execution
save_current_queue_to_playlist
remove_duplicates_from_playlist
reload_playlist

echo "Duplicate removal complete."
