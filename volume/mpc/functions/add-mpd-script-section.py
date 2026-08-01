#!/usr/bin/env python3

"""
add-mpd-script-section.py

Appends a [MPD-SCRIPTS] section (volume step sizes and the max-volume
toggle read by volume.py/mpdvolup.py/mpdvoldown.py) to mpd-extended.conf,
unless that section is already present. Run after
update-mpd-extended-cfg.py has populated the file's base MPD settings --
install.sh calls both in sequence.
"""

import os

MPD_EXTENDED_CONF_PATH = os.path.expanduser("~/.config/mpd-scripts/volume/mpd-extended.conf")


def add_mpd_scripts_section():
    """
    Appends a default [MPD-SCRIPTS] section to mpd-extended.conf, unless
    one is already present.
    """
    if not os.path.exists(MPD_EXTENDED_CONF_PATH):
        print(f"Error: {MPD_EXTENDED_CONF_PATH} not found.")
        return

    # Check if MPD-SCRIPTS section already exists
    with open(MPD_EXTENDED_CONF_PATH, 'r') as f:
        lines = f.readlines()
        for line in lines:
            if line.strip() == "[MPD-SCRIPTS]":
                print("MPD-SCRIPTS section already exists in mpd-extended.conf.")
                return

    # Add MPD-SCRIPTS section with or without a line break
    with open(MPD_EXTENDED_CONF_PATH, 'a') as f:
        if lines and lines[-1].strip():  # If last line is not empty, add a line break
            f.write("\n")
        f.write("[MPD-SCRIPTS]\n")
        f.write("volUp = 5\n")
        f.write("volDown = 5\n")
        f.write("toggleMaxVolume = False\n")
        f.write("maxVolume = 80\n")
        f.write("\n")

    print("MPD-SCRIPTS section added successfully to mpd-extended.conf.")

if __name__ == "__main__":
    add_mpd_scripts_section()
