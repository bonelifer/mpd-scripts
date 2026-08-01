#!/usr/bin/bash
# Script Name: rm-artists-playlist.sh
# Description: Removes songs from a playlist or the current MPD queue based on a list of artists.
#              Supports playlist mode (-p), queue mode (-q), and listing playlists (-l).
#              Matching is an unanchored, case-insensitive substring match against each
#              playlist entry's full file path (a saved .m3u is just a flat list of paths,
#              with no separate artist/album/title fields) -- use full, specific artist
#              names in ARTIST_FILE, since a short or common name (e.g. "Air") could match
#              unrelated paths that merely contain that substring.
# Usage: ./rm-artists-playlist.sh [-v] (-p <playlist_name> | -q | -l)
#   -v, --verbose    Enable verbose output
#   -p, --playlist   Specify the playlist to process
#   -q, --queue      Process the current MPD queue
#   -l, --list       List all available playlists
#   -h, --help       Show usage and exit
#
# Configuration:
#   PLAYLIST_DIR and ARTIST_FILE live in
#   ~/.config/mpd-scripts/rm-artists-playlist/rm-artists-playlist.conf,
#   seeded from rm-artists-playlist.conf.example (shipped alongside this
#   script) on first run.
# Version: 1.8

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

Removes songs by a list of artists (read from ARTIST_FILE, one per line)
from a saved MPD playlist or the current queue. Matching is an unanchored,
case-insensitive substring match against each entry's full file path -- use
full, specific artist names, since a short or common name could match
unrelated paths that merely contain that substring. Blank lines in
ARTIST_FILE are ignored.

Options:
  -p, --playlist NAME  Remove the listed artists' songs from the named playlist.
  -q, --queue          Remove the listed artists' songs from the current MPD queue.
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
# PLAYLIST_DIR/ARTIST_FILE, so it works even before the config file has
# been set up.
if [[ "$LIST_MODE" == true ]]; then
    echo "Available playlists:"
    mpc lsplaylists
    exit 0
fi

# Config lives in
# ~/.config/mpd-scripts/rm-artists-playlist/rm-artists-playlist.conf,
# seeded from the rm-artists-playlist.conf.example template shipped
# alongside this script on first run. Only -p/-q need it.
CONFIG_DIR="$HOME/.config/mpd-scripts/rm-artists-playlist"
CONFIG_FILE="$CONFIG_DIR/rm-artists-playlist.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$CONFIG_DIR"
    cp "$(dirname "$0")/rm-artists-playlist.conf.example" "$CONFIG_FILE"
    echo "Created $CONFIG_FILE -- edit it with your playlist directory and artist file, then run this again." >&2
    exit 1
fi

# shellcheck source=rm-artists-playlist.conf.example
source "$CONFIG_FILE"

if [[ "$PLAYLIST_DIR" == "/path/to/your/mpd/playlists" ]]; then
    echo "Error: $CONFIG_FILE still has a placeholder PLAYLIST_DIR value. Edit it first." >&2
    exit 1
fi

if [[ "$ARTIST_FILE" == "/path/to/your/artists_to_remove.txt" ]]; then
    echo "Error: $CONFIG_FILE still has a placeholder ARTIST_FILE value. Edit it first." >&2
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

# Validate playlist and artist file
if [[ ! -f "$PLAYLIST_PATH" ]]; then
    echo "Error: Playlist '$PLAYLIST_NAME' not found!" >&2
    exit 1
fi

if [[ ! -f "$ARTIST_FILE" ]]; then
    echo "Error: Artist file '$ARTIST_FILE' not found!" >&2
    exit 1
fi

# Check if the artist removal list is empty before proceeding
if [[ ! -s "$ARTIST_FILE" ]]; then
    echo "Artist removal list is empty. No changes made."

    # If queue mode was enabled, we should not clear the queue accidentally
    if [[ "$QUEUE_MODE" == true ]]; then
        echo "Skipping queue processing to prevent clearing MPD queue."
    fi

    exit 0
fi

# Read artist names and create a grep pattern for matching. Blank lines are
# dropped first -- an empty alternative in the resulting regex (e.g. from
# "Artist One\n\nArtist Two") would otherwise match every line
# unconditionally, silently wiping the *entire* playlist/queue instead of
# just the named artists' songs. Remaining lines are escaped for regex
# matching, then joined into a single alternation pattern.
PATTERN=$(grep -v '^[[:space:]]*$' "$ARTIST_FILE" \
    | sed -E 's/([]\/.^$*+?{}|()])/\\&/g' | tr '\n' '|' | sed 's/|$//')

if [[ -z "$PATTERN" ]]; then
    echo "Artist removal list is empty. No changes made."

    if [[ "$QUEUE_MODE" == true ]]; then
        echo "Skipping queue processing to prevent clearing MPD queue."
    fi

    exit 0
fi

# Check if any songs match the artist removal list
if ! grep -iqE "$PATTERN" "${PLAYLIST_PATH}"; then
    echo "No songs by the specified artists found in the playlist. No changes made."

    # If queue mode was enabled, we should not clear the queue accidentally
    if [[ "$QUEUE_MODE" == true ]]; then
        echo "Skipping queue processing to prevent clearing MPD queue."
    fi

    exit 0
fi

# Backup the playlist before making changes
cp "$PLAYLIST_PATH" "${PLAYLIST_PATH}.bak"

# Verbose output: Display playlist info
if [[ "$VERBOSE" == true ]]; then
    echo "Processing playlist: $PLAYLIST_NAME"
    echo "Original playlist has $(wc -l < "${PLAYLIST_PATH}.bak") songs."
fi

# Remove matching lines (songs by artists in the removal list)
grep -iEv "$PATTERN" "${PLAYLIST_PATH}.bak" > "$PLAYLIST_PATH"

# Verbose output: Display removed songs and updated playlist info
if [[ "$VERBOSE" == true ]]; then
    REMOVED_COUNT=$(($(wc -l < "${PLAYLIST_PATH}.bak") - $(wc -l < "$PLAYLIST_PATH")))
    echo "Removed $REMOVED_COUNT songs."
    echo "Updated playlist has $(wc -l < "$PLAYLIST_PATH") songs."
fi

# Queue mode: Update the MPD queue with the processed playlist
if [[ "$QUEUE_MODE" == true ]]; then
    [[ "$VERBOSE" == true ]] && echo "Clearing current MPD queue..."
    mpc clear > /dev/null  # Clear the current queue

    [[ "$VERBOSE" == true ]] && echo "Loading updated playlist into MPD queue..."
    mpc load "$TEMP_PLAYLIST" > /dev/null  # Load the processed playlist into the queue

    [[ "$VERBOSE" == true ]] && echo "Starting playback..."
    mpc play > /dev/null  # Start playback
fi

# Final confirmation message
echo "Processing complete. Updated playlist saved as '$PLAYLIST_NAME'."
