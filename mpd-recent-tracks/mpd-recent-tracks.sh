#!/usr/bin/bash
# Script Name: mpd-recent-tracks.sh
# Description: Generates an M3U playlist (newest first) of music files added
#              or modified in the last N days, with paths relative to
#              MUSIC_DIR so MPD can resolve them.
# Usage: ./mpd-recent-tracks.sh [-d <days>] [-n <limit> | -r <count>] [-q] [-l [-p]]
#   -d, --days    Number of days to look back (default: DEFAULT_DAYS_OLD from config)
#   -n, --limit   Cap the playlist at this many songs (newest first)
#   -r, --random  Pick this many songs at random from the recent-tracks pool
#   -q, --quiet   Suppress informational output; only errors are printed
#   -l, --load    Load the generated playlist into MPD via `mpc load` (left paused)
#   -p, --play    With -l/--load, also start playback via `mpc play`
#   -h, --help    Show usage and exit
#
# Configuration:
#   PLAYLIST_DIR, MUSIC_DIR, PLAYLIST_TITLE, DEFAULT_DAYS_OLD, EXTENSIONS,
#   and EXCLUDE_FILE live in
#   ~/.config/mpd-scripts/mpd-recent-tracks/mpd-recent-tracks.conf, seeded
#   from mpd-recent-tracks.conf.example (shipped alongside this script) on
#   first run. EXCLUDE_FILE (default exclude_paths.txt, seeded from
#   exclude_paths.txt.example) lists glob patterns to skip.

set -euo pipefail

DAYS_OLD=""
LIMIT=""
RANDOM_COUNT=""
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
Usage: $(basename "$0") [-d <days>] [-n <limit> | -r <count>] [-q] [-l [-p]]

Generates an M3U playlist (newest first) of music files added or modified
in the last <days> days (default: DEFAULT_DAYS_OLD from config).

Options:
  -d, --days N    Number of days to look back.
  -n, --limit N   Cap the playlist at this many songs (newest first).
  -r, --random N  Pick N songs at random from the recent-tracks pool,
                  instead of the newest N. Cannot be combined with -n/--limit.
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
        -r|--random)
            if [[ $# -lt 2 ]]; then
                usage "Error: -r/--random requires an argument."
            fi
            RANDOM_COUNT="$2"
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

if [[ -n "$RANDOM_COUNT" ]] && ! [[ "$RANDOM_COUNT" =~ ^[0-9]+$ ]]; then
    usage "Error: -r/--random must be a non-negative integer, got '$RANDOM_COUNT'."
fi

if [[ -n "$LIMIT" && -n "$RANDOM_COUNT" ]]; then
    usage "Error: -n/--limit and -r/--random cannot be used together."
fi

if [[ -n "$RANDOM_COUNT" ]] && ! command -v shuf &> /dev/null; then
    echo "Error: -r/--random requires the shuf command, which was not found." >&2
    exit 1
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

SCRIPT_DIR="$(dirname "$0")"

if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$CONFIG_DIR"
    cp "$SCRIPT_DIR/mpd-recent-tracks.conf.example" "$CONFIG_FILE"
    echo "Created $CONFIG_FILE -- edit it with your playlist/music directories, then run this again." >&2
    exit 1
fi

# shellcheck source=mpd-recent-tracks.conf.example
source "$CONFIG_FILE"

if [[ "$PLAYLIST_DIR" == "/path/to/mpd/playlists" || "$MUSIC_DIR" == "/path/to/Music" ]]; then
    echo "Error: $CONFIG_FILE still has placeholder PLAYLIST_DIR/MUSIC_DIR values. Edit it first." >&2
    exit 1
fi

if [[ -z "${EXTENSIONS// }" ]]; then
    echo "Error: $CONFIG_FILE has an empty EXTENSIONS list." >&2
    exit 1
fi

# Seed the exclude-patterns file alongside the main config on first run.
EXCLUDE_PATH="$CONFIG_DIR/${EXCLUDE_FILE:-exclude_paths.txt}"
if [[ ! -f "$EXCLUDE_PATH" ]]; then
    cp "$SCRIPT_DIR/exclude_paths.txt.example" "$EXCLUDE_PATH"
fi

EXCLUDE_PATTERNS=()
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    EXCLUDE_PATTERNS+=("$line")
done < "$EXCLUDE_PATH"

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
# Write to temp files first so a failed/interrupted run never touches an
# existing good playlist; only replace it once we know the run succeeded.
# SIZE_TMP holds the -n/--limit or -r/--random result before it replaces
# TMP_FILE's full candidate list.
TMP_FILE="$(mktemp "${PLAYLIST_FILE}.XXXXXX")"
SIZE_TMP="$(mktemp "${PLAYLIST_FILE}.XXXXXX")"
trap 'rm -f "$TMP_FILE" "$SIZE_TMP"' EXIT

# Build the `-iname "*.ext" -o -iname "*.ext" ...` clause from EXTENSIONS
# so the matched formats are configurable instead of hardcoded.
read -ra EXT_LIST <<< "$EXTENSIONS"
FIND_NAME_ARGS=()
for ext in "${EXT_LIST[@]}"; do
    [[ ${#FIND_NAME_ARGS[@]} -gt 0 ]] && FIND_NAME_ARGS+=(-o)
    FIND_NAME_ARGS+=(-iname "*.${ext}")
done

# Strip the MUSIC_DIR prefix (and any leading slash) from each match so
# paths in the playlist are relative to MPD's music_directory. Using bash
# parameter expansion (quoted, so it's a literal prefix match rather than a
# glob/regex) avoids having to escape MUSIC_DIR against regex metacharacters
# like "." or "(" that commonly show up in real directory names.
#
# `-printf '%T@ %p\0'` prefixes each match with its mtime (epoch seconds) so
# `sort -z -rn -k1,1` can order the NUL-delimited records newest first
# without breaking on paths that contain spaces or newlines. TMP_FILE gets
# every matching candidate; -n/--limit or -r/--random is applied afterwards
# as a separate pass over the full list (see below).
if ! find -L "$MUSIC_DIR" -type f -mtime "-${DAYS_OLD}" \( "${FIND_NAME_ARGS[@]}" \) -printf '%T@ %p\0' |
    sort -z -rn -k1,1 |
    while IFS=' ' read -r -d '' _mtime file; do
        relative="${file#"$MUSIC_DIR"}"
        relative="${relative#/}"

        excluded=false
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            if [[ "$relative" == $pattern ]]; then
                excluded=true
                break
            fi
        done
        [[ "$excluded" == true ]] && continue

        printf '%s\n' "$relative"
    done > "$TMP_FILE"; then
    echo "Error: Failed to create playlist. Possible permission issue." >&2
    exit 1
fi

# Apply -r/--random (a random sample of the pool) or -n/--limit (the
# newest N, which TMP_FILE is already sorted as) against the full
# candidate list gathered above.
if [[ -n "$RANDOM_COUNT" ]]; then
    shuf -n "$RANDOM_COUNT" "$TMP_FILE" > "$SIZE_TMP"
    mv "$SIZE_TMP" "$TMP_FILE"
elif [[ -n "$LIMIT" ]]; then
    head -n "$LIMIT" "$TMP_FILE" > "$SIZE_TMP"
    mv "$SIZE_TMP" "$TMP_FILE"
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
