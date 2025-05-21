#!/usr/bin/bash

# Script: MPD Duplicate Removal
# Purpose: This script identifies and removes duplicate entries from an MPD playlist.
# It finds the first duplicate based on file names, and removes it from the playlist.
# The script continues removing duplicates until there are no more left.
#
# Functions:
# 1. mpd_first_duplicate: Identifies the position of the first duplicate file in the playlist.
# 2. mpd_delete_duplicates: Loops through the playlist and deletes duplicates using the first function.
#
# Usage:
# Run this script in an environment where MPD (Music Player Daemon) and MPC (Music Player Client) are installed and configured.
# It will automatically search for duplicates and remove them.

# Function: mpd_first_duplicate
# Purpose: This function searches the playlist for the first duplicate entry based on the file name.
# Input: None
# Output: Position of the first duplicate item or empty if no duplicates are found.
mpd_first_duplicate(){
  # Check if the playlist is empty by using 'mpc playlist' and searching for any output
  if ! mpc playlist | grep -q .; then
    echo "Playlist is empty."  # Inform the user if the playlist has no items
    return  # Exit the function if the playlist is empty
  fi

  # List the playlist with position and file path, then process it with awk
  # - Position is stored in 'pos', and file name is used to track duplicates.
  # - When a file appears more than once, its position is printed and the function exits.
  mpc -f "%position% \t %file%" playlist | awk '{
    pos=$1          # Store the position of the current song
    $1=""            # Remove the position from the line
    map[$0]=map[$0]+1 # Increment the count for the current file
    if (map[$0] > 1) {  # If a duplicate is found (count > 1)
      print pos       # Print the position of the duplicate
      exit            # Exit after finding the first duplicate
    }
  }'
}

# Function: mpd_delete_duplicates
# Purpose: This function calls mpd_first_duplicate to find and delete duplicate entries in the playlist.
# Input: None
# Output: None. It deletes duplicate items directly from the playlist.
mpd_delete_duplicates(){
  while true; do
    # Get the position of the first duplicate
    item="$(mpd_first_duplicate)"
    
    # Exit the loop if no duplicate is found (empty result)
    if [ -z "$item" ]; then
      echo "No more duplicates found."  # Inform the user when no duplicates remain
      break  # Exit the loop when no more duplicates are found
    fi
    
    # Log and delete the duplicate item at the given position
    echo "Deleting duplicate at position $item..."  # Provide feedback on deletion
    mpc del "$item"  # Remove the song from the playlist using mpc
  done
}

# Call the function to delete duplicates from the playlist
mpd_delete_duplicates

