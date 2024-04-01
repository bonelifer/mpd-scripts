#!/usr/bin/env python3

"""
update-mpd-extended-cfg.py

Description:
This script updates the mpd-extended.cfg file with configuration values extracted from the mpd.conf file.
If mpd.conf is not found in the default locations, the script prompts the user to enter the path manually.
The script then extracts relevant configuration values such as music_directory, playlist_directory, log_file, port, and password from mpd.conf.
These values are then updated in the mpd-extended.cfg file located at ~/.config/mpd/mpd-extended.cfg.
If any value is missing or cannot be extracted, appropriate warnings are displayed.

"""
import os

def update_mpd_extended_cfg(mpd_conf_path):
    mpd_extended_cfg_path = os.path.expanduser('~/.config/mpd/mpd-extended.cfg')

    # Read values from mpd.conf
    mpd_conf_values = {}
    with open(mpd_conf_path, 'r') as f:
        in_audio_output_section = False
        for line in f:
            if 'audio_output' in line and not line.startswith('#'):
                in_audio_output_section = True
            elif in_audio_output_section and not line.strip():  # End of audio output section
                in_audio_output_section = False
            elif not line.startswith('#'):  # Ignore commented lines
                if 'music_directory' in line:
                    try:
                        mpd_conf_values['music_directory'] = line.split('"')[1]
                    except IndexError:
                        print("Warning: Couldn't extract music_directory from mpd.conf")
                elif 'playlist_directory' in line:
                    try:
                        mpd_conf_values['playlist_directory'] = line.split('"')[1]
                    except IndexError:
                        print("Warning: Couldn't extract playlist_directory from mpd.conf")
                elif 'log_file' in line:
                    try:
                        mpd_conf_values['log_file'] = line.split('"')[1]
                    except IndexError:
                        print("Warning: Couldn't extract log_file from mpd.conf")
                elif 'port' in line and not in_audio_output_section:
                    try:
                        mpd_conf_values['port'] = line.split('"')[1]
                    except IndexError:
                        print("Warning: Couldn't extract port from mpd.conf")
                elif 'password' in line:
                    try:
                        mpd_conf_values['password'] = line.split('"')[1]
                    except IndexError:
                        print("Warning: Couldn't extract password from mpd.conf")

    # Update values in mpd-extended.cfg
    with open(mpd_extended_cfg_path, 'r') as cfg_file:
        lines = cfg_file.readlines()

    with open(mpd_extended_cfg_path, 'w') as cfg_file:
        for line in lines:
            if line.startswith('music_directory') and 'music_directory' in mpd_conf_values:
                line = f"music_directory = {mpd_conf_values['music_directory']}\n"
            elif line.startswith('playlist_directory') and 'playlist_directory' in mpd_conf_values:
                line = f"playlist_directory = {mpd_conf_values['playlist_directory']}\n"
            elif line.startswith('log_file') and 'log_file' in mpd_conf_values:
                line = f"log_file = {mpd_conf_values['log_file']}\n"
            elif line.startswith('port') and 'port' in mpd_conf_values:
                line = f"port = {mpd_conf_values['port']}\n"
            elif line.startswith('password') and 'password' in mpd_conf_values:
                line = f"password = {mpd_conf_values['password']}\n"
            cfg_file.write(line)

def main():
    # Check if MPD is installed
    if not os.path.exists('/etc/mpd.conf'):
        print("MPD is not installed or configuration file not found.")
        return

    # Search for mpd.conf in default locations
    mpd_conf_locations = [
        '/etc/mpd.conf',
        '~/.mpd/mpd.conf',
        '~/.config/mpd/mpd.conf'
    ]
    for location in mpd_conf_locations:
        mpd_conf_path = os.path.expanduser(location)
        if os.path.exists(mpd_conf_path):
            break
    else:
        print("MPD configuration file not found in default locations.")
        mpd_conf_path = input("Please enter the path to your MPD configuration file: ")

    # Update mpd-extended.cfg
    update_mpd_extended_cfg(mpd_conf_path)
    print("MPD Extended Configuration File updated successfully.")

if __name__ == "__main__":
    main()


