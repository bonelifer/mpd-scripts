#!/usr/bin/bash

# Description:
# This script generates a random playlist of tracks from a local music directory using MPC.
# It filters tracks by artist, limits the number of tracks from each artist, and saves the 
# generated playlist as an M3U file in the specified playlist directory.
#
# The script:
# - Scans the specified local music directory for MP3 tracks.
# - Filters tracks by artist and limits the number of tracks based on the artist's total.
# - If the total number of filtered tracks is less than the target count, it fills up the list
#   with additional random tracks from the library.
# - Removes the base directory path when saving the playlist.
# - Checks if the playlist already exists in MPC and deletes it before creating a new one.
#
# Important:
# Before running the script, ensure that the following variables are correctly set:
# - `MUSIC_DIR`: Path to your local music directory containing MP3 files.
# - `PLAYLIST_DIR`: Path to the directory where MPC saves its playlists (typically with `.m3u` extension).
#
# Usage:
# - You can specify a custom track count and playlist name with the `-c` and `-p` options respectively.
# - If not specified, the script defaults to creating a playlist with 16,000 tracks named "random_playlist".

# Editable variables
# Set the path to your local music directory
MUSIC_DIR="/media/william/NewData/Music/MP3B/"

# Set the path to your MPC playlists directory
PLAYLIST_DIR="/media/william/NewData/homelab/mpd-alsa-docker/data/.mpd/playlists/"

# Default number of tracks in the playlist
DEFAULT_TARGET_TRACK_COUNT=16000

# Default playlist name
DEFAULT_PLAYLIST_NAME="random_playlist"

# Temporary files for storing track lists
TRACK_LIST=$(mktemp)
FILTERED_TRACK_LIST=$(mktemp)
ADDITIONAL_TRACK_LIST=$(mktemp)

# Function to install required packages if not already installed
install_package() {
    sudo apt install -y "$1"
}

# Function to check and install required tools
install_required_tools() {
    for cmd in mpc awk shuf; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "$cmd is required but not installed. Installing..."
            install_package "$cmd"
        fi
    done

    # Check for optional tools and install them if not installed
    for cmd in rg parallel; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "$cmd is not installed. Installing..."
            install_package "$cmd"
        fi
    done
}

# Install the required tools
install_required_tools

# Parse command-line arguments using getopts
while getopts "c:p:" opt; do
    case $opt in
        c) TARGET_TRACK_COUNT="$OPTARG" ;;
        p) PLAYLIST_NAME="$OPTARG" ;;
        *) echo "Usage: $0 [-c track_count] [-p playlist_name]" ;;
    esac
done

# Set defaults if arguments are not provided
TARGET_TRACK_COUNT=${TARGET_TRACK_COUNT:-$DEFAULT_TARGET_TRACK_COUNT}
PLAYLIST_NAME=${PLAYLIST_NAME:-$DEFAULT_PLAYLIST_NAME}
FALLBACK_MODE=false

# Check for --fallback argument
if [[ "$1" == "--fallback" ]]; then
    FALLBACK_MODE=true
    echo "Fallback mode enabled: Using grep and shuf instead of ripgrep and parallel."
fi

# Clear the current MPC queue
mpc clear

# Fetch all available tracks in the music directory
find "$MUSIC_DIR" -type f -iname "*.mp3" > "$TRACK_LIST"

# Count the number of tracks per artist, and limit how many from each artist can be included.
awk -F"/" '{artists[$1]++} END {for (a in artists) print a, (artists[a] < 50 ? 5 : int(artists[a] * 0.10))}' "$TRACK_LIST" > artist_limits.txt

declare -A artist_counts  # To keep track of how many tracks have been added per artist

# Create a filtered track list using the artist limit
while IFS= read -r line; do
    artist=$(echo "$line" | cut -d ' ' -f 1)
    limit=$(echo "$line" | cut -d ' ' -f 2)

    # Ensure limit is numeric to avoid errors
    if [[ "$limit" =~ ^[0-9]+$ ]]; then
        # Escape special characters or spaces in artist name
        artist_escaped=$(echo "$artist" | sed 's/[]\/$*.^[]/\\&/g')

        # Use ripgrep or grep to filter tracks, and shuffle results
        if [ "$USE_RIPGREP" = true ]; then
            rg "^$artist_escaped/" "$TRACK_LIST" | shuf -n "$limit" >> "$FILTERED_TRACK_LIST"
        else
            grep "^$artist_escaped/" "$TRACK_LIST" | shuf -n "$limit" >> "$FILTERED_TRACK_LIST"
        fi
    fi
done < artist_limits.txt

# Shuffle and limit the track count to the desired target
TRACK_COUNT=$(wc -l < "$FILTERED_TRACK_LIST")

# If the filtered list contains fewer than TARGET_TRACK_COUNT, fill with random tracks
if [ "$TRACK_COUNT" -lt "$TARGET_TRACK_COUNT" ]; then
    ADDITIONAL_COUNT=$((TARGET_TRACK_COUNT - TRACK_COUNT))
    #Comment out Debug Statement: echo "Filling up with $ADDITIONAL_COUNT additional random tracks."

    # Create a list of additional tracks that excludes already added tracks
    grep -F -v -f "$FILTERED_TRACK_LIST" "$TRACK_LIST" > "$ADDITIONAL_TRACK_LIST"

    # Shuffle additional tracks and select the required number
    if [ "$USE_PARALLEL" = true ]; then
        parallel --pipe shuf -n "$ADDITIONAL_COUNT" < "$ADDITIONAL_TRACK_LIST" >> "$FILTERED_TRACK_LIST"
    else
        shuf "$ADDITIONAL_TRACK_LIST" | head -n "$ADDITIONAL_COUNT" >> "$FILTERED_TRACK_LIST"
    fi
fi

# Remove playlist if it already exists (using mpc)
mpc lsplaylists | grep -q "^$PLAYLIST_NAME$" && mpc rm "$PLAYLIST_NAME"

# Save the new playlist by writing the tracks to the playlist directory
# Remove the base music directory path from the track file paths
sed "s|^$MUSIC_DIR||" "$FILTERED_TRACK_LIST" > "$PLAYLIST_DIR$PLAYLIST_NAME.m3u"

# Add the tracks to MPC
mpc load "$PLAYLIST_NAME"

# Clean up temporary files
rm "$TRACK_LIST" "$FILTERED_TRACK_LIST" "$ADDITIONAL_TRACK_LIST" artist_limits.txt

    #Comment out Debug Statement: echo "Random playlist of $TARGET_TRACK_COUNT tracks created and saved as '$PLAYLIST_NAME'."

