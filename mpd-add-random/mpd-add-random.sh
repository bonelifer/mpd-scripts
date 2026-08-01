#!/usr/bin/bash
#
# mpd-add-random.sh
#
# Adds a random selection of tracks from the local music library to the
# current MPD queue, using paths relative to MUSIC_DIR (as required by mpc).
#
# Usage:
#   ./mpd-add-random.sh [-t NUMBER]
#
# Options:
#   -t, --tracks NUMBER  Number of random tracks to add (default: 10).
#
# Configuration:
#   MUSIC_DIR lives in ~/.config/mpd-scripts/mpd-add-random/mpd-add-random.conf,
#   seeded from mpd-add-random.conf.example (shipped alongside this script)
#   on first run.
#
# Examples:
#   ./mpd-add-random.sh -t 5    # Adds 5 random tracks to the queue
#   ./mpd-add-random.sh         # Defaults to 10 random tracks

set -euo pipefail

# Number of tracks to add. Defaults to 10 if not provided.
NUM_TRACKS=10

display_help() {
    cat <<HELP
Usage: $(basename "$0") [-t NUMBER]

Adds a random selection of tracks from the local music library (MUSIC_DIR,
see mpd-add-random.conf) to the current MPD queue.

Options:
  -t, --tracks NUMBER  Number of random tracks to add (default: 10).
  -h, --help           Show this help message.
HELP
    exit 0
}

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
        -h|--help) display_help ;;
        *)
            echo "Unknown option: $1" >&2
            display_help
            ;;
    esac
done

# Validate that NUM_TRACKS is a positive integer
if ! [[ "$NUM_TRACKS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: -t/--tracks must be a positive integer, got '$NUM_TRACKS'." >&2
    exit 1
fi

# Confirm required tools are available
for cmd in mpc find shuf; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: required command '$cmd' not found in PATH." >&2
        exit 1
    fi
done

# Config lives in ~/.config/mpd-scripts/mpd-add-random/mpd-add-random.conf,
# seeded from the mpd-add-random.conf.example template shipped alongside
# this script on first run.
CONFIG_DIR="$HOME/.config/mpd-scripts/mpd-add-random"
CONFIG_FILE="$CONFIG_DIR/mpd-add-random.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$CONFIG_DIR"
    cp "$(dirname "$0")/mpd-add-random.conf.example" "$CONFIG_FILE"
    echo "Created $CONFIG_FILE -- edit it with your music directory, then run this again." >&2
    exit 1
fi

# shellcheck source=mpd-add-random.conf.example
source "$CONFIG_FILE"

if [[ "$MUSIC_DIR" == "/path/to/your/music/directory" ]]; then
    echo "Error: $CONFIG_FILE still has a placeholder MUSIC_DIR value. Edit it first." >&2
    exit 1
fi

# Confirm the music directory exists
if [[ ! -d "$MUSIC_DIR" ]]; then
    echo "Error: music directory '$MUSIC_DIR' does not exist. Check MUSIC_DIR in $CONFIG_FILE." >&2
    exit 1
fi

# Build a NUL-delimited array of all audio files, safe for filenames
# containing spaces, newlines, or other unusual characters. -L follows
# symlinks, so symlinked audio files (and directories of them) are included
# rather than silently skipped.
TRACKS=()
while IFS= read -r -d '' track; do
    TRACKS+=("$track")
done < <(find -L "$MUSIC_DIR" -type f \
    \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \
       -o -iname "*.opus" -o -iname "*.wav" -o -iname "*.wma" -o -iname "*.aac" \) \
    -print0)

TOTAL_TRACKS="${#TRACKS[@]}"

if [[ "$TOTAL_TRACKS" -eq 0 ]]; then
    echo "Error: no audio files found under '$MUSIC_DIR'." >&2
    exit 1
fi

if [[ "$NUM_TRACKS" -gt "$TOTAL_TRACKS" ]]; then
    echo "There are only $TOTAL_TRACKS tracks available. Adding all available tracks."
    NUM_TRACKS="$TOTAL_TRACKS"
fi

# Randomly select NUM_TRACKS tracks (NUL-delimited to preserve odd filenames)
# and queue each one with a path relative to MUSIC_DIR, as mpc expects. A
# plain prefix strip is used rather than `realpath`, which would resolve a
# symlinked subdirectory to its physical target -- MPD's own database
# indexes such tracks under the symlink's name (as found by `find -L`
# above), not its target, so resolving it here would build a path outside
# MUSIC_DIR that MPD wouldn't recognize. A failed individual add is a
# warning, not a reason to abort the whole run -- one bad path shouldn't
# stop the rest from being added.
ADDED_COUNT=0
while IFS= read -r -d '' track; do
    relative_path="${track#"$MUSIC_DIR"/}"
    if mpc add "$relative_path"; then
        (( ADDED_COUNT++ )) || true
    else
        echo "Warning: failed to add '$relative_path' to queue." >&2
    fi
done < <(printf '%s\0' "${TRACKS[@]}" | shuf -z -n "$NUM_TRACKS")

echo "Added $ADDED_COUNT random tracks to the queue."
