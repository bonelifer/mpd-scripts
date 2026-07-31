#!/bin/bash

# Sends a desktop notification (via notify-send, or dunstify with
# use_dunstify="true") for the currently playing MPD track, showing title,
# artist, and album, using the mpc command-line tool. On compilations, shows
# the track's real artist rather than the album's artist (e.g. "Various
# Artists"). Looks for a cover/folder/artwork/front image in the track's
# directory, optionally falls back to art embedded in the file itself (see
# embed_art_fallback), and falls back further to a generic image when none
# is found. See mpd-notifier.conf.example for optional features: embedded
# art extraction, grayscale cover art while paused, and notification
# categories.

# Cobbled together from other now playing scripts.
# Image found on Google Images

# Config lives in ~/.config/mpd-notifier/mpd-notifier.conf, seeded from the
# mpd-notifier.conf.example template shipped alongside this script on first
# run; see that file for what each setting does.
config_dir="$HOME/.config/mpd-notifier"
config_file="$config_dir/mpd-notifier.conf"

if [ ! -f "$config_file" ]; then
    mkdir -p "$config_dir"
    cp "$(dirname "$0")/mpd-notifier.conf.example" "$config_file"
fi

# shellcheck source=mpd-notifier.conf.example
source "$config_file"

MPC_CMD=(mpc)
if [ -n "${MPD_HOST}" ]; then
    MPC_CMD=(mpc -h "${MPD_HOST}" -p 6600)
fi

# With use_dunstify="true", use dunst's `dunstify` instead of notify-send.
# dunstify is a known-good, reliably-featured notify-send alternative (worth
# it on systems like Ubuntu 22.04, whose stock notify-send predates
# -r/--replace-id and -A/--action support), but its actions use a different
# argument format ("action,Label" instead of "action=Label"), so it's treated
# as its own mode rather than auto-detected the same way as notify-send.
NOTIFY_CMD="notify-send"
ACTION_SEP="="
if [ "${use_dunstify}" == "true" ]; then
    NOTIFY_CMD="dunstify"
    ACTION_SEP=","
fi

for cmd in mpc "$NOTIFY_CMD"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' is required but not installed." >&2
        exit 1
    fi
done

if [ "$NOTIFY_CMD" == "dunstify" ]; then
    # dunstify reliably supports all of these, regardless of exact --help wording.
    NOTIFY_REPLACE_ARGS=(-r 91325)
    NOTIFY_ACTIONS_SUPPORTED=1
    NOTIFY_CATEGORY_SUPPORTED=1
else
    # Not every notify-send provider supports -r/--replace-id, -A/--action,
    # or -c/--category (e.g. the notify-send.sh reimplementation, or Ubuntu
    # 22.04's stock libnotify-bin), so only use them if advertised.
    NOTIFY_SEND_HELP="$("$NOTIFY_CMD" --help 2>/dev/null)"

    NOTIFY_REPLACE_ARGS=()
    if echo "$NOTIFY_SEND_HELP" | grep -q -- '--replace-id'; then
        NOTIFY_REPLACE_ARGS=(-r 91325)
    fi

    NOTIFY_ACTIONS_SUPPORTED=0
    if echo "$NOTIFY_SEND_HELP" | grep -q -- '--action'; then
        NOTIFY_ACTIONS_SUPPORTED=1
    fi

    NOTIFY_CATEGORY_SUPPORTED=0
    if echo "$NOTIFY_SEND_HELP" | grep -q -- '--category'; then
        NOTIFY_CATEGORY_SUPPORTED=1
    fi
fi

fallback_image="$cache_dir/unknown.jpg"

# Check if the cache directory exists, create it if not
if [ ! -d "$cache_dir" ]; then
    mkdir -p "$cache_dir"
fi

# Copy 'unknown.jpg' if it doesn't exist in the cache directory
if [ ! -f "$fallback_image" ]; then
    cp "$(dirname "$0")/unknown.jpg" "$cache_dir"
fi

# Escapes '&' for Pango markup, picks display_artist (real artist vs album
# artist, for compilations), and resolves the cover-art image path. Assumes
# array[1..5] (title/artist/albumartist/album/file) and $status are already
# set by whichever path populated them below.
finish_song_info() {
    # notify-send parses the body as Pango markup, so a literal "&" (e.g. in
    # "Rock & Roll") must be escaped to "&amp;" or the notification won't render.
    array[1]=$(echo "${array[1]}" | sed 's/\&/\&amp\;/')
    array[2]=$(echo "${array[2]}" | sed 's/\&/\&amp\;/')
    array[3]=$(echo "${array[3]}" | sed 's/\&/\&amp\;/')
    array[4]=$(echo "${array[4]}" | sed 's/\&/\&amp\;/')

    # On compilations, artist (per-track) differs from album artist (e.g.
    # "Various Artists"); prefer the real artist for the notification.
    if [ -n "${array[2]}" ] && [ "${array[2]}" != "${array[3]}" ]; then
        display_artist="${array[2]}"
    else
        display_artist="${array[3]}"
    fi

    if [ -z "${MPD_HOST}" ]; then
        track_path="$dir${array[5]}"
        track_dir="$(dirname "$track_path")"
        cache_image="$cache_dir/cover.jpg"

        # Look for a cover image file in the track's directory -- any
        # filename containing "cover", "folder", "artwork", or "front"
        # (case-insensitive), not just a literal cover.jpg. Uses -iname
        # (basename-only matching) rather than -iregex, which matches the
        # whole path -- an artist/album directory containing one of these
        # words (e.g. "Front Line Assembly") would otherwise make every
        # .jpg/.jpeg in that directory match.
        local_image=""
        if [ -d "$track_dir" ]; then
            local_image="$(find "$track_dir" -maxdepth 1 -type f \
                \( -iname '*cover*.jpg' -o -iname '*cover*.jpeg' \
                   -o -iname '*folder*.jpg' -o -iname '*folder*.jpeg' \
                   -o -iname '*artwork*.jpg' -o -iname '*artwork*.jpeg' \
                   -o -iname '*front*.jpg' -o -iname '*front*.jpeg' \) \
                2>/dev/null | sort | head -n1)"
        fi

        if [ -n "$local_image" ] && [ -f "$local_image" ]; then
            cp "$local_image" "$cache_image"
        elif [ "${embed_art_fallback}" == "true" ] && command -v ffmpeg &>/dev/null \
             && ffmpeg -loglevel quiet -y -i "$track_path" "$cache_image" </dev/null 2>/dev/null; then
            : # No cover file found, but ffmpeg pulled embedded art out of the track itself.
        else
            cache_image="$fallback_image"
        fi
    fi
}

if [ -n "${MPD_STATUS_STATE+x}" ]; then
    # Running as an mpdcron "player" hook: mpdcron already queried mpd and
    # exports the result as env vars, so use those directly instead of
    # querying mpc ourselves. MPD_STATUS_STATE is always exported regardless
    # of song content (unlike song tags, which are absent for untagged
    # tracks or when nothing is loaded), making it a reliable signal that
    # we're running under mpdcron rather than standalone.
    case "$MPD_STATUS_STATE" in
        play)  status=playing ;;
        pause) status=paused ;;
        *)     status=stopped ;;
    esac

    array[1]="${MPD_SONG_TAG_TITLE}"
    array[2]="${MPD_SONG_TAG_ARTIST}"
    array[3]="${MPD_SONG_TAG_ALBUM_ARTIST}"
    array[4]="${MPD_SONG_TAG_ALBUM}"
    array[5]="${MPD_SONG_URI}"
    finish_song_info

    # mpdcron's "player" hook fires on seeks too, same as MPD's own idle
    # protocol, but unlike the watch loop's in-memory tracking, each hook
    # invocation is a fresh process with no memory of the last one. Persist
    # a "file|state" signature and skip notifying again if only the seek
    # position changed.
    signature_file="$cache_dir/.last_signature"
    current_signature="${array[5]}|${status}"
    last_signature=""
    if [ -f "$signature_file" ]; then
        last_signature="$(cat "$signature_file")"
    fi
    if [ "$current_signature" == "$last_signature" ]; then
        exit 0
    fi
    echo "$current_signature" > "$signature_file"
else
    # Get all the info needed to create the notify-send message: title, artist,
    # album artist, album, cover image. Artist and album artist are fetched
    # separately so compilations (where they differ) can show the real track
    # artist instead of the album's "Various Artists" album artist.
    output=$(mpc -f "%title%\n%artist%\n%albumartist%\n%album%\n%file%" current)

    # Get MPD status
    if [ -n "${MPD_HOST}" ]; then
        status=$(mpc -h "${MPD_HOST}" -p 6600 | grep playing | cut -c2-8)
        status2=$(mpc -h "${MPD_HOST}" -p 6600 | grep pause | cut -c2-7)
    else
        status=$(mpc | grep playing | cut -c2-8)
        status2=$(mpc | grep pause | cut -c2-7)
    fi

    if [ "$status" == "playing" ]; then
        status=playing
    elif [[ "$status2" == "paused" ]]; then
        status=paused
    else
        status=stopped
    fi

    if [ $? -ne 1 ]; then
        i=1
        while read -r line; do
            array[$i]="$line"
            (( i++ ))
        done <<< "$output"

        finish_song_info
    fi
fi

# Runs the mpc command for whichever notification action button was clicked.
handle_notification_action() {
    case "$1" in
        next)      "${MPC_CMD[@]}" next >/dev/null 2>&1 ;;
        prev)      "${MPC_CMD[@]}" prev >/dev/null 2>&1 ;;
        playpause) "${MPC_CMD[@]}" toggle >/dev/null 2>&1 ;;
    esac
}

# True when MPD's "consume" mode is on, meaning each track is dropped from
# the queue once it's played -- in that case there's no previous track left
# to go back to, so the Previous button shouldn't be offered. Under
# mpdcron, this is already known from MPD_STATUS_CONSUME; otherwise ask mpc.
consume_enabled() {
    if [ -n "${MPD_STATUS_STATE+x}" ]; then
        [ "${MPD_STATUS_CONSUME}" == "1" ]
    else
        "${MPC_CMD[@]}" 2>/dev/null | grep -q 'consume: *on'
    fi
}

# Sends the notification via $NOTIFY_CMD (notify-send, or dunstify with
# use_dunstify="true"). With enable_actions="true" (and only if $NOTIFY_CMD
# actually supports actions), Play-or-Pause/Next buttons are added, plus
# Previous unless consume mode is on (see consume_enabled above). The
# play/pause button is labeled for whichever action it will actually
# perform: "Play" while paused, "Pause" otherwise. Actions imply waiting for
# the user to click one, so that call is backgrounded and its result
# dispatched to mpc once they do (or it's otherwise ignored if the
# notification just times out or gets replaced).
send_notification() {
    local summary="$1" body="$2" image="$3"
    local args=("${NOTIFY_REPLACE_ARGS[@]}" -t "$notify_duration" -i "$image")

    # With notify_categories="true" (and only if $NOTIFY_CMD advertises
    # support), tag the notification "mpd"/"mpd-paused"/"mpd-stopped" so a
    # notification daemon can filter or style it per playback state.
    if [ "${notify_categories}" == "true" ] && [ "$NOTIFY_CATEGORY_SUPPORTED" -eq 1 ]; then
        local category="mpd"
        case "$status" in
            paused)  category="mpd-paused" ;;
            stopped) category="mpd-stopped" ;;
        esac
        args+=(-c "$category")
    fi

    if [ "${enable_actions}" == "true" ] && [ "$NOTIFY_ACTIONS_SUPPORTED" -eq 1 ]; then
        local playpause_label="Pause"
        if [ "$status" == "paused" ]; then
            playpause_label="Play"
        fi
        local action_args=(-A "playpause${ACTION_SEP}${playpause_label}" -A "next${ACTION_SEP}Next")
        if ! consume_enabled; then
            action_args=(-A "prev${ACTION_SEP}Previous" "${action_args[@]}")
        fi
        (
            action=$("$NOTIFY_CMD" "${args[@]}" "${action_args[@]}" "$summary" "$body")
            handle_notification_action "$action"
        ) &
    else
        "$NOTIFY_CMD" "${args[@]}" "$summary" "$body"
    fi
}

# Construct notify-send/dunstify command based on image availability
if [ -f "$cache_image" ]; then
    image="$cache_image"
else
    image="$fallback_image"
fi

# With grayscale_when_paused="true", show a grayscale cover while paused, as
# a visual cue distinct from the "(paused)" text. Always written to a
# separate scratch file rather than converted in place, since $image may be
# $fallback_image -- a persistent cached file that must stay in color for
# the next "playing" notification.
if [ "$status" == "paused" ] && [ "${grayscale_when_paused}" == "true" ] && command -v convert &>/dev/null; then
    paused_image="$cache_dir/paused-cover.jpg"
    if convert "$image" -colorspace Gray "$paused_image" 2>/dev/null; then
        image="$paused_image"
    fi
fi

if [ "$status" == "playing" ]; then
    send_notification "${array[1]}" "${display_artist}\n${array[4]}" "$image"
elif [ "$status" == "paused" ]; then
    send_notification "${array[1]}" "${display_artist}\n${array[4]} ($status)" "$image"
else
    send_notification "MPD client $status" "" "$image"
fi
