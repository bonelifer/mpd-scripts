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
# - Checks if the playlist already exists in MPC and deletes it before creating a new one.
#
# Configuration:
# MUSIC_DIR, PLAYLIST_DIR, and the defaults below live in
# ~/.config/mpd-queue-shuffle/mpd-queue-shuffle.conf, seeded from
# mpd-queue-shuffle.conf.example on first run.
#
# Usage:
# - You can specify a custom track count and playlist name with the `-c` and `-p` options respectively.
# - If not specified, the script defaults to the track count/playlist name from the config file.
# - Pass --fallback (or -f) to use grep/shuf instead of ripgrep/parallel even if they're installed.
# - Pass -y/--yes to install any missing required tools without prompting first.

set -e  # Exit on error

# Config lives in ~/.config/mpd-queue-shuffle/mpd-queue-shuffle.conf, seeded
# from the mpd-queue-shuffle.conf.example template shipped alongside this
# script on first run.
CONFIG_DIR="$HOME/.config/mpd-queue-shuffle"
CONFIG_FILE="$CONFIG_DIR/mpd-queue-shuffle.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    mkdir -p "$CONFIG_DIR"
    cp "$(dirname "$0")/mpd-queue-shuffle.conf.example" "$CONFIG_FILE"
    echo "Created $CONFIG_FILE -- edit it with your music/playlist directories, then run this again."
    exit 1
fi

# shellcheck source=mpd-queue-shuffle.conf.example
source "$CONFIG_FILE"

if [[ "$MUSIC_DIR" == "/path/to/your/music/directory/" || "$PLAYLIST_DIR" == "/path/to/your/mpc/playlists/directory/" ]]; then
    echo "Error: $CONFIG_FILE still has placeholder MUSIC_DIR/PLAYLIST_DIR values. Edit it first."
    exit 1
fi

# Ensure MUSIC_DIR has a trailing slash, so stripping it from found paths
# below always leaves a clean relative path (needed for correct per-artist
# grouping -- see TRACK_LIST below).
[[ "$MUSIC_DIR" == */ ]] || MUSIC_DIR="$MUSIC_DIR/"

# Parse command-line arguments. --fallback/-f and -y/--yes are handled
# separately first since getopts doesn't support long options, then
# whatever's left goes through getopts for -c/-p.
FALLBACK_MODE=false
ASSUME_YES=false
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --fallback) FALLBACK_MODE=true ;;
        --yes) ASSUME_YES=true ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]}"

while getopts "c:p:fy" opt; do
    case $opt in
        c) TARGET_TRACK_COUNT="$OPTARG" ;;
        p) PLAYLIST_NAME="$OPTARG" ;;
        f) FALLBACK_MODE=true ;;
        y) ASSUME_YES=true ;;
        *) echo "Usage: $0 [-c track_count] [-p playlist_name] [-f|--fallback] [-y|--yes]"; exit 1 ;;
    esac
done

# Set defaults if arguments are not provided
TARGET_TRACK_COUNT=${TARGET_TRACK_COUNT:-$DEFAULT_TARGET_TRACK_COUNT}
PLAYLIST_NAME=${PLAYLIST_NAME:-$DEFAULT_PLAYLIST_NAME}

if [ "$FALLBACK_MODE" = true ]; then
    echo "Fallback mode enabled: Using grep and shuf instead of ripgrep and parallel."
fi

# Checks for required tools (mpc, awk, shuf), and ripgrep/parallel unless
# --fallback was given (no point installing them if they won't be used).
# Prompts before installing anything unless -y/--yes was given.
check_required_tools() {
    local required=(mpc awk shuf)
    local optional=()
    if [ "$FALLBACK_MODE" != true ]; then
        optional+=(rg parallel)
    fi

    local missing=()
    for cmd in "${required[@]}" "${optional[@]}"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        return
    fi

    echo "Missing tools: ${missing[*]}"
    if [ "$ASSUME_YES" != true ]; then
        read -r -p "Install them now with apt (requires sudo)? [y/N] " reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            echo "Cannot continue without these tools."
            exit 1
        fi
    fi

    for cmd in "${missing[@]}"; do
        # apt's package name differs from the binary name for ripgrep.
        local pkg="$cmd"
        [ "$cmd" = "rg" ] && pkg="ripgrep"
        sudo apt install -y "$pkg"
    done
}

check_required_tools

# Use ripgrep/parallel only if they're actually available and --fallback
# wasn't requested.
USE_RIPGREP=false
USE_PARALLEL=false
if [ "$FALLBACK_MODE" != true ]; then
    command -v rg &>/dev/null && USE_RIPGREP=true
    command -v parallel &>/dev/null && USE_PARALLEL=true
fi

# Bail out early with a clear error if MPD/mpc isn't reachable, rather than
# doing all the scanning below and only failing at the final `mpc load`.
if ! mpc status &>/dev/null; then
    echo "Error: cannot reach MPD via mpc. Is it running and configured correctly?"
    exit 1
fi

# Temporary files for storing track lists
TRACK_LIST=$(mktemp)
FILTERED_TRACK_LIST=$(mktemp)
ADDITIONAL_TRACK_LIST=$(mktemp)
ARTIST_LIMITS=$(mktemp)
trap 'rm -f "$TRACK_LIST" "$FILTERED_TRACK_LIST" "$ADDITIONAL_TRACK_LIST" "$ARTIST_LIMITS"' EXIT

# Clear the current MPC queue
mpc clear

# Fetch all available tracks in the music directory, stored relative to
# MUSIC_DIR (e.g. "ArtistName/Album/track.mp3") so the artist-grouping
# below (and the final playlist paths) are correct.
find "$MUSIC_DIR" -type f -iname "*.mp3" | sed "s|^$MUSIC_DIR||" > "$TRACK_LIST"

# Count the number of tracks per artist, and limit how many from each artist can be included.
awk -F"/" '{artists[$1]++} END {for (a in artists) print a, (artists[a] < 50 ? 5 : int(artists[a] * 0.10))}' "$TRACK_LIST" > "$ARTIST_LIMITS"

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
done < "$ARTIST_LIMITS"

# Shuffle and limit the track count to the desired target
TRACK_COUNT=$(wc -l < "$FILTERED_TRACK_LIST")

# If the filtered list contains fewer than TARGET_TRACK_COUNT, fill with random tracks
if [ "$TRACK_COUNT" -lt "$TARGET_TRACK_COUNT" ]; then
    ADDITIONAL_COUNT=$((TARGET_TRACK_COUNT - TRACK_COUNT))

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

# Save the new playlist by writing the (already MUSIC_DIR-relative) tracks
# to the playlist directory.
cp "$FILTERED_TRACK_LIST" "$PLAYLIST_DIR$PLAYLIST_NAME.m3u"

# Add the tracks to MPC
if mpc load "$PLAYLIST_NAME"; then
    echo "Random playlist of $TARGET_TRACK_COUNT tracks created and saved as '$PLAYLIST_NAME'."
else
    echo "Error: 'mpc load $PLAYLIST_NAME' failed; the .m3u file was written but MPD didn't load it." >&2
    exit 1
fi
