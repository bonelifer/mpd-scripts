#!/usr/bin/bash
# Script Name: mpd-recent-tracks.sh
# Description: Generates an M3U playlist (newest first) of music files added
#              or modified in the last N days, with paths relative to
#              MUSIC_DIR so MPD can resolve them.
# Usage: ./mpd-recent-tracks.sh [-d <days>] [-n <limit>] [-q] [-l [-p]]
#   -d, --days    Number of days to look back (default: DEFAULT_DAYS_OLD from config)
#   -n, --limit   Cap the playlist at this many songs (newest first)
#   -q, --quiet   Suppress informational output; only errors are printed
#   -l, --load    Load the generated playlist into MPD via `mpc load` (left paused)
#   -p, --play    With -l/--load, also start playback via `mpc play`
#   -h, --help    Show usage and exit
#
# Configuration:
#   PLAYLIST_DIR, MUSIC_DIR, PLAYLIST_TITLE, and DEFAULT_DAYS_OLD live in
#   ~/.config/mpd-scripts/mpd-recent-tracks/mpd-recent-tracks.conf, seeded
#   from mpd-recent-tracks.conf.example (shipped alongside this script) on
#   first run.

set -euo pipefail

DAYS_OLD=""
LIMIT=""
QUIET=false
LOAD=false
PLAY=false

# Print a short error plus a pointer to --help, then exit 1.
usage() {
    echo "$1" >&2
    echo "Try '$(basename "$0") --help' for usage." >&2
    exit 1
}

display_help() {
    cat <<HELP
Usage: $(basename "$0") [-d <days>] [-n <limit>] [-q] [-l [-p]]

Generates an M3U playlist (newest first) of music files added or modified
in the last <days> days (default: DEFAULT_DAYS_OLD from config).

Options:
  -d, --days N    Number of days to look back.
  -n, --limit N   Cap the playlist at this many songs (newest first).
  -q, --quiet     Suppress informational output; only errors are printed.
  -l, --load      Load the generated playlist into MPD via 'mpc load'.
                  Playback is left paused unless -p/--play is also given.
  -p, --play      With -l/--load, start playback via 'mpc play' after loading.
  -h, --help      Show this help message.
HELP
    exit 0
}

# Parse command-line options (both short and long forms)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--days)
            if [[ $# -lt 2 ]]; then
                usage "Error: -d/--days requires an argument."
            fi
            DAYS_OLD="$2"
            shift 2
            ;;
        -n|--limit)
            if [[ $# -lt 2 ]]; then
                usage "Error: -n/--limit requires an argument."
            fi
            LIMIT="$2"
            shift 2
            ;;
        -q|--quiet) QUIET=true; shift ;;
        -l|--load) LOAD=true; shift ;;
        -p|--play) PLAY=true; shift ;;
        -h|--help) display_help ;;
        *)
            echo "Unknown option: $1" >&2
            display_help
            ;;
    esac
done

if [[ -n "$LIMIT" ]] && ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
    usage "Error: -n/--limit must be a non-negative integer, got '$LIMIT'."
fi

if [[ "$PLAY" == true && "$LOAD" == false ]]; then
    usage "Error: -p/--play requires -l/--load."
fi

if [[ "$LOAD" == true ]] && ! command -v mpc &> /dev/null; then
    echo "Error: -l/--load requires the mpc command, which was not found." >&2
    exit 1
fi

# Config lives in
# ~/.config/mpd-scripts/mpd-recent-tracks/mpd-recent-tracks.conf, seeded
# from the mpd-recent-tracks.conf.example template shipped alongside this
# script on first run.
CONFIG_DIR="$HOME/.config/mpd-scripts/mpd-recent-tracks"
CONFIG_FILE="$CONFIG_DIR/mpd-recent-tracks.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$CONFIG_DIR"
    cp "$(dirname "$0")/mpd-recent-tracks.conf.example" "$CONFIG_FILE"
    echo "Created $CONFIG_FILE -- edit it with your playlist/music directories, then run this again." >&2
    exit 1
fi

# shellcheck source=mpd-recent-tracks.conf.example
source "$CONFIG_FILE"

if [[ "$PLAYLIST_DIR" == "/path/to/mpd/playlists" || "$MUSIC_DIR" == "/path/to/Music" ]]; then
    echo "Error: $CONFIG_FILE still has placeholder PLAYLIST_DIR/MUSIC_DIR values. Edit it first." >&2
    exit 1
fi

# Fall back to the configured default if -d/--days wasn't given
DAYS_OLD="${DAYS_OLD:-$DEFAULT_DAYS_OLD}"
if ! [[ "$DAYS_OLD" =~ ^[0-9]+$ ]]; then
    usage "Error: -d/--days must be a non-negative integer, got '$DAYS_OLD'."
fi

if [[ ! -d "$PLAYLIST_DIR" ]]; then
    echo "Error: Playlist directory $PLAYLIST_DIR does not exist." >&2
    exit 1
fi

if [[ ! -d "$MUSIC_DIR" ]]; then
    echo "Error: Music directory $MUSIC_DIR does not exist." >&2
    exit 1
fi

PLAYLIST_FILE="$PLAYLIST_DIR/${PLAYLIST_TITLE}.m3u"
# Write to a temp file first so a failed/interrupted run never touches an
# existing good playlist; only replace it once we know the run succeeded.
TMP_FILE="$(mktemp "${PLAYLIST_FILE}.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

count=0

# Strip the MUSIC_DIR prefix (and any leading slash) from each match so
# paths in the playlist are relative to MPD's music_directory. Using bash
# parameter expansion (quoted, so it's a literal prefix match rather than a
# glob/regex) avoids having to escape MUSIC_DIR against regex metacharacters
# like "." or "(" that commonly show up in real directory names.
#
# `-printf '%T@ %p\0'` prefixes each match with its mtime (epoch seconds) so
# `sort -z -rn -k1,1` can order the NUL-delimited records newest first
# without breaking on paths that contain spaces or newlines. The loop keeps
# reading every record even past -n/--limit (rather than breaking early) so
# `find`/`sort` upstream never see a broken pipe under `pipefail`.
if ! find -L "$MUSIC_DIR" -type f -mtime "-${DAYS_OLD}" \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.flac" -o -iname "*.ogg" \) -printf '%T@ %p\0' |
    sort -z -rn -k1,1 |
    while IFS=' ' read -r -d '' _mtime file; do
        if [[ -z "$LIMIT" ]] || (( count < LIMIT )); then
            relative="${file#"$MUSIC_DIR"}"
            relative="${relative#/}"
            printf '%s\n' "$relative"
        fi
        count=$((count + 1))
    done > "$TMP_FILE"; then
    echo "Error: Failed to create playlist. Possible permission issue." >&2
    exit 1
fi

# Handle empty results: leave the temp file behind for the trap to clean up,
# and only remove any existing playlist once we know this run genuinely
# found nothing (as opposed to having failed, which is caught above).
if [[ ! -s "$TMP_FILE" ]]; then
    [[ "$QUIET" == true ]] || echo "Warning: No recent files found. Playlist is empty."
    rm -f "$PLAYLIST_FILE"
    exit 0
fi

mv "$TMP_FILE" "$PLAYLIST_FILE"

TOTAL_FILES=$(wc -l < "$PLAYLIST_FILE")
[[ "$QUIET" == true ]] || echo "Created the '$PLAYLIST_TITLE' playlist with $TOTAL_FILES songs at $PLAYLIST_FILE."

if [[ "$LOAD" == true ]]; then
    # `mpc load` only queues the songs; it never starts playback on its own,
    # so the loaded playlist stays paused unless -p/--play says otherwise.
    mpc load "$PLAYLIST_TITLE" > /dev/null
    [[ "$QUIET" == true ]] || echo "Loaded '$PLAYLIST_TITLE' into MPD."
    if [[ "$PLAY" == true ]]; then
        mpc play > /dev/null
        [[ "$QUIET" == true ]] || echo "Started playback."
    fi
fi
