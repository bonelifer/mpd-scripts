#!/usr/bin/env python3


"""
Adjust MPD volume using python-mpd library.

This script allows you to adjust the volume of the Music Player Daemon (MPD) using the settings provided 
in the 'mpd-extended.cfg' configuration file. If the configuration file or its settings are not found, 
the script falls back to default values.

Usage:
    volume.py [direction] [amount]

Arguments:
    direction   Direction to adjust the volume (up or down)
    amount      Amount by which to adjust volume

Examples:
    volume.py up 5      # Increase volume by 5 units
    volume.py down 10   # Decrease volume by 10 units

Note:
    If the 'toggleMaxVolume' setting is enabled in the configuration file, the script ensures that the 
    volume does not exceed the 'maxVolume' setting when increasing the volume. Otherwise, it respects 
    the provided volume increase value.

Dependencies:
    - python-mpd library (https://python-mpd.readthedocs.io/en/latest/)
"""


import os
import sys
import argparse
from mpd import MPDClient
import configparser

def read_config():
    """
    Function to read MPD configuration from mpd.conf file.
    
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
        'volUp': int(config['MPD-SCRIPTS'].get('volUp', 5)),
        'volDown': int(config['MPD-SCRIPTS'].get('volDown', 5)),
        'toggleMaxVolume': config['MPD-SCRIPTS'].getboolean('toggleMaxVolume', fallback=False),
        'maxVolume': int(config['MPD-SCRIPTS'].get('maxVolume', 80)),
        'host': config['MPD'].get('HOST', 'localhost'),
        'port': int(config['MPD'].get('PORT', '6600')),
        'password': config['MPD'].get('PASSWORD', '')
    }
    return mpd_config

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description='Adjust MPD volume.')
    parser.add_argument('direction', choices=['up', 'down'], help='Direction to adjust volume (up or down)')
    parser.add_argument('amount', nargs='?', type=int, default=5, help='Amount by which to adjust volume')
    args = parser.parse_args()

    # Read MPD configuration from mpd-extended.cfg
    mpd_config = read_config()
    toggle_max_volume = mpd_config['toggleMaxVolume']
    max_volume = mpd_config['maxVolume']
    host = mpd_config['host']
    port = mpd_config['port']
    password = mpd_config['password']

    # Connect to MPD server
    client = MPDClient()
    client.connect(host, port)

    # Authenticate if password is provided
    if password:
        client.password(password)

    # Get current volume
    current_volume = int(client.status().get('volume', 0))

    # Adjust volume based on command-line argument
    if args.direction == 'up':
        if toggle_max_volume:
            # Check if increasing volume would exceed maxVolume
            new_volume = min(current_volume + args.amount, max_volume)
            client.setvol(new_volume)
            print(f"Volume increased by {new_volume - current_volume} units.")
        else:
            client.volume(f'+{args.amount}')  # Increase volume by specified amount
            print(f"Volume increased by {args.amount} units.")
    elif args.direction == 'down':
        client.volume(f'-{args.amount}')  # Decrease volume by specified amount
        print(f"Volume decreased by {args.amount} units.")

    # Disconnect from MPD server
    client.close()
    client.disconnect()

if __name__ == "__main__":
    main()

