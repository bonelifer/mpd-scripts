#!/usr/bin/env bash
set -e

# Script to interact with the music queue and manage song ratings and statuses using "stickers"
# The stickers feature is used for marking songs with specific labels (e.g., "broken" or "rating").
# This script supports rating songs, rescaling stored ratings, flagging/unflagging songs as
# "bad" (broken), removing songs from the queue, listing songs flagged as bad, and jumping to
# a random or top-rated song in the queue.
# Ratings are compatible with clients such as Cantata, mpedv, and myMPD.

# Function to display usage instructions
usage () {
    # Display the command usage with details of available options
    echo "$0 <command> <args>"
    echo -e "\nCommands:"
    echo -e "    remove              remove current song from queue"
    echo -e "    random              jump to a random song in queue"
    echo -e "    flag_bad            flags current song as bad"
    echo -e "    unflag_bad          clears the bad flag on current song"
    echo -e "    list_bad            list all songs marked as bad"
    echo -e "    rate <0-$RATING_SCALE>    rate the current song"
    echo -e "    ratings [dir]       list ratings for all songs, optionally scoped to [dir]"
    echo -e "    rescale <old> <new> convert all stored ratings from the <old> scale to <new>"
    echo -e "    top_rated           jump to a top-rated song (mode set by TOP_RATED_MODE)"
}

# Function to check if mpc (Music Player Client) is installed
check_mpc_installed () {
    # If mpc is not installed, exit the script with an error message
    if ! command -v mpc &> /dev/null; then
        echo "mpc command not found. Please install it."
        exit 1
    fi
}

# Function to remove the current song from the queue
remove () {
    check_mpc_installed  # Ensure mpc is installed before proceeding
    # Resolve the current song's actual queue position; it is not always 0
    # (e.g. after skipping, random mode, or with already-played songs still queued).
    local position
    position="$(mpc -f '%position%' current)"
    if [[ -z "$position" ]]; then
        echo "No song is currently playing."
        exit 1
    fi
    mpc del "$position"   # Remove the song at its actual position in the queue
}

# Function to flag the current song as "bad" (broken)
flag_bad () {
    check_mpc_installed  # Ensure mpc is installed before proceeding
    # Get the file path of the current song and set the "broken" sticker to 1 (true)
    mpc sticker "$(mpc -f '%file%' current)" set broken 1
}

# Function to clear the "bad" (broken) flag from the current song
unflag_bad () {
    check_mpc_installed  # Ensure mpc is installed before proceeding
    # Get the file path of the current song and delete its "broken" sticker
    mpc sticker "$(mpc -f '%file%' current)" delete broken
}

# Function to list all songs that are marked as "bad" (broken)
list_bad () {
    check_mpc_installed  # Ensure mpc is installed before proceeding
    # Search for all songs with the "broken" sticker set
    mpc sticker "" find broken
}

# Function to jump to a random song in the queue
random () {
    check_mpc_installed  # Ensure mpc is installed before proceeding
    mpc random on        # Enable random play mode
    mpc next             # Skip to the next song, which will be random due to random play being enabled
    mpc random off       # Disable random play mode after jumping to the song
}

# Function to rate the current song (from 0 to RATING_SCALE)
rate () {
    check_mpc_installed  # Ensure mpc is installed before proceeding
    # Validate that the rating is an integer between 0 and RATING_SCALE
    if [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 0 && $1 <= RATING_SCALE )); then
        # Apply the rating to the current song
        mpc sticker "$(mpc -f '%file%' current)" set rating "$1"
    else
        # Print an error message and exit if the rating is not valid
        echo "Invalid rating. Please provide a rating between 0 and $RATING_SCALE."
        exit 1
    fi
}

# Function to list all ratings for songs in a specific directory
ratings () {
    check_mpc_installed  # Ensure mpc is installed before proceeding
    # Search for all songs in the specified directory and list their ratings
    mpc sticker "$1" find rating
}

# Function to convert every stored rating from one scale to another
# (e.g. after changing RATING_SCALE in the config). Run manually since it
# rewrites sticker data across the whole library.
rescale () {
    check_mpc_installed  # Ensure mpc is installed before proceeding
    local old="$1" new="$2"
    if [[ ! "$old" =~ ^[0-9]+$ || ! "$new" =~ ^[0-9]+$ || "$old" -le 0 || "$new" -le 0 ]]; then
        echo "Usage: rescale <old-scale> <new-scale> (both positive integers)"
        exit 1
    fi
    local line file rating new_rating
    # `mpc sticker "" find rating` prints one "<file>: rating=<value>" line per song
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        file="${line%%: rating=*}"
        rating="${line##*: rating=}"
        # Round to the nearest integer on the new scale, clamped to [0, new]
        new_rating=$(( (rating * new + old / 2) / old ))
        (( new_rating > new )) && new_rating=$new
        (( new_rating < 0 )) && new_rating=0
        mpc sticker "$file" set rating "$new_rating"
    done < <(mpc sticker "" find rating)
}

# Function to jump to a top-rated song. TOP_RATED_MODE from the config
# controls whether ties for the highest rating are broken deterministically
# ("single") or by picking randomly among them ("random").
top_rated () {
    check_mpc_installed  # Ensure mpc is installed before proceeding
    local line file rating max_rating=-1
    local -a top_files=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        file="${line%%: rating=*}"
        rating="${line##*: rating=}"
        if (( rating > max_rating )); then
            max_rating=$rating
            top_files=("$file")
        elif (( rating == max_rating )); then
            top_files+=("$file")
        fi
    done < <(mpc sticker "" find rating)

    if (( ${#top_files[@]} == 0 )); then
        echo "No rated songs found."
        exit 1
    fi

    local chosen
    if [[ "$TOP_RATED_MODE" == "random" ]]; then
        chosen="${top_files[RANDOM % ${#top_files[@]}]}"
    else
        chosen="${top_files[0]}"
    fi

    mpc insert "$chosen"  # Queue it right after the current song
    mpc next              # Jump to it
}

# Config lives in
# ~/.config/mpd-scripts/music_queue_manager/music_queue_manager.conf, seeded
# from the music_queue_manager.conf.example template shipped alongside this
# script on first run.
CONFIG_DIR="$HOME/.config/mpd-scripts/music_queue_manager"
CONFIG_FILE="$CONFIG_DIR/music_queue_manager.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$CONFIG_DIR"
    cp "$(dirname "$0")/music_queue_manager.conf.example" "$CONFIG_FILE"
fi

# shellcheck source=music_queue_manager.conf.example
source "$CONFIG_FILE"

if [[ "$RATING_SCALE" != "5" && "$RATING_SCALE" != "10" ]]; then
    echo "Error: $CONFIG_FILE has an invalid RATING_SCALE (must be 5 or 10)." >&2
    exit 1
fi

if [[ "$TOP_RATED_MODE" != "single" && "$TOP_RATED_MODE" != "random" ]]; then
    echo "Error: $CONFIG_FILE has an invalid TOP_RATED_MODE (must be single or random)." >&2
    exit 1
fi

# Main script logic: Handle different commands passed as arguments
case "$1" in
    "remove")     remove ;;       # Remove the current song from the queue
    "flag_bad")   flag_bad ;;     # Flag the current song as "bad"
    "unflag_bad") unflag_bad ;;   # Clear the "bad" flag on the current song
    "random")     random ;;       # Jump to a random song in the queue
    "list_bad")   list_bad ;;     # List all songs marked as "bad"
    "rate")     # Handle song rating
        # Ensure the rating argument is provided
        if [[ -z "$2" ]]; then
            echo "Please provide a rating between 0 and $RATING_SCALE."
            exit 1
        fi
        rate "$2" ;;             # Call the rate function with the provided rating
    "ratings")    ratings "$2" ;; # List ratings for all songs, optionally scoped to a directory
    "rescale")  # Convert all stored ratings from one scale to another
        if [[ -z "$2" || -z "$3" ]]; then
            echo "Usage: rescale <old-scale> <new-scale>"
            exit 1
        fi
        rescale "$2" "$3" ;;
    "top_rated")  top_rated ;;    # Jump to a top-rated song
    *)            usage ;;        # Display usage information if an invalid command is provided
esac
