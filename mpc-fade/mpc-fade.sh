#!/usr/bin/bash
#
# mpc-fade.sh
#
# Fades MPD playback volume smoothly instead of jumping instantly, either
# to a specific target volume over a fixed duration, or as a fade-out /
# play-pause toggle / fade-in wrapper. By default it fades MPD's own volume
# (`mpc volume`); pass -P/--pulse to fade the PulseAudio sink-input stream
# feeding MPD instead, useful when other apps share the same sink and you
# don't want MPD's own volume control involved.
#
# Usage:
#   mpc-fade.sh <end volume> <duration in secs> [-P] [-a NAME|-i ID] [-L] [-q] [-n]
#   mpc-fade.sh -t [-s SECS] [-P] [-a NAME|-i ID] [-L] [-q] [-n]
#   mpc-fade.sh -l
#
# Options:
#   -t, --toggle       Fade out, toggle play/pause, fade back in, instead
#                       of fading to a fixed target volume.
#   -s, --secs SECS    Fade duration in seconds for --toggle mode (default: 2,
#                       or DEFAULT_SECS from the config file below if set).
#   -P, --pulse        Fade the PulseAudio sink-input volume instead of
#                       MPD's own volume (requires pactl).
#   -a, --app NAME     PulseAudio application name to match in --pulse
#                       mode (default: mpd, or PULSE_APP from the config
#                       file below if set).
#   -i, --sink-id ID   Fade a specific PulseAudio sink-input index directly
#                       instead of matching by application name (implies
#                       --pulse). Useful when more than one stream shares
#                       the same application name.
#   -l, --list-sinks   List active PulseAudio sink inputs in a numbered
#                       list and save your choice as the default --pulse
#                       app to the config file (requires pactl).
#   -L, --log-curve    Use a logarithmic fade curve instead of linear --
#                       spends proportionally more time at quiet volumes,
#                       approximating a perceptually even fade (loudness is
#                       roughly logarithmic in volume%). Off by default,
#                       or set by LOG_CURVE in the config file below.
#   -q, --quiet        Suppress the "Fading..."/"Done." progress messages.
#                       Errors still print regardless.
#   -n, --dry-run      Print what would happen without changing anything.
#   -h, --help         Show this help and exit.
#
# Configuration:
#   PULSE_APP, DEFAULT_SECS, and LOG_CURVE live in
#   ~/.config/mpd-scripts/mpc-fade/mpc-fade.conf, seeded from
#   mpc-fade.conf.example (shipped alongside this script). PULSE_APP is
#   normally set by -l/--list-sinks saving a choice; the others can be
#   edited directly. All optional -- without a config file, -P mode falls
#   back to matching application name "mpd", --toggle fades default to 2s,
#   and the fade curve defaults to linear.
#
# Other behavior:
#   - Only one fade/toggle runs at a time -- a second invocation while one
#     is already in progress exits immediately with an error, instead of
#     racing the first one's volume changes.
#   - Ctrl+C (or SIGTERM) during a fade jumps straight to the target volume
#     before exiting, rather than leaving it stuck partway through.
#
# Examples:
#   mpc-fade.sh 60 30        # fade current volume to 60% over 30 seconds
#   mpc-fade.sh 0 5          # fade out to 0% over 5 seconds
#   mpc-fade.sh -t           # fade out / toggle play-pause / fade back in
#   mpc-fade.sh -t -P -s 3   # same, fading the PulseAudio stream over 3s
#   mpc-fade.sh -l           # pick and save a default --pulse app
#   mpc-fade.sh 0 5 -q       # fade out silently, e.g. from a cronjob
#   mpc-fade.sh 0 5 -L       # fade out on a logarithmic curve
#   mpc-fade.sh 60 30 -n     # preview a fade without changing anything
#
# Typical usage in shell scripts or cronjobs:
#
#   mpc stop
#   mpc clear
#   mpc volume 15
#   mpc load "Radio Fantasy"
#   mpc play
#   mpc-fade.sh 60 30   # fade to volume 60% within 30 sec
#   sleep $((60*5))
#   mpc-fade.sh 0 5     # fade to volume 0% within 5 sec
#   mpc stop

set -euo pipefail

PROGRAM_NAME="$(basename "$0")"

if (( BASH_VERSINFO[0] < 4 )); then
    echo >&2 "$PROGRAM_NAME: ERROR: Bash version 4 or later is required (running ${BASH_VERSION})."
    exit 1
fi

# Aborts with an error if a required command isn't on PATH.
require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo >&2 "$PROGRAM_NAME: ERROR: command '$1' not found in PATH."
        exit 1
    fi
}

require_cmd mpc
require_cmd bc
require_cmd flock

# A single `mpc`/`pactl` call blocks with zero output forever if MPD/Pulse
# is unreachable (wrong MPD_HOST, firewalled, not running) -- bound every
# call so that fails fast with a clear message instead of hanging silently.
CMD_TIMEOUT_SECS=5

mpc_timeout() {
    local status=0
    timeout "$CMD_TIMEOUT_SECS" mpc "$@" || status=$?
    if (( status == 124 )); then
        echo >&2 "$PROGRAM_NAME: ERROR: 'mpc $*' timed out after ${CMD_TIMEOUT_SECS}s -- check that MPD is running and reachable (MPD_HOST/MPD_PORT)."
    fi
    return "$status"
}

pactl_timeout() {
    local status=0
    timeout "$CMD_TIMEOUT_SECS" pactl "$@" || status=$?
    if (( status == 124 )); then
        echo >&2 "$PROGRAM_NAME: ERROR: 'pactl $*' timed out after ${CMD_TIMEOUT_SECS}s -- check that PulseAudio is running."
    fi
    return "$status"
}

# Prints a routine status message, suppressed by -q/--quiet. Errors always
# print regardless -- this is only for the non-essential progress chatter.
info() {
    (( QUIET )) || echo "$@"
}

display_help() {
    cat <<HELP
Usage:
  $PROGRAM_NAME <end volume> <duration in secs> [-P] [-a NAME|-i ID] [-L] [-q] [-n]
  $PROGRAM_NAME -t [-s SECS] [-P] [-a NAME|-i ID] [-L] [-q] [-n]
  $PROGRAM_NAME -l

Options:
  -t, --toggle       Fade out, toggle play/pause, fade back in.
  -s, --secs SECS    Fade duration in seconds for --toggle mode (default: $SECS).
  -P, --pulse        Fade the PulseAudio sink-input volume instead of MPD's own volume.
  -a, --app NAME     PulseAudio application name to match in --pulse mode (default: mpd,
                     or PULSE_APP from $CONFIG_FILE if set).
  -i, --sink-id ID   Fade a specific PulseAudio sink-input index directly (implies --pulse).
  -l, --list-sinks   List active PulseAudio sink inputs and save your choice as the
                     default --pulse app to $CONFIG_FILE.
  -L, --log-curve    Use a logarithmic fade curve instead of linear.
  -q, --quiet        Suppress the "Fading..."/"Done." progress messages.
  -n, --dry-run      Print what would happen without changing anything.
  -h, --help         Show this help and exit.
HELP
}

# PULSE_APP/DEFAULT_SECS/LOG_CURVE are all optional -- if the config file
# doesn't exist yet, everything just falls back to the defaults set here.
CONFIG_DIR="$HOME/.config/mpd-scripts/mpc-fade"
CONFIG_FILE="$CONFIG_DIR/mpc-fade.conf"

APP="mpd"
SECS=2
LOG_CURVE=0
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=mpc-fade.conf.example
    source "$CONFIG_FILE"
    [[ -n "${PULSE_APP:-}" ]] && APP="$PULSE_APP"
    [[ -n "${DEFAULT_SECS:-}" ]] && SECS="$DEFAULT_SECS"
fi

TOGGLE=0
PULSE=0
LIST_SINKS=0
QUIET=0
DRY_RUN=0
SINK_ID=""
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--toggle) TOGGLE=1; shift ;;
        -s|--secs) SECS="$2"; shift 2 ;;
        -P|--pulse) PULSE=1; shift ;;
        -a|--app) APP="$2"; shift 2 ;;
        -i|--sink-id) SINK_ID="$2"; PULSE=1; shift 2 ;;
        -l|--list-sinks) LIST_SINKS=1; shift ;;
        -L|--log-curve) LOG_CURVE=1; shift ;;
        -q|--quiet) QUIET=1; shift ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -h|--help) display_help; exit 0 ;;
        -*) echo >&2 "$PROGRAM_NAME: ERROR: unknown option '$1'"; display_help; exit 1 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

if (( PULSE || LIST_SINKS )); then
    require_cmd pactl
fi

# --- volume backend -------------------------------------------------------
#
# Both backends are addressed through get_volume/set_volume so fade_to()
# doesn't need to know whether it's driving `mpc volume` or a PulseAudio
# sink-input. The pulse functions take the sink-input index as an argument
# since, unlike MPD, a PulseAudio sink may have more than one client stream.

pulse_sink_input_index() {
    local raw
    raw=$(pactl_timeout list sink-inputs)
    echo "$raw" | awk -v app="$APP" '
        /^Sink Input #/ { idx = $0; sub(/^Sink Input #/, "", idx) }
        $0 ~ "application\\.name = \"" app "\"" { print idx; exit }
    '
}

get_volume() {
    if (( PULSE )); then
        local idx="$1" raw
        raw=$(pactl_timeout list sink-inputs)
        echo "$raw" \
            | sed -n "/^Sink Input #${idx}\$/,/^Sink Input #/p" \
            | grep -m1 'Volume:' \
            | grep -oP '\d+(?=%)' \
            | head -1
    else
        local raw
        raw=$(mpc_timeout volume)
        echo "$raw" | sed -e 's/[^0-9]*\([0-9]*\).*/\1/'
    fi
}

# No-op in --dry-run mode, so a preview run never actually changes volume.
set_volume() {
    local vol="$1" idx="${2:-}"
    (( DRY_RUN )) && return 0
    if (( PULSE )); then
        pactl_timeout set-sink-input-volume "$idx" "${vol}%" > /dev/null
    else
        mpc_timeout volume "$vol" > /dev/null
    fi
}

# Linear fade: constant %/sec, the original behavior.
fade_loop_linear() {
    local vol="$1" target="$2" duration="$3" idx="$4"
    local step_delay
    step_delay=$(echo "$duration / ($vol - $target)" | bc -l)
    step_delay=${step_delay#-}

    if (( vol < target )); then
        while (( vol <= target )); do
            set_volume "$vol" "$idx"
            vol=$(( vol + 1 ))
            sleep "$step_delay"
        done
    else
        while (( vol >= target )); do
            set_volume "$vol" "$idx"
            vol=$(( vol - 1 ))
            sleep "$step_delay"
        done
    fi
}

# Logarithmic fade: each 1% step's dwell time is weighted by 1/level
# (floored at 1%), so quiet levels get proportionally more real time than
# loud ones -- approximates a perceptually linear (constant loudness-rate)
# fade, since loudness is roughly logarithmic in volume%.
fade_loop_log() {
    local vol="$1" target="$2" duration="$3" idx="$4"
    local direction=1
    (( target < vol )) && direction=-1

    local -a levels
    local level="$vol"
    while true; do
        levels+=("$level")
        (( level == target )) && break
        level=$(( level + direction ))
    done

    local -a weights
    local weight_sum=0 lvl floored w
    for lvl in "${levels[@]}"; do
        floored=$(( lvl < 1 ? 1 : lvl ))
        w=$(echo "1 / $floored" | bc -l)
        weights+=("$w")
        weight_sum=$(echo "$weight_sum + $w" | bc -l)
    done

    local i delay
    for i in "${!levels[@]}"; do
        set_volume "${levels[$i]}" "$idx"
        delay=$(echo "$duration * ${weights[$i]} / $weight_sum" | bc -l)
        sleep "$delay"
    done
}

# Fades from the current volume to $1 over $2 seconds. $3 is the
# PulseAudio sink-input index, ignored when not in --pulse mode.
fade_to() {
    local target="$1" duration="$2" idx="${3:-}"
    local vol
    vol=$(get_volume "$idx")

    if [[ -z "$vol" ]]; then
        echo >&2 "$PROGRAM_NAME: ERROR: could not read current volume."
        exit 1
    fi

    if (( vol == target )); then
        info "Volume already at ${target}%. Nothing to do."
        return 0
    fi

    if (( DRY_RUN )); then
        local curve="linear"
        (( LOG_CURVE )) && curve="log"
        local backend="mpc"
        (( PULSE )) && backend="pulse"
        echo "[dry-run] would fade volume: ${vol}% -> ${target}% over ${duration}s ($curve curve, $backend backend)."
        return 0
    fi

    info "Fading volume: ${vol}% -> ${target}% over ${duration}s..."

    # Jump straight to the target instead of leaving volume stuck partway
    # through if interrupted mid-fade.
    trap "set_volume '${target}' '${idx}'; info 'Interrupted -- jumped to ${target}%.'; exit 130" INT TERM

    if (( LOG_CURVE )); then
        fade_loop_log "$vol" "$target" "$duration" "$idx"
    else
        fade_loop_linear "$vol" "$target" "$duration" "$idx"
    fi

    trap - INT TERM
    info "Done."
}

# Resolves the PulseAudio sink-input index for $APP (or the explicit
# --sink-id) in --pulse mode, or prints nothing (unused by the mpc
# backend) otherwise.
resolve_pulse_index() {
    if (( PULSE )); then
        local idx
        if [[ -n "$SINK_ID" ]]; then
            idx="$SINK_ID"
        else
            idx=$(pulse_sink_input_index)
        fi
        if [[ -z "$idx" ]]; then
            echo >&2 "$PROGRAM_NAME: ERROR: no PulseAudio sink input found for application '$APP'."
            exit 1
        fi
        echo "$idx"
    fi
}

# Toggles MPD play/pause, or just prints what it would do in --dry-run mode.
do_toggle() {
    if (( DRY_RUN )); then
        echo "[dry-run] would toggle play/pause."
    else
        mpc_timeout toggle -q
    fi
}

run_toggle() {
    local idx vol status_output
    idx=$(resolve_pulse_index)
    vol=$(get_volume "$idx")
    status_output=$(mpc_timeout status)

    if grep -q '\[playing\]' <<< "$status_output"; then
        fade_to 0 "$SECS" "$idx"
        do_toggle
        set_volume "$vol" "$idx"
    else
        set_volume 0 "$idx"
        do_toggle
        fade_to "$vol" "$SECS" "$idx"
    fi
}

run_fade_to_volume() {
    if [[ ${#ARGS[@]} -ne 2 ]]; then
        display_help
        exit 1
    fi

    local target="${ARGS[0]}" duration="${ARGS[1]}" idx
    idx=$(resolve_pulse_index)
    fade_to "$target" "$duration" "$idx"
}

# Writes $1 as PULSE_APP in $CONFIG_FILE, seeding the file from the
# .conf.example template alongside this script if it doesn't exist yet.
save_default_app() {
    local app="$1"
    mkdir -p "$CONFIG_DIR"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        cp "$(dirname "$0")/mpc-fade.conf.example" "$CONFIG_FILE"
    fi

    if grep -q '^PULSE_APP=' "$CONFIG_FILE"; then
        sed -i "s/^PULSE_APP=.*/PULSE_APP=\"$app\"/" "$CONFIG_FILE"
    else
        echo "PULSE_APP=\"$app\"" >> "$CONFIG_FILE"
    fi

    info "Saved default --pulse app '$app' to $CONFIG_FILE"
}

# Lists every active PulseAudio sink input in a numbered menu (index,
# application name, media name, volume), then prompts for a pick and saves
# its application name as the default --pulse/-a app via save_default_app.
list_sinks() {
    local list_raw raw
    list_raw=$(pactl_timeout list sink-inputs)
    raw=$(echo "$list_raw" | awk '
        function flush() {
            if (idx != "") {
                printf "%s\t%s\t%s\t%s\n", idx, (app == "" ? "?" : app), (media == "" ? "?" : media), (vol == "" ? "?" : vol)
            }
        }
        /^Sink Input #/ {
            flush()
            idx = $0; sub(/^Sink Input #/, "", idx)
            app = ""; media = ""; vol = ""
        }
        /Volume:/ && vol == "" {
            if (match($0, /[0-9]+%/)) vol = substr($0, RSTART, RLENGTH)
        }
        /application\.name = / {
            v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); app = v
        }
        /media\.name = / {
            v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); media = v
        }
        END { flush() }
    ')

    if [[ -z "$raw" ]]; then
        echo >&2 "$PROGRAM_NAME: no active PulseAudio sink inputs found."
        exit 1
    fi

    local -a idxs apps medias vols
    while IFS=$'\t' read -r idx app media vol; do
        idxs+=("$idx"); apps+=("$app"); medias+=("$media"); vols+=("$vol")
    done <<< "$raw"

    echo "Active PulseAudio sink inputs:"
    local i
    for i in "${!idxs[@]}"; do
        printf '  %d) %s - %s (%s) [id %s]\n' "$((i + 1))" "${apps[$i]}" "${medias[$i]}" "${vols[$i]}" "${idxs[$i]}"
    done

    local choice
    read -r -p "Select a sink to save as the default --pulse app (1-${#idxs[@]}), or Enter to cancel: " choice

    if [[ -z "$choice" ]]; then
        echo "Cancelled."
        exit 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#idxs[@]} )); then
        echo >&2 "$PROGRAM_NAME: ERROR: invalid selection '$choice'."
        exit 1
    fi

    save_default_app "${apps[$((choice - 1))]}"
}

# Only one fade/toggle may run at a time -- a second instance exits
# immediately instead of racing the first one's volume changes. Held via
# an open file descriptor for the life of the process; released
# automatically on exit.
acquire_lock() {
    local lock_file="${XDG_RUNTIME_DIR:-/tmp}/mpc-fade.lock"
    exec 9>"$lock_file"
    if ! flock -n 9; then
        echo >&2 "$PROGRAM_NAME: ERROR: another mpc-fade instance is already running ($lock_file)."
        exit 1
    fi
}

if (( LIST_SINKS )); then
    list_sinks
else
    acquire_lock
    if (( TOGGLE )); then
        run_toggle
    else
        run_fade_to_volume
    fi
fi

exit 0
