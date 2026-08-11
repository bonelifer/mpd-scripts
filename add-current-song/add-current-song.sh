#!/usr/bin/bash

#
# Script: Add Current MPD Song to M3U
#
# Purpose:
#   Adds the currently playing MPD song to an M3U playlist.
#
# Features:
#   - Creates the playlist if it does not exist.
#   - Optionally creates the parent directory.
#   - Prevents duplicate entries by default.
#   - Optionally allows duplicate entries.
#   - Optionally removes existing duplicate entries.
#   - Optionally sorts the playlist alphabetically.
#   - Optionally removes blank lines.
#   - Normalizes Windows CRLF line endings.
#   - Configurable MPD output format.
#   - Optional verbose output.
#   - Validates the playlist extension.
#   - Checks playlist and directory permissions.
#   - Detects MPD communication failures and reports diagnostics.
#   - Rejects unexpected multiline MPD output.
#   - Rejects extended M3U files rather than corrupting them.
#   - Uses a lock to prevent concurrent modifications.
#   - Configurable lock timeout.
#   - Uses atomic replacement when rewriting the playlist.
#   - Cleans up temporary files when interrupted.
#   - Uses consistent C locale sorting.
#   - Provides a --help option.
#
# Usage:
#   add-current-song.sh /path/to/playlist.m3u
#   add-current-song.sh --help
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Settings live in
# ~/.config/mpd-scripts/add-current-song/add-current-song.conf, seeded from
# the add-current-song.conf.example template shipped alongside this script
# on first run. Edit the copy there, not the template.
CONFIG_DIR="$HOME/.config/mpd-scripts/add-current-song"
CONFIG_FILE="$CONFIG_DIR/add-current-song.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$CONFIG_DIR"
    cp "$(dirname "$0")/add-current-song.conf.example" "$CONFIG_FILE"
fi

# shellcheck source=add-current-song.conf.example
source "$CONFIG_FILE"

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

#
# Display the script usage information.
#
show_help() {
    cat <<'EOF'
Usage:
  add-current-song.sh PLAYLIST
  add-current-song.sh --help
  add-current-song.sh -h

Description:
  Adds the currently playing MPD song to an M3U playlist.

The playlist is created automatically when necessary, subject to the
CREATE_DIRECTORY configuration setting.

Configuration:
  Settings live in
  ~/.config/mpd-scripts/add-current-song/add-current-song.conf, seeded from
  add-current-song.conf.example on first run.

  SORT_PLAYLIST
      Sort the playlist alphabetically.
      true  = enabled
      false = preserve addition order

  CREATE_DIRECTORY
      Create the playlist's parent directory when necessary.
      true  = enabled
      false = fail if the directory does not exist

  ALLOW_DUPLICATES
      Allow the current song to be added when it already exists.
      true  = allow duplicates
      false = prevent duplicates

  REMOVE_EXISTING_DUPLICATES
      Remove duplicate entries already present in the playlist.
      true  = enabled
      false = preserve existing duplicates

  REMOVE_BLANK_LINES
      Remove blank or whitespace-only lines when rewriting.
      true  = enabled
      false = preserve blank lines

  NORMALIZE_CRLF
      Convert CRLF line endings to Unix LF line endings.
      true  = enabled
      false = preserve existing line endings

  MPD_FORMAT
      Format string passed to mpc.
      Default: %file%
      Docs: https://www.musicpd.org/doc/mpc/html/

  VERBOSE
      Display informational messages.
      true  = enabled
      false = errors only

  REQUIRE_M3U_EXTENSION
      Require the playlist filename to end in .m3u or .m3u8.
      true  = enabled
      false = allow any filename

  LOCK_TIMEOUT
      Number of seconds to wait for another process to release the lock.
      0 = fail immediately
EOF
}

#
# Print an informational message when verbose output is enabled.
#
log_message() {
    if [[ "$VERBOSE" == true ]]; then
        printf '%s\n' "$*"
    fi
}

#
# Print an error message and exit.
#
error_exit() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

#
# Validate a boolean configuration value.
#
validate_boolean() {
    local variable_name="$1"
    local variable_value="$2"

    if [[ "$variable_value" != true &&
        "$variable_value" != false ]]; then
        error_exit "$variable_name must be true or false."
    fi
}

#
# Clean up temporary files created during playlist processing.
#
# The lock file is deliberately NOT removed.
#
# Why:
#   flock locks the file descriptor/inode rather than the filename itself.
#   Removing the lock file while another process is using it can allow a
#   second process to create a new lock file with the same pathname. The two
#   processes could then hold different inodes and both modify the playlist.
#
# Leaving the zero-length .lock file in place is safe. The kernel releases
# the actual lock automatically when file descriptor 9 is closed.
#
cleanup() {
    if [[ -n "${TEMP_FILE:-}" ]]; then
        rm -f -- "$TEMP_FILE"
        TEMP_FILE=""
    fi

    if [[ -n "${SORT_TEMP_FILE:-}" ]]; then
        rm -f -- "$SORT_TEMP_FILE"
        SORT_TEMP_FILE=""
    fi

    if [[ -n "${MPD_ERROR_FILE:-}" ]]; then
        rm -f -- "$MPD_ERROR_FILE"
        MPD_ERROR_FILE=""
    fi
}

#
# Handle termination signals safely.
#
handle_signal() {
    printf 'Error: Operation interrupted.\n' >&2
    exit 130
}

#
# Create a temporary file in the same directory as the playlist.
#
# Keeping the temporary file in the same filesystem allows the final mv
# operation to be atomic.
#
create_temp_file() {
    local directory="$1"

    mktemp "$directory/.playlist.XXXXXX"
}

#
# Rewrite a playlist through a temporary file.
#
# This allows normalization and optional blank-line removal without
# modifying the original playlist until the complete replacement is ready.
#
rewrite_playlist() {
    local source_file="$1"
    local destination_file="$2"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Normalize CRLF line endings.
        if [[ "$NORMALIZE_CRLF" == true ]]; then
            line="${line%$'\r'}"
        fi

        # Remove blank or whitespace-only lines when requested.
        if [[ "$REMOVE_BLANK_LINES" == true &&
            -z "${line//[[:space:]]/}" ]]; then
            continue
        fi

        printf '%s\n' "$line"
    done < "$source_file" > "$destination_file"

    # Verify that the destination was created successfully.
    #
    # We do not require it to be non-empty here because an empty playlist
    # can be legitimate. The caller verifies that the song being added is
    # present before replacing the original playlist.
    if [[ ! -f "$destination_file" ]]; then
        error_exit "Failed to create rewritten playlist."
    fi
}

#
# Set the destination file permissions or exit on failure.
#
set_permissions_or_exit() {
    local file_mode="$1"
    local destination_file="$2"

    if ! chmod "$file_mode" "$destination_file"; then
        error_exit "Unable to set playlist permissions."
    fi
}

#
# Preserve the permissions of the original playlist.
#
# GNU/Linux and BSD/macOS use different stat syntax, so detect the available
# form rather than assuming one implementation.
#
preserve_permissions() {
    local source_file="$1"
    local destination_file="$2"
    local file_mode

    if file_mode="$(stat -c '%a' -- "$source_file" 2>/dev/null)"; then
        set_permissions_or_exit "$file_mode" "$destination_file"
        return
    fi

    if file_mode="$(stat -f '%Lp' -- "$source_file" 2>/dev/null)"; then
        set_permissions_or_exit "$file_mode" "$destination_file"
        return
    fi

    error_exit "Unable to determine playlist permissions."
}

#
# Detect extended M3U directives.
#
# Returns success if the playlist contains #EXTM3U or #EXTINF.
#
is_extended_m3u() {
    local playlist_file="$1"

    grep -qE '^[[:space:]]*#(EXTM3U|EXTINF):?' "$playlist_file"
}

# ---------------------------------------------------------------------------
# Handle command-line options
# ---------------------------------------------------------------------------

case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
esac

# ---------------------------------------------------------------------------
# Validate configuration
# ---------------------------------------------------------------------------

validate_boolean "SORT_PLAYLIST" "$SORT_PLAYLIST"
validate_boolean "CREATE_DIRECTORY" "$CREATE_DIRECTORY"
validate_boolean "ALLOW_DUPLICATES" "$ALLOW_DUPLICATES"
validate_boolean "REMOVE_EXISTING_DUPLICATES" \
    "$REMOVE_EXISTING_DUPLICATES"
validate_boolean "REMOVE_BLANK_LINES" "$REMOVE_BLANK_LINES"
validate_boolean "NORMALIZE_CRLF" "$NORMALIZE_CRLF"
validate_boolean "VERBOSE" "$VERBOSE"
validate_boolean "REQUIRE_M3U_EXTENSION" "$REQUIRE_M3U_EXTENSION"

if ! [[ "$LOCK_TIMEOUT" =~ ^[0-9]+$ ]]; then
    error_exit "LOCK_TIMEOUT must be a non-negative integer."
fi

# MPD format output must remain a single line. Newline characters in the
# format could cause the current-song result to become multiple lines.
#
# We do not prohibit % format specifiers because they are how mpc obtains
# information such as %file%, %artist%, and %title%.
if [[ "$MPD_FORMAT" == *$'\n'* ||
    "$MPD_FORMAT" == *$'\r'* ]]; then
    error_exit "MPD_FORMAT must not contain newline characters."
fi

# ---------------------------------------------------------------------------
# Signal handling
# ---------------------------------------------------------------------------

TEMP_FILE=""
SORT_TEMP_FILE=""
MPD_ERROR_FILE=""

trap cleanup EXIT
trap handle_signal INT TERM HUP

# ---------------------------------------------------------------------------
# Validate command-line arguments
# ---------------------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    printf 'Usage: %s /path/to/playlist.m3u\n' "$0" >&2
    printf 'Use "%s --help" for more information.\n' "$0" >&2
    exit 2
fi

PLAYLIST="$1"

# ---------------------------------------------------------------------------
# Validate playlist filename
# ---------------------------------------------------------------------------

if [[ "$REQUIRE_M3U_EXTENSION" == true &&
    ! "$PLAYLIST" =~ \.(m3u|m3u8)$ ]]; then
    error_exit "Playlist must have a .m3u or .m3u8 extension: $PLAYLIST"
fi

# ---------------------------------------------------------------------------
# Determine playlist path
# ---------------------------------------------------------------------------

# Convert a relative playlist path to an absolute path.
if [[ "$PLAYLIST" != /* ]]; then
    PLAYLIST="$PWD/$PLAYLIST"
fi

PLAYLIST_DIRECTORY="$(dirname -- "$PLAYLIST")"

# ---------------------------------------------------------------------------
# Validate existing playlist path
# ---------------------------------------------------------------------------

# Reject symbolic links, including dangling symbolic links.
if [[ -L "$PLAYLIST" ]]; then
    error_exit "Refusing to operate on a symbolic link: $PLAYLIST"
fi

# Reject existing paths that are not regular files.
if [[ -e "$PLAYLIST" && ! -f "$PLAYLIST" ]]; then
    error_exit "Playlist path is not a regular file: $PLAYLIST"
fi

# ---------------------------------------------------------------------------
# Create parent directory if necessary
# ---------------------------------------------------------------------------

if [[ ! -d "$PLAYLIST_DIRECTORY" ]]; then
    if [[ "$CREATE_DIRECTORY" == true ]]; then
        if ! mkdir -p -- "$PLAYLIST_DIRECTORY"; then
            error_exit \
                "Unable to create playlist directory: $PLAYLIST_DIRECTORY"
        fi

        log_message "Created directory: $PLAYLIST_DIRECTORY"
    else
        error_exit \
            "Playlist directory does not exist: $PLAYLIST_DIRECTORY"
    fi
fi

# Verify that the playlist directory is writable.
if [[ ! -w "$PLAYLIST_DIRECTORY" ]]; then
    error_exit \
        "Playlist directory is not writable: $PLAYLIST_DIRECTORY"
fi

# ---------------------------------------------------------------------------
# Verify required commands
# ---------------------------------------------------------------------------

for command_name in \
    awk \
    chmod \
    flock \
    grep \
    mktemp \
    mpc \
    mv \
    sort \
    stat; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        error_exit "Required command not found: $command_name"
    fi
done

# ---------------------------------------------------------------------------
# Lock the playlist
# ---------------------------------------------------------------------------

# Include the complete playlist path in the lock filename.
#
# Why:
#   A generic lock name could cause unrelated playlists to share a lock.
#   Using the exact playlist path as the base ensures each playlist has its
#   own lock file.
#
LOCK_FILE="${PLAYLIST}.lock"

if ! exec 9>"$LOCK_FILE"; then
    error_exit "Unable to create lock file: $LOCK_FILE"
fi

if (( LOCK_TIMEOUT == 0 )); then
    if ! flock -n 9; then
        error_exit "Playlist is already being modified: $PLAYLIST"
    fi
elif ! flock -w "$LOCK_TIMEOUT" 9; then
    error_exit "Timed out waiting for playlist lock: $PLAYLIST"
fi

# ---------------------------------------------------------------------------
# Create the playlist if necessary
# ---------------------------------------------------------------------------

if [[ ! -e "$PLAYLIST" ]]; then
    if ! touch -- "$PLAYLIST"; then
        error_exit "Unable to create playlist: $PLAYLIST"
    fi

    log_message "Created playlist: $PLAYLIST"
fi

# Verify that the playlist is writable.
if [[ ! -w "$PLAYLIST" ]]; then
    error_exit "Playlist is not writable: $PLAYLIST"
fi

# ---------------------------------------------------------------------------
# Detect extended M3U format
# ---------------------------------------------------------------------------

if [[ -s "$PLAYLIST" ]] && is_extended_m3u "$PLAYLIST"; then
    # Extended M3U is deliberately rejected.
    #
    # Why:
    #   #EXTINF metadata belongs to the media path that follows it.
    #   The sorting and duplicate-removal logic in this script operates on
    #   individual lines. Processing an extended M3U as a normal path-only
    #   playlist could separate metadata from its song and corrupt the file.
    #
    # Proper support would require treating each metadata/media pair as one
    # record throughout sorting, duplicate removal, and rewriting.
    error_exit "Extended M3U detected. This script only supports path-only M3U playlists to avoid separating #EXTINF metadata from its song."
fi

# ---------------------------------------------------------------------------
# Get the currently playing MPD song
# ---------------------------------------------------------------------------

MPD_ERROR_FILE="$(mktemp)"

if ! SONG="$(mpc -f "$MPD_FORMAT" current 2>"$MPD_ERROR_FILE")"; then
    MPD_ERROR="$(cat "$MPD_ERROR_FILE")"
    rm -f -- "$MPD_ERROR_FILE"
    MPD_ERROR_FILE=""

    if [[ -n "$MPD_ERROR" ]]; then
        error_exit "Unable to communicate with MPD: $MPD_ERROR"
    fi

    error_exit "Unable to communicate with MPD."
fi

rm -f -- "$MPD_ERROR_FILE"
MPD_ERROR_FILE=""

# Make sure MPD returned a song.
if [[ -z "$SONG" ]]; then
    error_exit "No song is currently playing."
fi

# Reject unexpected multiline output.
if [[ "$SONG" == *$'\n'* ]]; then
    error_exit "MPD returned unexpected multiline song data."
fi

# Normalize a carriage return if MPD happens to return one.
if [[ "$NORMALIZE_CRLF" == true ]]; then
    SONG="${SONG%$'\r'}"
fi

# Make sure the resulting song value is still non-empty.
if [[ -z "$SONG" ]]; then
    error_exit "MPD returned an empty song path."
fi

# ---------------------------------------------------------------------------
# Check for an existing entry
# ---------------------------------------------------------------------------

SONG_ALREADY_PRESENT=false

if grep -qxF -- "$SONG" "$PLAYLIST"; then
    SONG_ALREADY_PRESENT=true

    if [[ "$ALLOW_DUPLICATES" == false ]]; then
        log_message "Song already exists; not adding duplicate:"
        log_message "$SONG"
    fi
fi

# ---------------------------------------------------------------------------
# Add the song
# ---------------------------------------------------------------------------

if [[ "$SONG_ALREADY_PRESENT" == false ||
    "$ALLOW_DUPLICATES" == true ]]; then

    if ! printf '%s\n' "$SONG" >> "$PLAYLIST"; then
        error_exit "Unable to add song to playlist."
    fi

    SONG_ADDED=true
else
    SONG_ADDED=false
fi

# ---------------------------------------------------------------------------
# Determine whether the playlist needs rewriting
# ---------------------------------------------------------------------------

REWRITE_PLAYLIST=false

if [[ "$SORT_PLAYLIST" == true ||
    "$REMOVE_EXISTING_DUPLICATES" == true ||
    "$REMOVE_BLANK_LINES" == true ||
    "$NORMALIZE_CRLF" == true ]]; then
    REWRITE_PLAYLIST=true
fi

# ---------------------------------------------------------------------------
# Avoid unnecessary work
# ---------------------------------------------------------------------------

# If the song was already present and no rewrite operation was requested,
# there is nothing else to do.
if [[ "$SONG_ADDED" == false &&
    "$REWRITE_PLAYLIST" == false ]]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Rewrite playlist when required
# ---------------------------------------------------------------------------

if [[ "$REWRITE_PLAYLIST" == true ]]; then
    TEMP_FILE="$(create_temp_file "$PLAYLIST_DIRECTORY")"

    # Start with normalization and optional blank-line removal.
    rewrite_playlist "$PLAYLIST" "$TEMP_FILE"

    # Remove duplicate entries when requested.
    if [[ "$REMOVE_EXISTING_DUPLICATES" == true ]]; then
        SORT_TEMP_FILE="$(create_temp_file "$PLAYLIST_DIRECTORY")"

        if [[ "$SORT_PLAYLIST" == true ]]; then
            LC_ALL=C sort -u "$TEMP_FILE" > "$SORT_TEMP_FILE"
        else
            awk '!seen[$0]++' "$TEMP_FILE" > "$SORT_TEMP_FILE"
        fi

        rm -f -- "$TEMP_FILE"
        TEMP_FILE="$SORT_TEMP_FILE"
        SORT_TEMP_FILE=""
    elif [[ "$SORT_PLAYLIST" == true ]]; then
        SORT_TEMP_FILE="$(create_temp_file "$PLAYLIST_DIRECTORY")"

        if [[ "$ALLOW_DUPLICATES" == true ]]; then
            LC_ALL=C sort "$TEMP_FILE" > "$SORT_TEMP_FILE"
        else
            LC_ALL=C sort -u "$TEMP_FILE" > "$SORT_TEMP_FILE"
        fi

        rm -f -- "$TEMP_FILE"
        TEMP_FILE="$SORT_TEMP_FILE"
        SORT_TEMP_FILE=""
    fi

    # Verify that the song exists in the rewritten playlist.
    #
    # We intentionally check for presence rather than requiring exactly one
    # occurrence. Existing duplicate entries may legitimately remain when
    # REMOVE_EXISTING_DUPLICATES=false.
    #
    # When REMOVE_EXISTING_DUPLICATES=true, sort -u or awk removes duplicates
    # before this verification.
    if ! grep -qxF -- "$SONG" "$TEMP_FILE"; then
        error_exit "Rewritten playlist does not contain the current song."
    fi

    # Preserve the existing playlist permissions.
    preserve_permissions "$PLAYLIST" "$TEMP_FILE"

    # Atomically replace the original playlist.
    if ! mv -- "$TEMP_FILE" "$PLAYLIST"; then
        error_exit "Unable to replace playlist."
    fi

    # The temporary file has been moved successfully.
    TEMP_FILE=""
fi

# ---------------------------------------------------------------------------
# Finished
# ---------------------------------------------------------------------------

if [[ "$SONG_ADDED" == true ]]; then
    log_message "Added:"
    log_message "$SONG"
else
    log_message "Playlist already contained the current song."
fi

if [[ "$REWRITE_PLAYLIST" == true ]]; then
    if [[ "$REMOVE_EXISTING_DUPLICATES" == true ]]; then
        log_message "Removed existing duplicate entries."
    fi

    if [[ "$SORT_PLAYLIST" == true ]]; then
        log_message "Playlist sorted alphabetically."
    fi
fi

log_message "Playlist: $PLAYLIST"
