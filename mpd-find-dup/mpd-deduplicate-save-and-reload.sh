#!/usr/bin/bash

# Script: MPD Duplicate Removal (Save Current Queue to Playlist)
# Purpose: This script saves the current MPD queue to a playlist, removes duplicates, and reloads the cleaned playlist.
#
# Variables:
# - PLAYLIST_DIR: Directory where the playlists are stored.
# - PLAYLIST_NAME: Name of the playlist to save (without .m3u extension).
#
# Usage:
# 1. Set the PLAYLIST_DIR and PLAYLIST_NAME variables.
# 2. Ensure MPD and MPC are installed and configured.
# 3. Run the script.

# Hardcoded playlist directory
PLAYLIST_DIR="/path/to/your/mpd/playlists/"

# Name of the playlist to save (change this to your desired name)
PLAYLIST_NAME="current_playlist"
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
