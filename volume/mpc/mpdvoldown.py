#!/usr/bin/env python3

"""
Decrease MPD volume using mpc command-line tool.

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
    - mpc command-line tool (https://musicpd.org/doc/html/user.html#mpc)
"""

import os
import sys
import subprocess
import configparser

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
        'host': config['MPD'].get('host', 'localhost'),
        'port': int(config['MPD'].get('port', '6600')),
        'password': config['MPD'].get('password', ''),
        'toggleMaxVolume': config['MPD-SCRIPTS'].getboolean('toggleMaxVolume', fallback=False),
        'maxVolume': int(config['MPD-SCRIPTS'].get('maxVolume', 80))
    }
    return mpd_config

def mpc_env(mpd_config):
    """
    Builds the environment mpc reads its connection settings from
    (MPD_HOST/MPD_PORT), so volume.conf's host/port/password are actually
    honored instead of silently falling back to mpc's own defaults. The
    password travels via MPD_HOST's "password@host" form rather than a
    -P/--password flag, so it doesn't show up in `ps` output.
    """
    env = os.environ.copy()
    host = mpd_config['host']
    env['MPD_HOST'] = f"{mpd_config['password']}@{host}" if mpd_config['password'] else host
    env['MPD_PORT'] = str(mpd_config['port'])
    return env

def get_current_volume(env):
    """
    Function to retrieve the current volume level from MPD using mpc command.

    Returns:
    - Current volume level as an integer.
    """
    try:
        output = subprocess.check_output(["mpc", "volume"], env=env).decode().strip()
        current_volume = int(output.split()[1].strip("%"))
        return current_volume
    except Exception as e:
        print(f"Error: {e}")
        return None

def main():
    # Read MPD server configuration from volume.conf
    mpd_config = read_config()
    toggle_max_volume = mpd_config['toggleMaxVolume']
    max_volume = mpd_config['maxVolume']
    env = mpc_env(mpd_config)

    # If no arguments provided, show usage and current volume
    if len(sys.argv) == 1:
        current_volume = get_current_volume(env)
        if current_volume is not None:
            print(f"usage: {sys.argv[0]} [-h] [amount]\nCurrent volume: {current_volume}%")
        sys.exit(0)

    # Determine volume amount
    if len(sys.argv) > 1:
        volume_amount = sys.argv[1]
    else:
        volume_amount = "5"  # Default volume decrease amount

    # Retrieve current volume
    current_volume = get_current_volume(env)
    if current_volume is None:
        sys.exit(1)

    # Decrease volume
    try:
        subprocess.run(["mpc", "volume", f"-{volume_amount}"], env=env)
        print(f"Volume decreased by {volume_amount} units.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()

