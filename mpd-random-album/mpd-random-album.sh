#!/usr/bin/bash
# shellcheck disable=SC2317

#
# Script: mpd-random-album.sh
#
# Purpose:
#   Clear the current MPD queue and replace it with a randomly selected
#   collection of complete albums, then begin playback.
#
# Behavior:
#   - Selects random unique album/album-artist combinations.
#   - Uses exact album and album-artist matching when resolving albums (and
#     when excluding recently-picked ones), so two different artists'
#     albums that happen to share a title are never conflated.
#   - Optionally restricts selection to albums with a track dated within a
#     given year or year range, and/or matching a genre (substring, case
#     insensitive).
#   - Optionally avoids re-selecting any of the last N albums picked,
#     remembered across runs in a small cache file.
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
#   mpd-random-album.sh --year 1975 5
#   mpd-random-album.sh --year 1970-1979 5
#   mpd-random-album.sh --genre jazz 3
#   mpd-random-album.sh --allow-repeats 3
#
# Note: SC2317 ("unreachable" code) is disabled file-wide above because the
# static analysis doesn't trace functions that are only ever invoked via
# `trap` (restore_queue, handle_error, handle_signal, handle_int,
# handle_term, cleanup) -- it otherwise flags their bodies as unreachable
# even though they're the script's actual error/signal/exit handlers.
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

# Defaults for settings that may not exist in a config predating them, so
# an old config file (missing AVOID_REPEATS/CACHE_SIZE) doesn't trip set
# -u's "unbound variable" instead of just falling back sensibly.
AVOID_REPEATS=true
CACHE_SIZE=20

# shellcheck source=mpd-random-album.conf.example
source "$CONFIG_FILE"

# Recently-picked albums live here (not under ~/.config, since this is
# regeneratable cache data rather than user configuration or critical
# state) so AVOID_REPEATS can skip them on future runs. One
# "albumartist\talbum" pair per line, oldest first.
CACHE_DIR="$HOME/.cache/mpd-scripts/mpd-random-album"
CACHE_FILE="$CACHE_DIR/recent-albums.tsv"

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
  -A, --allow-repeats  Don't avoid recently-picked albums for this run,
                       even if AVOID_REPEATS is on in the config.
  -d, --dry-run        Select and resolve albums without changing the queue.
  -f, --force          Skip albums that fail to resolve instead of aborting.
  -g, --genre GENRE    Only select albums with a track whose genre
                       contains GENRE (case insensitive).
  -h, --help           Show this help message.
  -q, --quiet          Suppress informational messages.
  -y, --year YEAR      Only select albums with a track dated YEAR, or
                        within a YEAR-YEAR range (e.g. 1970-1979).

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
    YEAR_FILTER=""
    GENRE_FILTER=""
    ALLOW_REPEATS_OVERRIDE=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -A|--allow-repeats)
                # Deliberately does NOT touch AVOID_REPEATS itself -- that
                # stays the persistent config value, so update_cache() still
                # records this run's picks (see there for why: a forced
                # repeat should still count as "just played" for the next,
                # non-overridden run). Only select_random_albums()'s
                # exclusion check consults this override.
                ALLOW_REPEATS_OVERRIDE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -g|--genre)
                if [[ $# -lt 2 ]]; then
                    error_exit "-g/--genre requires an argument."
                fi
                GENRE_FILTER="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -y|--year)
                if [[ $# -lt 2 ]]; then
                    error_exit "-y/--year requires an argument."
                fi
                YEAR_FILTER="$2"
                shift 2
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

    # YEAR_FILTER is either a single 4-digit year or a "START-END" range
    # (inclusive); either form sets YEAR_START/YEAR_END, which
    # select_random_albums() actually filters on. A bare year sets both to
    # the same value, so it's just a range of one.
    YEAR_START=""
    YEAR_END=""
    if [[ -n "$YEAR_FILTER" ]]; then
        if [[ "$YEAR_FILTER" =~ ^([0-9]{4})-([0-9]{4})$ ]]; then
            YEAR_START="${BASH_REMATCH[1]}"
            YEAR_END="${BASH_REMATCH[2]}"
            if (( YEAR_START > YEAR_END )); then
                error_exit "-y/--year range must have start <= end, got '$YEAR_FILTER'."
            fi
        elif [[ "$YEAR_FILTER" =~ ^[0-9]{4}$ ]]; then
            YEAR_START="$YEAR_FILTER"
            YEAR_END="$YEAR_FILTER"
        else
            error_exit "-y/--year must be a 4-digit year or a START-END range, got '$YEAR_FILTER'."
        fi
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
    local -a candidates=()
    local excluded_recent=false

    # %date% is always requested even when YEAR_START/YEAR_END are unset,
    # so the same pipeline serves both cases; awk's (start == "" || ...)
    # just always matches when there's no filter. track_year is the
    # leading 4 digits of the date field, compared numerically against
    # [start, end] rather than string-matched -- a plain substring search
    # would have false positives (e.g. a filter of "75" incorrectly
    # matching "1975"), and a numeric range needs a numeric comparison
    # regardless. A single year (-y 1975) is just a range of one
    # (YEAR_START == YEAR_END), so it's handled by the same comparison.
    # Tracks whose date isn't a clean 4-digit-leading value never match a
    # filter, rather than erroring -- same "skip what doesn't cleanly fit"
    # treatment as everywhere else this script filters candidates.
    #
    # The digit check below is spelled out as four [0-9] classes rather
    # than [0-9]{4} deliberately -- mawk (Debian/Ubuntu's default awk,
    # which this script only ever requires "awk" for) doesn't support
    # brace-interval regex syntax and silently matches nothing with it,
    # unlike bash's own =~ used for the same 4-digit check elsewhere in
    # this script, which has no such limitation.
    #
    # Genre matching (-g/--genre) is deliberately a case-insensitive
    # substring match via index(), not the exact matching used for
    # album/albumartist -- genre tagging is inherently loose and
    # inconsistent across libraries ("Rock" vs. "Classic Rock" vs.
    # "rock"), unlike album/artist identity, where exact matching is what
    # prevents two different things from being conflated. index() also
    # sidesteps any regex-metacharacter surprises from an arbitrary
    # user-supplied genre string, the same reasoning the year filter
    # originally used it for before it needed numeric range comparison.
    mapfile -t candidates < <(
        mpc listall --format='%albumartist%\t%album%\t%date%\t%genre%' |
            awk -F '\t' -v start="$YEAR_START" -v end="$YEAR_END" -v genre="${GENRE_FILTER,,}" '
                NF >= 2 &&
                $1 != "" &&
                $2 != "" &&
                (start == "" ||
                    (substr($3, 1, 4) ~ /^[0-9][0-9][0-9][0-9]$/ &&
                     substr($3, 1, 4) + 0 >= start + 0 &&
                     substr($3, 1, 4) + 0 <= end + 0)) &&
                (genre == "" || index(tolower($4), genre) > 0) {
                    print $1 "\t" $2
                }
            ' |
            sort -u
    )

    # Excludes albums picked recently (see AVOID_REPEATS/-A/--allow-repeats
    # and update_cache()) from the candidate pool before shuf ever sees it,
    # rather than picking-and-retrying one at a time -- this can't loop
    # indefinitely, and a pool that's shrunk too far to satisfy
    # album_count falls straight through to the existing partial-success
    # (or --force) handling exactly like an album vanishing from the
    # library would.
    if [[ "$AVOID_REPEATS" == true && "$ALLOW_REPEATS_OVERRIDE" != true && -s "$CACHE_FILE" && ${#candidates[@]} -gt 0 ]]; then
        local -a filtered=()
        mapfile -t filtered < <(printf '%s\n' "${candidates[@]}" | grep -vxFf "$CACHE_FILE" || true)
        if [[ ${#filtered[@]} -lt ${#candidates[@]} ]]; then
            excluded_recent=true
        fi
        candidates=("${filtered[@]}")
    fi

    RANDOM_ALBUMS=()
    if [[ ${#candidates[@]} -gt 0 ]]; then
        mapfile -t RANDOM_ALBUMS < <(printf '%s\n' "${candidates[@]}" | shuf -n "$album_count")
    fi

    if [[ ${#RANDOM_ALBUMS[@]} -eq 0 ]]; then
        if [[ "$excluded_recent" == true ]]; then
            error_exit "No albums remain after excluding recently-picked ones. Use -A/--allow-repeats, lower CACHE_SIZE, or add more music."
        fi
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
# Recent-albums cache
# ---------------------------------------------------------------------------

#
# Records this run's resolved albums as "recently picked" for AVOID_REPEATS
# to exclude on future runs, trimming the cache to the last CACHE_SIZE
# entries. Only called after a real (non-dry-run) run has actually changed
# the queue, so a dry run or a failed run never pollutes it. A failure here
# is reported but never fatal -- the queue/playback change it's recording
# has already succeeded by the time this runs, and a stale/missing cache
# file just means AVOID_REPEATS has less history to work with next time,
# not a reason to make an otherwise-successful run exit non-zero.
#
update_cache() {
    if [[ "$AVOID_REPEATS" != true ]]; then
        return 0
    fi

    if ! [[ "$CACHE_SIZE" =~ ^[0-9]+$ ]]; then
        warning_message "CACHE_SIZE in $CONFIG_FILE is invalid ('$CACHE_SIZE'); skipping recent-albums cache update."
        return 0
    fi

    if (( CACHE_SIZE == 0 )); then
        return 0
    fi

    mkdir -p "$CACHE_DIR"
    touch "$CACHE_FILE"

    local -a combined
    mapfile -t combined < <(cat "$CACHE_FILE"; printf '%s\n' "${RESOLVED_ALBUMS[@]}")

    local cache_tmp
    cache_tmp="$(mktemp "${CACHE_FILE}.XXXXXX")"
    printf '%s\n' "${combined[@]}" | tail -n "$CACHE_SIZE" > "$cache_tmp"
    mv "$cache_tmp" "$CACHE_FILE"
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
    update_cache || warning_message "Failed to update the recent-albums cache."

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
