#!/usr/bin/env python3
"""
MPD Volume Control

This script connects to an MPD server and increases the volume by 5 units. 
It also provides an option to edit the script.

Dependencies:
- configparser
- subprocess
- MPDClient from mpd

Usage:
python script.py

"""

import configparser
import subprocess
from mpd import MPDClient

def edit_script(scriptname):
    """
    Function to open the script in an editor for editing.
    """
    try:
        subprocess.run(["nano", scriptname])
    except Exception as e:
        print(f"Error: {e}")

def main():
    config = configparser.ConfigParser()
    config.read('config.ini')

    mpd_server = config['MPD']['SERVER']
    mpd_port = int(config['MPD']['MPD_PORT'])
    mpd_pass = config['MPD']['MPDPASS']

    scriptname = __file__

    edit_command = input("Do you want to edit the script? (y/n): ")
    if edit_command.lower() == 'y':
        edit_script(scriptname)

    # Connect to MPD server
    client = MPDClient()
    client.connect(mpd_server, mpd_port)

    # Authenticate
    client.password(mpd_pass)

    # Increase volume
    try:
        client.volume('+5')  # Increase volume by 5 units
        print("Volume increased by 5 units.")
    except Exception as e:
        print(f"Error: {e}")
    
    # Disconnect from MPD server
    client.close()
    client.disconnect()

if __name__ == "__main__":
    main()

