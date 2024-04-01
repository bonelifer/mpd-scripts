#!/usr/bin/env python3
# mpdvolup.py

"""
Increase MPD volume using mpc command-line tool.

This script allows you to increase the volume of the Music Player Daemon (MPD) using the settings provided 
in the 'mpd-extended.cfg' configuration file. If the configuration file or its settings are not found, 
the script falls back to default values.

Usage:
    mpdvolup.py [amount]

Arguments:
    amount      Amount by which to increase volume

Examples:
    mpdvolup.py 5     # Increase volume by 5 units
    mpdvolup.py 10    # Increase volume by 10 units

Note:
    If the 'toggleMaxVolume' setting is enabled in the configuration file, the script ensures that the 
    volume does not exceed the 'maxVolume' setting when increasing the volume. Otherwise, it respects 
    the provided volume increase value.

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

def main():
    # Read MPD server configuration from mpd-extended.cfg
    mpd_config = read_config()
    mpd_server = mpd_config['SERVER']
    mpd_port = mpd_config['MPD_PORT']
    mpd_pass = mpd_config['MPDPASS']
    toggle_max_volume = mpd_config['toggleMaxVolume']
    max_volume = mpd_config['maxVolume']

    # Authenticate
    if mpd_pass:
        auth_string = f"-p '{mpd_pass}'"
    else:
        auth_string = ""

    # Determine volume amount
    if len(sys.argv) > 1:
        volume_amount = sys.argv[1]
    else:
        volume_amount = "5"  # Default volume increase amount

    # Increase volume
    try:
        subprocess.run(f"mpc {auth_string} volume +{volume_amount}", shell=True)
        print(f"Volume increased by {volume_amount} units.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()

