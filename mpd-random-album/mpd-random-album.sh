#!/usr/bin/bash
# shellcheck disable=SC2317

#
# Script: mpd-random-album.sh
#
# Note: SC2317 ("unreachable" code) is disabled file-wide above because the
# static analysis doesn't trace functions that are only ever invoked via
# `trap` (restore_queue, handle_error, handle_signal, handle_int,
# handle_term, cleanup) -- it otherwise flags their bodies as unreachable
# even though they're the script's actual error/signal/exit handlers.
#
# Purpose:
#   Clear the current MPD queue and replace it with a randomly selected
#   collection of complete albums, then begin playback.
#
# Behavior:
#   - Selects random unique album/album-artist combinations.
#   - Uses exact album and album-artist matching when resolving albums.
#   - Resolves every selected album before modifying the queue.
#   - Skips albums that disappear from the library between selection and
#     resolution when --force is given; aborts the run otherwise.
#   - Saves the original MPD queue and playback state before modification.
#   - Restores the original queue and state if an error occurs after the
#     queue has been modified.
#   - Verifies the resulting queue before playback.
#   - Returns 0 for complete success, 2 for partial success, 1 for failure,
#     130 for SIGINT, and 143 for SIGTERM.
#
# Usage:
#   mpd-random-album.sh [OPTIONS] [ALBUM_COUNT]
#
# Examples:
#   mpd-random-album.sh
#   mpd-random-album.sh 5
#   mpd-random-album.sh --quiet 3
#   mpd-random-album.sh --dry-run 10
#

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Settings live in
# ~/.config/mpd-scripts/mpd-random-album/mpd-random-album.conf, seeded from
# the mpd-random-album.conf.example template shipped alongside this script
# on first run. Edit the copy there, not the template.
CONFIG_DIR="$HOME/.config/mpd-scripts/mpd-random-album"
CONFIG_FILE="$CONFIG_DIR/mpd-random-album.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$CONFIG_DIR"
    cp "$(dirname "$0")/mpd-random-album.conf.example" "$CONFIG_FILE"
fi

# shellcheck source=mpd-random-album.conf.example
source "$CONFIG_FILE"

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

QUEUE_MODIFIED=false
RESTORING_QUEUE=false
HANDLING_ERROR=false

ORIGINAL_RANDOM=""
ORIGINAL_REPEAT=""
ORIGINAL_SINGLE=""
ORIGINAL_CONSUME=""
ORIGINAL_STATE=""
ORIGINAL_SONG_POSITION=""

declare -a ORIGINAL_QUEUE=()
declare -a RANDOM_ALBUMS=()
declare -a RESOLVED_ALBUMS=()
declare -a SELECTED_TRACKS=()

# ---------------------------------------------------------------------------
# Logging and error handling
# ---------------------------------------------------------------------------

log_message() {
    if [[ "$QUIET" != true ]]; then
        printf '%s\n' "$*"
    fi
}

warning_message() {
    printf 'Warning: %s\n' "$*" >&2
}

#
# Restore the original MPD queue and playback state.
#
# Restoration deliberately ignores individual MPD failures. We are already
# recovering from an error, so another restoration failure must not trigger
# recursive ERR handling.
#
restore_queue() {
    local track
    local restore_position=""

    if [[ "$RESTORING_QUEUE" == true ]]; then
        return 0
    fi

    RESTORING_QUEUE=true

    #
    # Disable the ERR trap during restoration. Every MPD command also uses
    # "|| true" so a failed restoration command cannot recursively invoke
    # the error handler.
    #
    trap - ERR

    mpc stop >/dev/null 2>&1 || true
    mpc clear >/dev/null 2>&1 || true

    if [[ ${#ORIGINAL_QUEUE[@]} -gt 0 ]]; then
        for track in "${ORIGINAL_QUEUE[@]}"; do
            mpc add -- "$track" >/dev/null 2>&1 || true
        done
    fi

    # Restore random playback state.
    case "$ORIGINAL_RANDOM" in
        on)
            mpc random on >/dev/null 2>&1 || true
            ;;
        off)
            mpc random off >/dev/null 2>&1 || true
            ;;
    esac

    # Restore repeat state.
    case "$ORIGINAL_REPEAT" in
        on)
            mpc repeat on >/dev/null 2>&1 || true
            ;;
        off)
            mpc repeat off >/dev/null 2>&1 || true
            ;;
    esac

    # "single" and "consume" support "once" in addition to on/off.
    case "$ORIGINAL_SINGLE" in
        on)
            mpc single on >/dev/null 2>&1 || true
            ;;
        off)
            mpc single off >/dev/null 2>&1 || true
            ;;
        once)
            mpc single once >/dev/null 2>&1 || true
            ;;
    esac

    case "$ORIGINAL_CONSUME" in
        on)
            mpc consume on >/dev/null 2>&1 || true
            ;;
        off)
            mpc consume off >/dev/null 2>&1 || true
            ;;
        once)
            mpc consume once >/dev/null 2>&1 || true
            ;;
    esac

    if [[ ${#ORIGINAL_QUEUE[@]} -eq 0 ]]; then
        #
        # The original queue was empty, so leaving MPD stopped with an empty
        # queue is the correct restored state.
        #
        mpc stop >/dev/null 2>&1 || true
    elif [[ -n "$ORIGINAL_SONG_POSITION" ]]; then
        restore_position="$ORIGINAL_SONG_POSITION"

        case "$ORIGINAL_STATE" in
            playing)
                mpc play "$restore_position" >/dev/null 2>&1 || true
                ;;
            paused)
                mpc play "$restore_position" >/dev/null 2>&1 || true
                mpc pause >/dev/null 2>&1 || true
                ;;
            stopped)
                mpc stop >/dev/null 2>&1 || true
                ;;
        esac
    fi

    QUEUE_MODIFIED=false
    RESTORING_QUEUE=false

    trap handle_error ERR
}

#
# Print an error message and restore the original MPD state if necessary.
#
# IMPORTANT:
# Explicit exit calls do not trigger the ERR trap. Therefore restoration
# must happen here rather than relying exclusively on handle_error().
#
# The ERR trap remains as a second line of defense for unhandled failures.
#
error_exit() {
    local message="$*"

    if [[ "$QUEUE_MODIFIED" == true &&
          "$RESTORING_QUEUE" != true &&
          "$HANDLING_ERROR" != true ]]; then
        HANDLING_ERROR=true
        restore_queue || true
        HANDLING_ERROR=false
    fi

    printf 'Error: %s\n' "$message" >&2
    exit 1
}

#
# Handle unhandled command failures.
#
handle_error() {
    local exit_code=$?

    if [[ "$HANDLING_ERROR" == true ]]; then
        return "$exit_code"
    fi

    HANDLING_ERROR=true

    if [[ "$QUEUE_MODIFIED" == true &&
          "$RESTORING_QUEUE" != true ]]; then
        restore_queue || true
    fi

    printf 'Error: An unexpected error occurred.\n' >&2

    HANDLING_ERROR=false

    return "$exit_code"
}

# ---------------------------------------------------------------------------
# Signal handling
# ---------------------------------------------------------------------------

handle_signal() {
    local signal="$1"
    local exit_code

    case "$signal" in
        INT)
            exit_code=130
            ;;
        TERM)
            exit_code=143
            ;;
        *)
            exit_code=1
            ;;
    esac

    if [[ "$QUEUE_MODIFIED" == true &&
          "$RESTORING_QUEUE" != true ]]; then
        log_message "Interrupted; restoring the original MPD queue..."
        restore_queue || true
    fi

    exit "$exit_code"
}

handle_int() {
    handle_signal INT
}

handle_term() {
    handle_signal TERM
}

trap handle_error ERR
trap handle_int INT
trap handle_term TERM

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

cleanup() {
    #
    # Album selection uses process substitution rather than a persistent
    # temporary file, so there is currently nothing to remove here.
    #
    :
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Dependency checking
# ---------------------------------------------------------------------------

check_dependencies() {
    local command_name

    # Keep dependencies alphabetically ordered.
    for command_name in awk mpc shuf; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            error_exit "Required command not found: $command_name"
        fi
    done
}

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------

show_help() {
    cat <<'EOF'
Usage:
  mpd-random-album.sh [OPTIONS] [ALBUM_COUNT]

Description:
  Replace the current MPD queue with randomly selected complete albums.

Options:
  -d, --dry-run    Select and resolve albums without changing the queue.
  -f, --force      Skip albums that fail to resolve instead of aborting.
  -h, --help       Show this help message.
  -q, --quiet      Suppress informational messages.

Arguments:
  ALBUM_COUNT      Number of albums to select. Defaults to 1.

Exit codes:
  0   All requested albums were added successfully.
  1   General failure.
  2   Some albums could not be added (only possible with --force).
  130 Interrupted with SIGINT.
  143 Terminated with SIGTERM.
EOF
}

parse_arguments() {
    local album_count_set=false

    ALBUM_COUNT="$DEFAULT_ALBUM_COUNT"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                error_exit "Unknown option: $1"
                ;;
            *)
                if [[ "$album_count_set" == true ]]; then
                    error_exit "Too many arguments."
                fi

                ALBUM_COUNT="$1"
                album_count_set=true
                shift
                ;;
        esac
    done

    if [[ $# -gt 0 ]]; then
        error_exit "Unexpected argument: $1"
    fi

    if ! [[ "$ALBUM_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        error_exit "Album count must be a positive integer."
    fi
}

# ---------------------------------------------------------------------------
# MPD state handling
# ---------------------------------------------------------------------------

save_mpd_state() {
    local status_line
    local queue_output

    if ! status_line="$(
        mpc status \
            --format='%random%\t%repeat%\t%single%\t%consume%\t%state%\t%songpos%'
    )"; then
        error_exit "Unable to read MPD status."
    fi

    if [[ -z "$status_line" ]]; then
        error_exit "MPD returned an empty status."
    fi

    IFS=$'\t' read -r \
        ORIGINAL_RANDOM \
        ORIGINAL_REPEAT \
        ORIGINAL_SINGLE \
        ORIGINAL_CONSUME \
        ORIGINAL_STATE \
        ORIGINAL_SONG_POSITION <<< "$status_line"

    if [[ -n "$ORIGINAL_SONG_POSITION" &&
          "$ORIGINAL_SONG_POSITION" != "-" ]]; then

        if ! [[ "$ORIGINAL_SONG_POSITION" =~ ^[0-9]+$ ]]; then
            error_exit \
                "Unexpected MPD song position: $ORIGINAL_SONG_POSITION"
        fi

        #
        # %songpos% is zero-based, while "mpc play POSITION" is one-based.
        # Convert it here so restoration can use the stored value directly.
        #
        ORIGINAL_SONG_POSITION=$((ORIGINAL_SONG_POSITION + 1))
    else
        ORIGINAL_SONG_POSITION=""
    fi

    if ! queue_output="$(mpc playlist)"; then
        error_exit "Unable to save the current MPD queue."
    fi

    ORIGINAL_QUEUE=()

    if [[ -n "$queue_output" ]]; then
        mapfile -t ORIGINAL_QUEUE <<< "$queue_output"
    fi
}

# ---------------------------------------------------------------------------
# Queue verification
# ---------------------------------------------------------------------------

verify_queue() {
    local queue_output
    local count
    local -a queue_lines=()

    #
    # Do not use %length% here.
    #
    # %length% represents duration, not the number of tracks in the queue.
    # Counting mpc playlist output gives the actual number of queued songs.
    #
    if ! queue_output="$(mpc playlist)"; then
        error_exit "Unable to read MPD queue; MPD may be unavailable."
    fi

    count=0

    if [[ -n "$queue_output" ]]; then
        mapfile -t queue_lines <<< "$queue_output"
        count=${#queue_lines[@]}
    fi

    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        error_exit "Unexpected queue count: $count"
    fi

    printf '%s' "$count"
}

# ---------------------------------------------------------------------------
# Album record validation
# ---------------------------------------------------------------------------

count_tabs() {
    local value="$1"
    local original_length
    local stripped_length

    original_length=${#value}

    # Remove all tabs using Bash parameter expansion.
    value="${value//$'\t'/}"

    stripped_length=${#value}

    printf '%s' "$((original_length - stripped_length))"
}

validate_album_record() {
    local album_record="$1"
    local tab_count

    tab_count="$(count_tabs "$album_record")"

    if (( tab_count != 1 )); then
        error_exit \
            "Malformed album record (expected exactly one tab): $album_record"
    fi
}

# ---------------------------------------------------------------------------
# Album selection
# ---------------------------------------------------------------------------

select_random_albums() {
    local album_count="$1"
    local album_record

    RANDOM_ALBUMS=()

    mapfile -t RANDOM_ALBUMS < <(
        mpc listall --format='%albumartist%\t%album%' |
            awk -F '\t' '
                NF == 2 &&
                $1 != "" &&
                $2 != "" {
                    print $1 "\t" $2
                }
            ' |
            sort -u |
            shuf -n "$album_count"
    )

    if [[ ${#RANDOM_ALBUMS[@]} -eq 0 ]]; then
        error_exit "No valid albums were found in the MPD library."
    fi

    for album_record in "${RANDOM_ALBUMS[@]}"; do
        validate_album_record "$album_record"
    done
}

# ---------------------------------------------------------------------------
# Album resolution
# ---------------------------------------------------------------------------

resolve_albums() {
    local album_record
    local album_artist
    local album
    local track
    local album_track_count
    local -a album_tracks

    RESOLVED_ALBUMS=()
    SELECTED_TRACKS=()

    for album_record in "${RANDOM_ALBUMS[@]}"; do
        album_artist="${album_record%%$'\t'*}"
        album="${album_record#*$'\t'}"

        #
        # Use mpc find rather than mpc search because the selected album and
        # album artist must match exactly.
        #
        # mpc search can produce unintended matches when metadata contains
        # similar names, such as:
        #
        #   The Wall
        #   The Wall (Remastered)
        #
        # The exact metadata pair selected above should resolve to exactly
        # that album rather than to substring/partial matches.
        #
        mapfile -t album_tracks < <(
            mpc find album "$album" albumartist "$album_artist"
        )

        album_track_count=0

        if [[ ${#album_tracks[@]} -eq 0 ]]; then
            if [[ "$FORCE" != true ]]; then
                error_exit \
                    "No tracks found for: $album_artist - $album (use --force to skip albums that fail to resolve instead of aborting)"
            fi

            warning_message "No tracks found for: $album_artist - $album"
            continue
        fi

        for track in "${album_tracks[@]}"; do
            if [[ -n "$track" ]]; then
                SELECTED_TRACKS+=("$track")

                #
                # Safe with set -e: the result is 1, 2, 3... rather than 0.
                #
                ((album_track_count += 1))
            fi
        done

        if (( album_track_count == 0 )); then
            if [[ "$FORCE" != true ]]; then
                error_exit \
                    "Album contains no valid tracks: $album_artist - $album (use --force to skip albums that fail to resolve instead of aborting)"
            fi

            warning_message "Album contains no valid tracks: $album_artist - $album"
            continue
        fi

        RESOLVED_ALBUMS+=("$album_record")

        log_message \
            "Resolved: $album_artist - $album ($album_track_count track(s))"
    done

    if [[ ${#RESOLVED_ALBUMS[@]} -eq 0 ]]; then
        error_exit "None of the selected albums could be resolved."
    fi

    if [[ ${#SELECTED_TRACKS[@]} -eq 0 ]]; then
        error_exit "No tracks were resolved from the selected albums."
    fi
}

# ---------------------------------------------------------------------------
# Queue modification
# ---------------------------------------------------------------------------

clear_and_fill_queue() {
    local track

    if ! mpc clear >/dev/null; then
        error_exit "Unable to clear the MPD queue."
    fi

    QUEUE_MODIFIED=true

    #
    # Random playback is disabled while constructing the queue.
    # The original random state is restored after the queue is verified.
    #
    if ! mpc random off >/dev/null; then
        error_exit "Unable to disable MPD random playback."
    fi

    for track in "${SELECTED_TRACKS[@]}"; do
        if ! mpc add -- "$track" >/dev/null; then
            error_exit "Unable to add track to MPD queue: $track"
        fi
    done
}

# ---------------------------------------------------------------------------
# Final validation and playback
# ---------------------------------------------------------------------------

start_playback() {
    local queue_length

    queue_length="$(verify_queue)"

    if (( queue_length != ${#SELECTED_TRACKS[@]} )); then
        error_exit \
            "Queue verification failed: expected ${#SELECTED_TRACKS[@]} track(s), found $queue_length."
    fi

    #
    # Report albums added, not tracks. Each album may contain multiple tracks.
    #
    log_message \
        "Added ${#RESOLVED_ALBUMS[@]} random album(s) containing $queue_length track(s)."

    if ! mpc play >/dev/null; then
        error_exit "Unable to start MPD playback."
    fi

    #
    # Restore the original random setting only after the new queue has been
    # successfully built and playback has started.
    #
    case "$ORIGINAL_RANDOM" in
        on)
            if ! mpc random on >/dev/null; then
                error_exit "Unable to restore MPD random playback state."
            fi
            ;;
        off)
            if ! mpc random off >/dev/null; then
                error_exit "Unable to restore MPD random playback state."
            fi
            ;;
    esac

    QUEUE_MODIFIED=false
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local requested_album_count
    local resolved_album_count

    check_dependencies
    parse_arguments "$@"

    requested_album_count="$ALBUM_COUNT"

    save_mpd_state

    # Resolve everything before changing the user's existing queue.
    select_random_albums "$requested_album_count"
    resolve_albums

    resolved_album_count="${#RESOLVED_ALBUMS[@]}"

    if [[ "$DRY_RUN" == true ]]; then
        log_message \
            "Dry run: $resolved_album_count album(s) resolved; MPD queue was not changed."

        return 0
    fi

    clear_and_fill_queue
    start_playback

    if (( resolved_album_count < requested_album_count )); then
        warning_message \
            "Only $resolved_album_count of $requested_album_count requested album(s) were added."

        return 2
    fi

    log_message "Playback started successfully."

    return 0
}

#
# main is invoked via "|| exit_code=$?" rather than as a bare command.
#
# Why:
#   set -e/-E treat ANY non-zero return from a top-level command as a
#   failure that trips the ERR trap -- including main's own deliberate
#   "return 2" for partial success. A bare "main "$@"" would print the
#   generic "An unexpected error occurred." message even on a successful,
#   documented partial-success run. Making main's invocation part of a "||"
#   list exempts it from that (per bash's set -e rules: a command
#   immediately followed by "||" doesn't trigger errexit/ERR on failure),
#   so only genuinely unhandled errors inside main still reach the trap.
#
exit_code=0
main "$@" || exit_code=$?
exit "$exit_code"
