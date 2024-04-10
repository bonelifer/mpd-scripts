#!/usr/bin/env python3

"""
Adjust MPD volume using mpc command-line tool.

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
    - mpc command-line tool (https://musicpd.org/doc/html/user.html#mpc)
"""

import os
import sys
import argparse
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
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description='Adjust MPD volume.')
    parser.add_argument('direction', nargs='?', choices=['up', 'down'], help='Direction to adjust volume (up or down)')
    parser.add_argument('amount', nargs='?', type=int, default=5, help='Amount by which to adjust volume')
    args = parser.parse_args()

    # Read MPD server configuration from mpd-extended.cfg
    mpd_config = read_config()
    toggle_max_volume = mpd_config['toggleMaxVolume']
    max_volume = mpd_config['maxVolume']

    # If no arguments provided, show usage and current volume
    if not args.direction:
        try:
            current_volume = int(subprocess.getoutput("mpc volume").split()[0])
            print(f"usage: {sys.argv[0]} [-h] {{up,down}} [amount]\nCurrent volume: {current_volume}%")
        except Exception as e:
            print(f"Error: {e}")
        sys.exit(0)

    # Adjust volume based on command-line argument
    try:
        if args.direction == 'up':
            if toggle_max_volume:
                current_volume = int(subprocess.getoutput("mpc volume").split()[0])
                new_volume = min(current_volume + args.amount, max_volume)
                subprocess.run(f"mpc volume {new_volume}", shell=True)
                print(f"Volume increased by {new_volume - current_volume} units.")
            else:
                subprocess.run(f"mpc volume +{args.amount}", shell=True)
                print(f"Volume increased by {args.amount} units.")
        elif args.direction == 'down':
            subprocess.run(f"mpc volume -{args.amount}", shell=True)
            print(f"Volume decreased by {args.amount} units.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()

