#!/usr/bin/bash
#
# playpause.sh
#
# Prints the currently playing/paused MPD track for use in a status bar
# (e.g. polybar, i3blocks), prefixed with a play/pause/stop symbol.
#
# Usage:
#   playpause.sh [-l LEN] [-h]
#
# Options:
#   -l, --max-len LEN   Truncate the title to LEN characters, appending an
#                       ellipsis when it's cut short (default: 0, meaning
#                       no truncation, or MAX_LEN from the config file
#                       below if set).
#   -h, --help          Show this help and exit.
#
# Output:
#   "<symbol> <title>" on stdout when a track is playing or paused; just
#   "<symbol>" when MPD is stopped, since `mpc` reports no current-track
#   line in that state. Symbol is "►" playing, "∎∎" paused, "■" stopped,
#   or SYMBOL_PLAYING/SYMBOL_PAUSED/SYMBOL_STOPPED from the config file
#   below if set. Prints nothing if `mpc` fails (e.g. MPD is not running).
#
# Configuration:
#   SYMBOL_PLAYING, SYMBOL_PAUSED, SYMBOL_STOPPED, MAX_LEN, and
#   FALLBACK_TITLE live in ~/.config/mpd-scripts/playpause/playpause.conf,
#   seeded from playpause.conf.example (shipped alongside this script).
#   All optional -- without a config file, the built-in defaults above
#   apply.

set -euo pipefail

PROGRAM_NAME="$(basename "$0")"

# Aborts with an error if a required command isn't on PATH.
require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo >&2 "$PROGRAM_NAME: ERROR: command '$1' not found in PATH."
        exit 1
    fi
}

require_cmd mpc

# SYMBOL_*/MAX_LEN/FALLBACK_TITLE are all optional -- if the config file
# doesn't exist yet, everything just falls back to the defaults set here.
CONFIG_DIR="$HOME/.config/mpd-scripts/playpause"
CONFIG_FILE="$CONFIG_DIR/playpause.conf"

SYMBOL_PLAYING="►"
SYMBOL_PAUSED="∎∎"
SYMBOL_STOPPED="■"
MAX_LEN=0
FALLBACK_TITLE="(unknown track)"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=playpause.conf.example
    source "$CONFIG_FILE"
fi

display_help() {
    cat <<HELP
Usage:
  $PROGRAM_NAME [-l LEN] [-h]

Options:
  -l, --max-len LEN   Truncate the title to LEN characters, with an ellipsis
                     when cut short (default: $MAX_LEN, meaning no limit,
                     or MAX_LEN from $CONFIG_FILE if set).
  -h, --help          Show this help and exit.
HELP
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--max-len) MAX_LEN="$2"; shift 2 ;;
        -h|--help) display_help; exit 0 ;;
        -*) echo >&2 "$PROGRAM_NAME: ERROR: unknown option '$1'"; display_help; exit 1 ;;
        *) echo >&2 "$PROGRAM_NAME: ERROR: unexpected argument '$1'"; display_help; exit 1 ;;
    esac
done

# Truncates $1 to $MAX_LEN characters, appending an ellipsis if it's cut
# short. MAX_LEN=0 (the default) means no truncation.
truncate_title() {
    local title="$1"
    if (( MAX_LEN > 0 )) && (( ${#title} > MAX_LEN )); then
        echo "${title:0:MAX_LEN}…"
    else
        echo "$title"
    fi
}

mpc_output=$(mpc) || exit
status_line=$(grep -E '^\[(playing|paused|stopped)\]' <<< "$mpc_output" || true)
status=$(cut -f 1 -d ' ' <<< "$status_line")

case "$status" in
    "[playing]"|"[paused]")
        title=$(head -n 1 <<< "$mpc_output")
        [[ -z "$title" ]] && title="$FALLBACK_TITLE"
        title=$(truncate_title "$title")
        if [[ "$status" == "[playing]" ]]; then
            echo "$SYMBOL_PLAYING $title"
        else
            echo "$SYMBOL_PAUSED $title"
        fi
        ;;
    *)
        echo "$SYMBOL_STOPPED"
        ;;
esac
