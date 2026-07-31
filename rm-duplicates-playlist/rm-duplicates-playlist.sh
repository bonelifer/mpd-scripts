#!/usr/bin/bash
# Script Name: rm-duplicates-playlist.sh
# Description: Removes duplicate entries from a playlist or the current MPD queue.
#              Supports playlist mode (-p), queue mode (-q), and listing playlists (-l).
#              Duplicates are detected by exact path match (case-insensitive).
# Usage: ./rm-duplicates-playlist.sh [-v] (-p <playlist_name> | -q | -l)
#   -v, --verbose    Enable verbose output
#   -p, --playlist   Specify the playlist to process
#   -q, --queue      Process the current MPD queue
#   -l, --list       List all available playlists
#   -h, --help       Show usage and exit
#
# Configuration:
#   PLAYLIST_DIR lives in ~/.config/rm-duplicates-playlist/rm-duplicates-playlist.conf,
#   seeded from rm-duplicates-playlist.conf.example (shipped alongside this
#   script) on first run.
# Version: 1.0

set -e

# Temporary playlist name for queue mode (without .m3u extension)
TEMP_PLAYLIST="currentqueue"

# Flags for script behavior
VERBOSE=false
QUEUE_MODE=false
LIST_MODE=false
PLAYLIST_NAME=""

# Print a short error plus a pointer to --help, then exit 1. Used for
# argument-validation errors (missing/conflicting flags) rather than -h.
usage() {
    echo "$1" >&2
    echo "Try '$(basename "$0") --help' for usage." >&2
    exit 1
}

display_help() {
    cat <<HELP
Usage: $(basename "$0") [-v] (-p <playlist_name> | -q | -l)

Removes duplicate entries (matched by file path, case-insensitively) from
a saved MPD playlist or the current queue.

Options:
  -p, --playlist NAME  Remove duplicates from the named playlist.
  -q, --queue          Remove duplicates from the current MPD queue.
  -l, --list           List all available MPD playlists and exit.
  -v, --verbose        Enable verbose output.
  -h, --help           Show this help message.

Exactly one of -p, -q, or -l must be given.
HELP
    exit 0
}

# Function to clean up temporary files
cleanup() {
    if [[ -f "${PLAYLIST_DIR}/${TEMP_PLAYLIST}.m3u" ]]; then
        [[ "$VERBOSE" == true ]] && echo "Cleaning up temporary playlist: ${PLAYLIST_DIR}/${TEMP_PLAYLIST}.m3u"
        rm -f "${PLAYLIST_DIR}/${TEMP_PLAYLIST}.m3u"
    fi
    if [[ -f "${PLAYLIST_DIR}/${TEMP_PLAYLIST}.m3u.bak" ]]; then
        [[ "$VERBOSE" == true ]] && echo "Cleaning up temporary backup: ${PLAYLIST_DIR}/${TEMP_PLAYLIST}.m3u.bak"
        rm -f "${PLAYLIST_DIR}/${TEMP_PLAYLIST}.m3u.bak"
    fi
    # Remove the playlist from MPD's database if it exists
    if mpc lsplaylists | grep -Fxq "$TEMP_PLAYLIST"; then
        [[ "$VERBOSE" == true ]] && echo "Removing temporary playlist from MPD database: $TEMP_PLAYLIST"
        mpc rm "$TEMP_PLAYLIST" > /dev/null
    fi
}

# Trap to ensure cleanup runs on script exit
trap cleanup EXIT

# Parse command-line options (both short and long forms)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=true; shift ;;
        -q|--queue)   QUEUE_MODE=true; shift ;;
        -l|--list)    LIST_MODE=true; shift ;;
        -p|--playlist)
            if [[ $# -lt 2 ]]; then
                usage "Error: -p/--playlist requires an argument."
            fi
            PLAYLIST_NAME="$2"
            shift 2
            ;;
        -h|--help) display_help ;;
        *)
            echo "Unknown option: $1" >&2
            display_help
            ;;
    esac
done

# Ensure only one of -p, -q, or -l is specified
if [[ "$LIST_MODE" == true && ("$QUEUE_MODE" == true || -n "$PLAYLIST_NAME") ]]; then
    usage "Error: Cannot use -l with -p or -q."
fi

if [[ "$QUEUE_MODE" == true && -n "$PLAYLIST_NAME" ]]; then
    usage "Error: Cannot use -q and -p together."
fi

if [[ "$QUEUE_MODE" == false && "$LIST_MODE" == false && -z "$PLAYLIST_NAME" ]]; then
    usage "Error: Either -p, -q, or -l must be specified."
fi

# List mode: Display all available playlists and exit. Doesn't touch
# PLAYLIST_DIR, so it works even before the config file has been set up.
if [[ "$LIST_MODE" == true ]]; then
    echo "Available playlists:"
    mpc lsplaylists
    exit 0
fi

# Config lives in ~/.config/rm-duplicates-playlist/rm-duplicates-playlist.conf,
# seeded from the rm-duplicates-playlist.conf.example template shipped
# alongside this script on first run. Only -p/-q need it.
CONFIG_DIR="$HOME/.config/rm-duplicates-playlist"
CONFIG_FILE="$CONFIG_DIR/rm-duplicates-playlist.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$CONFIG_DIR"
    cp "$(dirname "$0")/rm-duplicates-playlist.conf.example" "$CONFIG_FILE"
    echo "Created $CONFIG_FILE -- edit it with your playlist directory, then run this again." >&2
    exit 1
fi

# shellcheck source=rm-duplicates-playlist.conf.example
source "$CONFIG_FILE"

if [[ "$PLAYLIST_DIR" == "/path/to/your/mpd/playlists" ]]; then
    echo "Error: $CONFIG_FILE still has a placeholder PLAYLIST_DIR value. Edit it first." >&2
    exit 1
fi

# Queue mode: Save the current queue to a temporary playlist
if [[ "$QUEUE_MODE" == true ]]; then
    # Delete the temporary playlist if it already exists
    if mpc lsplaylists | grep -Fxq "$TEMP_PLAYLIST"; then
        [[ "$VERBOSE" == true ]] && echo "Deleting existing temporary playlist: $TEMP_PLAYLIST"
        mpc rm "$TEMP_PLAYLIST" > /dev/null
    fi

    [[ "$VERBOSE" == true ]] && echo "Saving current MPD queue to $TEMP_PLAYLIST..."
    mpc save "$TEMP_PLAYLIST" > /dev/null  # mpc appends .m3u automatically
    PLAYLIST_NAME="$TEMP_PLAYLIST"
fi

# Full path to the playlist file
PLAYLIST_PATH="${PLAYLIST_DIR}/${PLAYLIST_NAME}.m3u"

# Validate that the playlist file exists
if [[ ! -f "$PLAYLIST_PATH" ]]; then
    echo "Error: Playlist '$PLAYLIST_NAME' not found!" >&2
    exit 1
fi

ORIGINAL_COUNT=$(wc -l < "$PLAYLIST_PATH")

# Use awk-based seen-tracking to detect duplicates preserving order
DEDUPED=$(awk '!seen[tolower($0)]++' "$PLAYLIST_PATH")

# $DEDUPED being empty means zero entries, not one blank line -- `wc -l`
# on an empty string via `echo`/here-string would otherwise report 1.
if [[ -z "$DEDUPED" ]]; then
    DEDUPED_COUNT=0
else
    DEDUPED_COUNT=$(wc -l <<< "$DEDUPED")
fi

if [[ "$ORIGINAL_COUNT" -eq "$DEDUPED_COUNT" ]]; then
    echo "No duplicate entries found in the playlist. No changes made."

    if [[ "$QUEUE_MODE" == true ]]; then
        echo "Skipping queue processing to prevent clearing MPD queue."
    fi

    exit 0
fi

# Backup the playlist before making changes
cp "$PLAYLIST_PATH" "${PLAYLIST_PATH}.bak"

# Verbose output: Display original playlist info
if [[ "$VERBOSE" == true ]]; then
    echo "Processing playlist: $PLAYLIST_NAME"
    echo "Original playlist has $ORIGINAL_COUNT entries."
fi

# Write deduplicated entries back to the playlist file
echo "$DEDUPED" > "$PLAYLIST_PATH"

# Verbose output: Report removed duplicates
if [[ "$VERBOSE" == true ]]; then
    REMOVED_COUNT=$(( ORIGINAL_COUNT - DEDUPED_COUNT ))
    echo "Removed $REMOVED_COUNT duplicate(s)."
    echo "Updated playlist has $DEDUPED_COUNT entries."
fi

# Queue mode: Reload the MPD queue with the deduplicated playlist
if [[ "$QUEUE_MODE" == true ]]; then
    [[ "$VERBOSE" == true ]] && echo "Clearing current MPD queue..."
    mpc clear > /dev/null

    [[ "$VERBOSE" == true ]] && echo "Loading deduplicated playlist into MPD queue..."
    mpc load "$TEMP_PLAYLIST" > /dev/null

    [[ "$VERBOSE" == true ]] && echo "Starting playback..."
    mpc play > /dev/null
fi

# Final confirmation message
echo "Processing complete. Updated playlist saved as '$PLAYLIST_NAME'."
