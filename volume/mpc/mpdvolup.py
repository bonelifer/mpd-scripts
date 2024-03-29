#!/usr/bin/env python3
"""
mpdvolup.py

Description:
    This script increases the volume of an MPD (Music Player Daemon) server by a specified amount (default: 5 units).
    It connects to the MPD server using the configuration specified in 'mpd.conf', authenticates if a password is provided, and then adjusts the volume accordingly using the `mpc` command line interface.
    Finally, it prints a message indicating the volume change and disconnects from the MPD server.

Usage:
    python mpdvolup.py [amount]

Arguments:
    amount: Optional. Specifies the amount by which to increase the volume. Default is 5 units.

Examples:
    python mpdvolup.py
        Increases the volume of the MPD server by 5 units.
    python mpdvolup.py 10
        Increases the volume of the MPD server by 10 units.
"""

import os
import sys
import subprocess

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

