#!/usr/bin/env python3
"""
mpdvoldown.py

Description:
    This script decreases the volume of an MPD (Music Player Daemon) server by a specified amount.
    It connects to the MPD server using the configuration specified in 'mpd.conf', authenticates if a password is provided, 
    and then decreases the volume by the specified amount.
    Finally, it prints a message indicating the volume change and disconnects from the MPD server.

Usage:
    python mpdvoldown.py [amount]

Arguments:
    amount: The amount by which to decrease the volume. Must be a positive integer.

Example:
    python mpdvoldown.py 10
        Decreases the volume of the MPD server by 10 units.
"""

import os
import sys
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

    # Handle command-line arguments
    if len(sys.argv) > 1:
        amount = int(sys.argv[1])
        try:
            client.volume(f'-{amount}')  # Decrease volume by specified amount
            print(f"Volume decreased by {amount} units.")
        except Exception as e:
            print(f"Error: {e}")
    else:
        print("Please specify the amount by which to decrease the volume.")

    # Disconnect from MPD server
    client.close()
    client.disconnect()

if __name__ == "__main__":
    main()

