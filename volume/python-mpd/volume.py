#!/usr/bin/env python3
"""
volume.py

Description:
    This script adjusts the volume of an MPD (Music Player Daemon) server based on the command-line argument provided ('up' or 'down') and an optional value.
    It connects to the MPD server using the configuration specified in 'mpd.conf', authenticates if a password is provided, and then adjusts the volume accordingly.
    Finally, it prints a message indicating the volume change and disconnects from the MPD server.

Usage:
    python volume.py [up [<amount>] | down [<amount>]]

Arguments:
    up: Increase the volume. Optionally specify the amount to increase.
    down: Decrease the volume. Optionally specify the amount to decrease.

Examples:
    python volume.py up 10
        Increases the volume of the MPD server by 10 units.
    python volume.py down 5
        Decreases the volume of the MPD server by 5 units.
"""

import os
import sys
import argparse
from mpd import MPDClient

def read_config():
    """
    Function to read MPD configuration from mpd.conf file.
    
    Returns:
    - Dictionary containing MPD configuration.
    """
    mpd_conf_paths = [
        "/etc/mpd.conf",
        "/etc/mpd/mpd.conf",
        "/usr/local/etc/mpd.conf",
        "~/.mpdconf",
        "~/.config/mpd/mpd.conf"
    ]

    for path in mpd_conf_paths:
        full_path = os.path.expanduser(path)
        if os.path.isfile(full_path):
            with open(full_path, 'r') as f:
                config_lines = f.readlines()
            config_dict = {}
            for line in config_lines:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    config_dict[key.strip()] = value.strip()
            return config_dict

    print("MPD configuration file (mpd.conf) not found in common locations.")
    sys.exit(1)

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description='Adjust MPD volume.')
    parser.add_argument('direction', choices=['up', 'down'], help='Direction to adjust volume (up or down)')
    parser.add_argument('amount', nargs='?', type=int, default=5, help='Amount by which to adjust volume')
    args = parser.parse_args()

    # Read MPD server configuration from mpd.conf
    mpd_config = read_config()
    mpd_server = mpd_config.get('bind_to_address', 'localhost')
    mpd_port = int(mpd_config.get('port', '6600'))
    mpd_pass = mpd_config.get('password', '')

    # Connect to MPD server
    client = MPDClient()
    client.connect(mpd_server, mpd_port)

    # Authenticate
    if mpd_pass:
        client.password(mpd_pass)

    # Adjust volume based on command-line argument
    try:
        if args.direction == 'up':
            client.volume(f'+{args.amount}')  # Increase volume by specified amount
            print(f"Volume increased by {args.amount} units.")
        elif args.direction == 'down':
            client.volume(f'-{args.amount}')  # Decrease volume by specified amount
            print(f"Volume decreased by {args.amount} units.")
    except Exception as e:
        print(f"Error: {e}")

    # Disconnect from MPD server
    client.close()
    client.disconnect()

if __name__ == "__main__":
    main()

