#!/usr/bin/bash
# mpdsimilar.sh — Fetches similar artist tracks via Last.fm and adds them to the MPD queue.
#
# Usage:
#   mpdsimilar.sh [OPTIONS]
#
# Options:
#   -c, --current   Add similar artist tracks for the currently playing track.
#                   Crops the playlist to only the current track first.
#   -a, --all       Add similar artist tracks for every track already in the queue.
#   -s, --shuffle   Shuffle the playlist after adding new tracks.
#   -l, --length N  Override the configured max playlist size with N for this run.
#   -i, --install   Install missing required packages via apt-get.
#   -h, --help      Show usage and exit. Also shown when run with no options.
#
# -c and -a are mutually exclusive.
#
# Configuration:
#   All configurable parameters live in
#   ~/.config/mpd-scripts/mpdsimilar/mpdsimilar.conf, seeded from
#   mpdsimilar.conf.example (shipped alongside this script) on first run:
#     lastfm_api_key       Last.fm API key.
#     lastfm_api_url       Last.fm API endpoint.
#     similar_limit        Number of similar artists to fetch per query.
#     per_artist_limit     Maximum tracks sampled per similar artist.
#     current_total_limit  Total tracks added when using -c/--current.
#     per_track_limit      Total tracks added per queue entry when using -a/--all.
#     max_playlist_size    Hard cap on MPD playlist size (MPD default: 16 368).
#                           Can be overridden per-run with -l/--length.
#     api_rate_limit_delay Seconds to sleep between Last.fm API calls.
#     curl_max_time        Seconds before a Last.fm request times out.

set -euo pipefail

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------
required_apps=("curl" "jq" "mpc")

# Check that all required tools are present; print missing ones and exit.
# Does not attempt installation — see install_missing_apps.
check_required_apps() {
    local -a missing=()

    for app in "${required_apps[@]}"; do
        if ! command -v "${app}" &>/dev/null; then
            missing+=("${app}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: the following required applications are missing: ${missing[*]}" >&2
        echo "Run with -i/--install to attempt automatic installation." >&2
        exit 1
    fi
}

# Install all packages in $required_apps via apt-get in a single pass.
install_missing_apps() {
    echo "Installing missing packages: ${required_apps[*]}"
    sudo apt-get update
    sudo apt-get install -y \
        curl \
        jq \
        mpc

    check_required_apps
    echo "All required packages are installed."
}

# ---------------------------------------------------------------------------
# Config file (all configurable parameters)
# ---------------------------------------------------------------------------
# Every tunable, including the Last.fm API key, lives outside the script in
# ~/.config/mpd-scripts/mpdsimilar/mpdsimilar.conf, seeded from
# mpdsimilar.conf.example on first run, so secrets never end up committed
# to version control.
config_dir="${HOME}/.config/mpd-scripts/mpdsimilar"
config_file="${config_dir}/mpdsimilar.conf"

# Seed the live config from the tracked .example template on first run, then
# source it. Exits early (after seeding) so the user can fill in their key.
# Only called when a Last.fm API call is actually about to happen.
load_config() {
    if [[ ! -f "${config_file}" ]]; then
        mkdir -p "${config_dir}"
        cp "$(dirname "$0")/mpdsimilar.conf.example" "${config_file}"
        chmod 600 "${config_file}"  # Contains a Last.fm API key
        echo "Created ${config_file} -- add your Last.fm API key, then run this again." >&2
        exit 1
    fi

    # shellcheck source=mpdsimilar.conf.example
    source "${config_file}"

    if [[ -z "${lastfm_api_key:-}" || "${lastfm_api_key}" == "your_lastfm_api_key_here" ]]; then
        echo "Error: ${config_file} still has a placeholder lastfm_api_key. Edit it first." >&2
        exit 1
    fi

    # -l/--length, parsed before the config file is loaded, takes precedence
    # over the max_playlist_size value just sourced from it.
    if [[ -n "${length_override}" ]]; then
        max_playlist_size="${length_override}"
    fi
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

display_help() {
    cat <<HELP
Usage: $(basename "$0") [OPTIONS]

Options:
  -c, --current   Add similar artist tracks for the currently playing track.
                  Crops the queue to the current track first.
  -a, --all       Add similar artist tracks for each track in the current queue.
  -s, --shuffle   Shuffle the playlist after adding new tracks.
  -l, --length N  Override the max playlist size configured in mpdsimilar.conf, for this run.
  -i, --install   Install missing required packages via apt-get.
  -h, --help      Show this help message.

Note: -c and -a are mutually exclusive.
HELP
    exit 0
}

# Return the current number of tracks in the MPD playlist.
# Outputs:
#   Integer track count on stdout.
get_playlist_size() {
    mpc playlist | wc -l
}

# Return 0 when the playlist has room for more tracks, 1 when the cap is hit.
playlist_has_room() {
    local current_size
    current_size=$(get_playlist_size)

    if (( current_size >= max_playlist_size )); then
        echo "Playlist limit reached (${max_playlist_size} tracks). Stopping additions."
        return 1
    fi

    return 0
}

# Call the Last.fm artist.getSimilar API and return the raw JSON response.
# On curl failure or timeout, prints a warning to stderr and returns empty.
#
# Arguments:
#   $1  Artist name to query.
# Outputs:
#   Raw JSON response on stdout, or empty string on failure.
call_lastfm_api() {
    local artist="$1"
    local lastfm_response

    lastfm_response=$(
        curl --silent --fail --get \
            --max-time "${curl_max_time}" \
            --data-urlencode "api_key=${lastfm_api_key}" \
            --data-urlencode "format=json" \
            --data-urlencode "limit=${similar_limit}" \
            --data-urlencode "method=artist.getsimilar" \
            --data-urlencode "artist=${artist}" \
            "${lastfm_api_url}" \
        || true
    )

    if [[ -z "${lastfm_response}" ]]; then
        echo "Warning: Last.fm request failed or timed out for '${artist}'." >&2
    fi

    echo "${lastfm_response}"
}

# Parse a Last.fm JSON response and extract similar artist names.
# Checks for API-level errors before parsing. On error, prints a warning
# to stderr and outputs nothing.
#
# Arguments:
#   $1  Raw JSON response string from call_lastfm_api.
#   $2  Source artist name (used in error messages).
# Outputs:
#   One similar artist name per line on stdout.
parse_similar_artists() {
    local lastfm_response="$1"
    local source_artist="$2"
    local api_error api_message

    # Detect Last.fm API-level error codes in the response body.
    api_error=$(echo "${lastfm_response}" | jq -r '.error // empty' 2>/dev/null || true)

    if [[ -n "${api_error}" ]]; then
        api_message=$(echo "${lastfm_response}" | jq -r '.message // "unknown error"' 2>/dev/null || true)
        echo "Warning: Last.fm API error ${api_error} for '${source_artist}': ${api_message}" >&2
        return 0
    fi

    echo "${lastfm_response}" \
        | jq --raw-output '.similarartists.artist[]?.name' 2>/dev/null \
        || true
}

# Fetch similar artists for a given artist from Last.fm.
# Always prepends the source artist so their own local tracks are candidates
# even when Last.fm returns no results or the request fails.
#
# Arguments:
#   $1  Artist name to query.
# Outputs:
#   Source artist followed by similar artist names, one per line on stdout.
fetch_similar_artists() {
    local artist="$1"
    local lastfm_response

    lastfm_response=$(call_lastfm_api "${artist}")

    # Always include the source artist so their own tracks are candidates.
    echo "${artist}"

    [[ -z "${lastfm_response}" ]] && return 0

    parse_similar_artists "${lastfm_response}" "${artist}"
}

# Search the local MPD library for tracks by an artist using exact tag
# matching to avoid substring false positives (e.g. "The Knife" matching
# "The Knife of Something"). Returns up to $2 randomly sampled file paths.
# shuf -n returns fewer than $2 when fewer results exist — this is intentional.
#
# Arguments:
#   $1  Artist name to search.
#   $2  Maximum number of tracks to return.
# Outputs:
#   File paths on stdout, one per line. Errors from mpc go to stderr.
sample_tracks_for_artist() {
    local artist="$1"
    local limit="$2"

    # Fetch artist tag and file path together, filter by exact case-insensitive
    # artist match, then randomly sample up to $limit results.
    mpc search -f "%artist%\t%file%" artist "${artist}" 2>&1 \
        | awk -F'\t' -v a="${artist}" 'tolower($1) == tolower(a) {print $2}' \
        | shuf -n "${limit}"
}

# Deduplicate a list of file paths, preserving order of first occurrence.
#
# Arguments:
#   $@  File paths to deduplicate.
# Outputs:
#   Deduplicated file paths on stdout, one per line.
deduplicate_tracks() {
    printf '%s\n' "$@" | awk '!seen[$0]++'
}

# Add file paths to the MPD playlist, stopping early if the size cap is hit.
# Playlist size is checked once per track as the inner safety net.
#
# Arguments:
#   $@  File paths to add.
add_tracks_to_playlist() {
    local track

    for track in "$@"; do
        if ! playlist_has_room; then
            return 1
        fi
        mpc add "${track}" 2>&1 || echo "Warning: failed to add '${track}' to playlist." >&2
    done
}

# Collect candidate tracks from the source artist and similar artists,
# deduplicate, shuffle, and add up to $2 total tracks to the playlist.
#
# Arguments:
#   $1  Artist name.
#   $2  Maximum number of tracks to add.
enqueue_similar_for_artist() {
    local artist="$1"
    local total_limit="$2"
    local -a candidate_tracks=()
    local -a deduplicated_tracks=()
    local -a sampled_tracks=()
    local similar_artist track

    while IFS= read -r similar_artist; do
        while IFS= read -r track; do
            candidate_tracks+=("${track}")
        done < <(sample_tracks_for_artist "${similar_artist}" "${per_artist_limit}")
    done < <(fetch_similar_artists "${artist}")

    # Nothing found in the local library for this artist or any similar artist.
    [[ ${#candidate_tracks[@]} -eq 0 ]] && return 0

    # Deduplicate before shuffling to avoid the same track appearing twice.
    mapfile -t deduplicated_tracks < <(deduplicate_tracks "${candidate_tracks[@]}")

    # Shuffle all candidates and trim to the requested limit.
    mapfile -t sampled_tracks < <(printf '%s\n' "${deduplicated_tracks[@]}" | shuf -n "${total_limit}")

    [[ ${#sampled_tracks[@]} -eq 0 ]] && return 0

    add_tracks_to_playlist "${sampled_tracks[@]}"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
[[ $# -eq 0 ]] && display_help

current_track=false
all_tracks=false
shuffle_playlist=false
length_override=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--current)  current_track=true;    shift ;;
        -a|--all)      all_tracks=true;       shift ;;
        -s|--shuffle)  shuffle_playlist=true; shift ;;
        -l|--length)
            if [[ $# -lt 2 ]]; then
                echo "Error: -l/--length requires an argument." >&2
                exit 1
            fi
            if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "Error: -l/--length must be a positive integer, got '$2'." >&2
                exit 1
            fi
            length_override="$2"
            shift 2
            ;;
        -i|--install)  install_missing_apps;  exit 0 ;;
        -h|--help)     display_help ;;
        *)
            echo "Unknown option: $1"
            display_help
            ;;
    esac
done

if [[ "${current_track}" == true && "${all_tracks}" == true ]]; then
    echo "Error: -c/--current and -a/--all are mutually exclusive."
    exit 1
fi

# Only reached once -h/--help/-i/--install (which exit within the parsing loop
# above) are ruled out, so those work even when curl/jq/mpc aren't installed.
check_required_apps

# Only the Last.fm-hitting paths need the config (API key + tunables).
if [[ "${current_track}" == true || "${all_tracks}" == true ]]; then
    load_config
fi

# ---------------------------------------------------------------------------
# -c / --current
# ---------------------------------------------------------------------------
if [[ "${current_track}" == true ]]; then
    artist=$(mpc current -f "%artist%")

    if [[ -z "${artist}" ]]; then
        echo "Nothing is currently playing."
        exit 1
    fi

    # Crop the queue to only the current track before adding new tracks.
    mpc crop

    echo "Fetching similar artists for: ${artist}"
    enqueue_similar_for_artist "${artist}" "${current_total_limit}"
fi

# ---------------------------------------------------------------------------
# -a / --all
# ---------------------------------------------------------------------------
if [[ "${all_tracks}" == true ]]; then
    # Snapshot the queue before adding to it so newly added tracks are not
    # re-processed in this run.
    mapfile -t queue_artists < <(mpc playlist -f "%artist%")

    if [[ ${#queue_artists[@]} -eq 0 ]]; then
        echo "The playlist is empty — nothing to process."
        exit 1
    fi

    # Track processed artists (lowercase) to skip duplicates across the queue.
    declare -A seen_artists=()
    local_total=${#queue_artists[@]}
    current_index=0

    for artist in "${queue_artists[@]}"; do
        (( current_index++ )) || true

        # Check playlist cap once per artist rather than per track.
        if ! playlist_has_room; then
            break
        fi

        # Skip blank artist tags — these would send empty strings to Last.fm.
        if [[ -z "${artist}" ]]; then
            echo "Warning: skipping track with blank artist tag." >&2
            continue
        fi

        # Normalise to lowercase for case-insensitive deduplication.
        artist_key="${artist,,}"

        if [[ -n "${seen_artists[${artist_key}]+set}" ]]; then
            continue
        fi
        seen_artists["${artist_key}"]=1

        echo "Fetching similar artists for: ${artist}"
        enqueue_similar_for_artist "${artist}" "${per_track_limit}"

        # Respect Last.fm rate limits between API calls, but not after the last one.
        if (( current_index < local_total )); then
            sleep "${api_rate_limit_delay}"
        fi
    done
fi

# ---------------------------------------------------------------------------
# -s / --shuffle
# ---------------------------------------------------------------------------
if [[ "${shuffle_playlist}" == true ]]; then
    echo "Shuffling playlist..."
    mpc shuffle
fi
