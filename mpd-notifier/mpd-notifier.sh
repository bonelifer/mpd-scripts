#!/bin/bash

# Sends a desktop notification (via notify-send) for the currently playing
# MPD track, showing title, artist, and album, using the mpc command-line
# tool. On compilations, shows the track's real artist rather than the
# album's artist (e.g. "Various Artists"). Falls back to a generic image
# when no cover art is found for the track.

# Cobbled together from other now playing scripts.
# Image found on Google Images

# Config lives in ~/.config/mpd-notifier/mpd-notifier.conf, seeded from the
# template shipped alongside this script on first run; see that file for
# what each setting does.
config_dir="$HOME/.config/mpd-notifier"
config_file="$config_dir/mpd-notifier.conf"

if [ ! -f "$config_file" ]; then
    mkdir -p "$config_dir"
    cp "$(dirname "$0")/mpd-notifier.conf" "$config_file"
fi

# shellcheck source=mpd-notifier.conf
source "$config_file"

fallback_image="$cache_dir/unknown.jpg"

# Check if the cache directory exists, create it if not
if [ ! -d "$cache_dir" ]; then
    mkdir -p "$cache_dir"
fi

# Copy 'unknown.jpg' if it doesn't exist in the cache directory
if [ ! -f "$fallback_image" ]; then
    cp "$(dirname "$0")/unknown.jpg" "$cache_dir"
fi

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
        local_image="$(dirname "$dir${array[5]}")/cover.jpg"
        cache_image="$cache_dir/cover.jpg"
        # Check if cover.jpg exists locally, if not, use the fallback image directly
        if [ -f "$local_image" ]; then
            cp "$local_image" "$cache_image"
        else
            cache_image="$fallback_image"
        fi
    fi
fi

# Construct notify-send command based on image availability
if [ -f "$cache_image" ]; then
    if [ "$status" == "playing" ]; then
        notify-send "${array[1]}" "${display_artist}\n${array[4]}" -t "$notify_duration" -i "$cache_image"
    elif [ "$status" == "paused" ]; then
        notify-send "${array[1]}" "${display_artist}\n${array[4]} ($status)" -t "$notify_duration" -i "$cache_image"
    else
        notify-send -i "$cache_image" -t "$notify_duration" "MPD client $status"
    fi
else
    if [ "$status" == "playing" ]; then
        notify-send "${array[1]}" "${display_artist}\n${array[4]}" -t "$notify_duration" -i "$fallback_image"
    elif [ "$status" == "paused" ]; then
        notify-send "${array[1]}" "${display_artist}\n${array[4]} ($status)" -t "$notify_duration" -i "$fallback_image"
    else
        notify-send -i "${fallback_image}" -t "$notify_duration" "MPD client $status"
    fi
fi
