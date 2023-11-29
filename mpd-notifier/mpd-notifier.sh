#!/bin/bash

# Displays and retrieves album cover art for the currently playing track in MPD using
# the mpc command-line tool. Provides a fallback image when the album art is absent.

# Cobled together from other now playing scripts.
# Image found on Google Images


# BEGIN CONFIG
dir="/media/william/Data2/BACKUP/MP3/"
# MPD_HOST="192.168.1.80" # Uncomment for connecting to a non-local MPD instance
notify_duration="5000"
cache_dir="/media/william/DataOrig/MPD/.notify-cache/"
## END CONFIG

fallback_image="$cache_dir/unknown.jpg"

# Check if the cache directory exists, create it if not
if [ ! -d "$cache_dir" ]; then
    mkdir -p "$cache_dir"
fi

# Copy 'unknown.jpg' if it doesn't exist in the cache directory
if [ ! -f "$fallback_image" ]; then
    cp "$(dirname "$0")/unknown.jpg" "$cache_dir"
fi

# Get all the info needed to create the notify-send message: album artist, album, title, cover image.
output=$(mpc -f "%title%\n%albumartist%\n%album%\n%file%" current)

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

    array[1]=$(echo "${array[1]}" | sed 's/\&/\&amp\;/')
    array[2]=$(echo "${array[2]}" | sed 's/\&/\&amp\;/')
    array[3]=$(echo "${array[3]}" | sed 's/\&/\&amp\;/')

    file=$(ls -t "$(dirname "$dir${array[4]}")"/*.{jpg,png} 2> /dev/null | head -n 1)
fi

if [[ -f "$file" && "$status" == "playing" ]]; then
    notify-send "${array[1]}" "${array[2]}\n${array[3]}" -t "$notify_duration" -i "$file"
elif [[ -f "$file" && "$status" == "paused" ]]; then
    notify-send "${array[1]}" "${array[2]}\n${array[3]} ($status)" -t "$notify_duration" -i "$file"
elif [[ ! -f "$file" && "$status" == "playing" ]]; then
    notify-send "${array[1]}" "${array[2]}\n${array[3]}" -t "$notify_duration" -i "${fallback_image}"
elif [[ ! -f "$file" && "$status" == "paused" ]]; then
    notify-send "${array[1]}" "${array[2]}\n${array[3]} ($status)" -t "$notify_duration" -i "${fallback_image}"
else
    notify-send -i "${fallback_image}" -t "$notify_duration" "MPD client $status"
fi

