#!/usr/bin/bash
#
# mpd-add-random-artist.sh
#
# Uses mpc to find and add random tracks from a specified artist to the
# MPD queue. By default, matches the artist exactly (via `mpc find`,
# case-sensitive) -- use -l/--loose for a substring, case-insensitive
# match (via `mpc search`) if you're unsure of the exact spelling or
# capitalization, or want to catch variant taggings. Loose matching can
# also pull in unrelated artists whose name merely contains the given
# string (e.g. "Air" loosely matching "Air Supply"), so prefer the exact
# default when you know the artist name precisely.
#
# Usage:
#   ./mpd-add-random-artist.sh [-t NUMBER] [-l] ARTIST_NAME
#
# Options:
#   -t, --tracks NUMBER  Number of random tracks to add (default: 10).
#   -l, --loose          Substring, case-insensitive match (mpc search)
#                        instead of the default exact match (mpc find).
#
# Examples:
#   ./mpd-add-random-artist.sh "The Beatles"          # Adds 10 random Beatles tracks (exact match)
#   ./mpd-add-random-artist.sh -t 5 "Pink Floyd"      # Adds 5 random Pink Floyd tracks
#   ./mpd-add-random-artist.sh -l "floyd"             # Loose match: catches "Pink Floyd" and similar

set -euo pipefail

# Default number of tracks
NUM_TRACKS=10
ARTIST=""
LOOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--tracks)
            if [[ $# -lt 2 ]]; then
                echo "Error: -t/--tracks requires an argument." >&2
                exit 1
            fi
            NUM_TRACKS="$2"
            shift 2
            ;;
        -l|--loose)
            LOOSE=true
            shift
            ;;
        *)
            # Reject a second positional argument instead of silently
            # overwriting the artist name.
            if [[ -n "$ARTIST" ]]; then
                echo "Error: multiple artist names provided ('$ARTIST' and '$1'). Quote the artist name if it contains spaces." >&2
                exit 1
            fi
            ARTIST="$1"
            shift
            ;;
    esac
done

# Check if artist was provided
if [[ -z "$ARTIST" ]]; then
    echo "Error: Artist name must be provided." >&2
    echo "Usage: $0 [-t NUMBER] [-l] ARTIST_NAME" >&2
    exit 1
fi

# Validate that NUM_TRACKS is a positive integer
if ! [[ "$NUM_TRACKS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: -t/--tracks must be a positive integer, got '$NUM_TRACKS'." >&2
    exit 1
fi

# Confirm mpc is available
if ! command -v mpc &>/dev/null; then
    echo "Error: required command 'mpc' not found in PATH." >&2
    exit 1
fi

# Exact match (mpc find) by default; substring, case-insensitive match
# (mpc search) with -l/--loose.
MPC_MATCH_CMD="find"
if [[ "$LOOSE" == true ]]; then
    MPC_MATCH_CMD="search"
fi

# Find all tracks by the artist using mpc
ALL_TRACKS=$(mpc "$MPC_MATCH_CMD" artist "$ARTIST")

# Check if any tracks were found (an empty result still yields one line
# from `echo`, so test the string directly rather than counting lines)
if [[ -z "$ALL_TRACKS" ]]; then
    echo "No tracks found for artist: $ARTIST"
    if [[ "$LOOSE" == false ]]; then
        echo "Exact match found nothing -- try -l/--loose for a substring match if you're unsure of the exact spelling or capitalization."
    fi
    exit 1
fi

# Count total tracks
TOTAL_TRACKS=$(echo "$ALL_TRACKS" | wc -l)

# Adjust number of tracks if requested more than available
if [[ "$NUM_TRACKS" -gt "$TOTAL_TRACKS" ]]; then
    echo "Only $TOTAL_TRACKS tracks available for $ARTIST. Adding all."
    NUM_TRACKS="$TOTAL_TRACKS"
fi

# Add random tracks to queue. A failed individual add is a warning, not a
# reason to abort the whole run -- one bad path shouldn't stop the rest
# from being added.
ADDED_COUNT=0
while IFS= read -r track; do
    if mpc add "$track"; then
        (( ADDED_COUNT++ )) || true
    else
        echo "Warning: failed to add '$track' to queue." >&2
    fi
done < <(printf '%s\n' "$ALL_TRACKS" | shuf -n "$NUM_TRACKS")

# Show results
echo "Added $ADDED_COUNT random tracks by $ARTIST to the queue."
CURRENT_POS=$(mpc status | grep -E '^\[playing\]|^\[paused\]' | awk '{print $2}' | cut -d'/' -f1) || CURRENT_POS="N/A"
TOTAL_QUEUE=$(mpc playlist | wc -l)
echo "Queue position: $CURRENT_POS/$TOTAL_QUEUE"
