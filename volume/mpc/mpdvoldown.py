#!/usr/bin/env python3

"""
Decrease MPD volume using mpc command-line tool.

This script allows you to decrease the volume of the Music Player Daemon (MPD) using the settings provided 
in the 'mpd-extended.cfg' configuration file. If the configuration file or its settings are not found, 
the script falls back to default values.

Usage:
    mpdvoldown.py [amount]

Arguments:
    amount      Amount by which to decrease volume

Examples:
    mpdvoldown.py 5     # Decrease volume by 5 units
    mpdvoldown.py 10    # Decrease volume by 10 units

Dependencies:
    - mpc command-line tool (https://musicpd.org/doc/html/user.html#mpc)
"""

import os
import sys
import subprocess
import configparser

def read_config():
    """
    Function to read MPD configuration from mpd-extended.cfg file.
    
    Returns:
    - Dictionary containing MPD configuration.
    """
    config = configparser.ConfigParser()
    mpd_extended_cfg_path = os.path.expanduser("~/.config/mpd/mpd-extended.cfg")
    if not os.path.isfile(mpd_extended_cfg_path):
        print(f"Error: MPD extended configuration file (mpd-extended.cfg) not found at {mpd_extended_cfg_path}")
        sys.exit(1)

    config.read(mpd_extended_cfg_path)
    mpd_config = {
        'SERVER': config['MPD-SCRIPTS'].get('server', 'localhost'),
        'MPD_PORT': int(config['MPD-SCRIPTS'].get('mpd_port', '6600')),
        'MPDPASS': config['MPD-SCRIPTS'].get('password', ''),
        'toggleMaxVolume': config['MPD-SCRIPTS'].getboolean('toggleMaxVolume', fallback=False),
        'maxVolume': int(config['MPD-SCRIPTS'].get('maxVolume', 80))
    }
    return mpd_config

def get_current_volume():
    """
    Function to retrieve the current volume level from MPD using mpc command.
    
    Returns:
    - Current volume level as an integer.
    """
    try:
        output = subprocess.check_output(["mpc", "volume"]).decode().strip()
        current_volume = int(output.split()[0].strip("%"))
        return current_volume
    except Exception as e:
        print(f"Error: {e}")
        return None

def main():
    # Read MPD server configuration from mpd-extended.cfg
    mpd_config = read_config()
    toggle_max_volume = mpd_config['toggleMaxVolume']
    max_volume = mpd_config['maxVolume']

    # If no arguments provided, show usage and current volume
    if len(sys.argv) == 1:
        current_volume = get_current_volume()
        if current_volume is not None:
            print(f"usage: {sys.argv[0]} [-h] [amount]\nCurrent volume: {current_volume}%")
        sys.exit(0)

    # Determine volume amount
    if len(sys.argv) > 1:
        volume_amount = sys.argv[1]
    else:
        volume_amount = "5"  # Default volume decrease amount

    # Retrieve current volume
    current_volume = get_current_volume()
    if current_volume is None:
        sys.exit(1)

    # Decrease volume
    try:
        subprocess.run(["mpc", "volume", f"-{volume_amount}"])
        print(f"Volume decreased by {volume_amount} units.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()

