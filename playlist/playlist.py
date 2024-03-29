#!/usr/bin/env python3
"""
MPD Playlist Viewer

This script connects to an MPD server and displays information about the current song
and the playlist. It also allows for adjusting the playlist display window with an offset.

Dependencies:
- os
- sys
- time
- mpd

Usage:
python script.py [offset]

Args:
- Optionally, specify an offset to adjust the playlist display window. If not provided, the default offset is 10.

Example:
python script.py 5
"""

import os
import sys
import time
import mpd

bold = '\033[1m'
normal = '\033[0m'

# Function to read MPD configuration from mpd.conf file
def read_config():
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

# Function to connect to MPD
def connect_mpd(server, port, password):
    client = mpd.MPDClient()
    client.connect(server, port)
    client.password(password)
    return client

# Function to display the playlist
def display_playlist(client, plpos, offset):
    headoffset = offset
    tailoffset = offset

    print("\nCurrent song:")
    current = client.currentsong()
    print(f"{bold}{current.get('title', 'Unknown')} on {current.get('album', 'Unknown')} by {current.get('artist', 'Unknown')}{normal}\n")

    if plpos - offset <= 0:
        tailoffset = plpos
        print(f"{bold}<< Start of Playlist >>{normal}")

    print("\nPlaylist:")
    playlist = client.playlistinfo()
    for song in playlist[max(0, plpos - offset):min(plpos + offset, len(playlist))]:
        print(f"{song['pos']} {song.get('title', 'Unknown')} by {song.get('artist', 'Unknown')}")

    print("\nNext up:")
    next_song = playlist[plpos + 1] if plpos + 1 < len(playlist) else None
    if next_song:
        print(f"{next_song['title']} by {next_song['artist']} on {next_song['album']}")
    else:
        print("No more songs in the playlist.")

# Function to handle viewing the playlist
def view_playlist(offset):
    mpd_config = read_config()
    client = connect_mpd(mpd_config.get('bind_to_address', 'localhost'), int(mpd_config.get('port', '6600')), mpd_config.get('password', ''))
    plpos = int(client.status()["song"])
    display_playlist(client, plpos, offset)
    client.close()
    client.disconnect()

def main():
    if len(sys.argv) > 1:
        offset = int(sys.argv[1])
        view_playlist(offset)
    else:
        view_playlist(10)

if __name__ == "__main__":
    main()

