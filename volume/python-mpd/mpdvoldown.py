#!/usr/bin/env python3

"""
Decrease MPD volume using python-mpd library.

This script allows you to decrease the volume of the Music Player Daemon (MPD) using the settings provided 
in the 'volume.conf' configuration file. If the configuration file or its settings are not found, 
the script falls back to default values.

Usage:
    mpdvoldown.py [amount]

Arguments:
    amount      Amount by which to decrease volume

Examples:
    mpdvoldown.py 5     # Decrease volume by 5 units
    mpdvoldown.py 10    # Decrease volume by 10 units

Dependencies:
    - python-mpd library (https://python-mpd.readthedocs.io/en/latest/)
"""


import configparser
import os
import sys
from mpd import MPDClient

def read_config():
    """
    Function to read MPD configuration from volume.conf file.
    
    Returns:
    - Dictionary containing MPD configuration.
    """
    config = configparser.ConfigParser()
    volume_conf_path = os.path.expanduser("~/.config/mpd-scripts/volume/volume.conf")
    if not os.path.isfile(volume_conf_path):
        print(f"Error: MPD extended configuration file (volume.conf) not found at {volume_conf_path}")
        sys.exit(1)

    config.read(volume_conf_path)
    mpd_config = {
        'SERVER': config['MPD'].get('host', 'localhost'),
        'MPD_PORT': int(config['MPD'].get('port', '6600')),
        'MPDPASS': config['MPD'].get('password', '')
    }
    return mpd_config

def main():
    # Read MPD server configuration from volume.conf
    mpd_config = read_config()
    mpd_server = mpd_config['SERVER']
    mpd_port = mpd_config['MPD_PORT']
    mpd_pass = mpd_config['MPDPASS']

    # Connect to MPD server
    client = MPDClient()
    client.connect(mpd_server, mpd_port)

    # Authenticate
    if mpd_pass:
        client.password(mpd_pass)

    # Parse command-line arguments
    if len(sys.argv) > 1:
        amount = int(sys.argv[1])
    else:
        # If no arguments are provided, show usage and current volume
        current_volume = client.status().get('volume', 'Unknown')
        print(f"Usage: {sys.argv[0]} [amount]\nCurrent volume: {current_volume}")
        sys.exit(0)

    # Decrease volume
    try:
        client.volume(f'-{amount}')  # Decrease volume by specified amount
        print(f"Volume decreased by {amount} units.")
    except Exception as e:
        print(f"Error: {e}")
    
    # Disconnect from MPD server
    client.close()
    client.disconnect()

if __name__ == "__main__":
    main()

