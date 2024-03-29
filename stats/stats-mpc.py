#!/usr/bin/env python3
"""
Music Stats Recorder

This script records statistics about the music library, such as the number and size of files,
and MPD server stats. It appends the data to a file specified in the music library directory.

Dependencies:
- os
- subprocess
- datetime
- pathlib
- sys

Usage:
python stats.py

"""

import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

def read_mpd_config():
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
            config = {}
            with open(full_path, 'r') as f:
                for line in f:
                    if '=' in line:
                        key, value = line.strip().split('=', 1)
                        config[key.strip()] = value.strip()
            return config

    print("MPD configuration file (mpd.conf) not found in common locations.")
    sys.exit(1)

# Read MPD server configuration from mpd.conf
mpd_config = read_mpd_config()
music_library = mpd_config.get('music_directory', '/var/lib/mpd/music')
mpd_host = mpd_config.get('bind_to_address', 'localhost')
mpd_port = mpd_config.get('port', '6600')
mpd_password = mpd_config.get('password', '')  # Read password from mpd.conf

# Get MPD server stats using mpc with authentication
if mpd_password:
    mpc_stats = subprocess.check_output(["mpc", f"-h{mpd_host}:{mpd_port}", f"-p{mpd_password}", "stats"]).decode()
else:
    mpc_stats = subprocess.check_output(["mpc", f"-h{mpd_host}:{mpd_port}", "stats"]).decode()

stats = os.path.join(music_library, "stats")

date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
with open(stats, "a") as f:
    f.write(date + "\n")
    f.write(mpc_stats + "\n\n")
    f.write(".flac files found in library:\t{}\t{}\n".format(
        len(list(Path(music_library).rglob("*.flac"))),
        sum(f.stat().st_size for f in Path(music_library).rglob("*.flac"))
    ))
    f.write(".mp3 files found in library: \t{}\t{}\n".format(
        len(list(Path(music_library).rglob("*.mp3"))),
        sum(f.stat().st_size for f in Path(music_library).rglob("*.mp3"))
    ))
    f.write(".opus files found in library: \t{}\t{}\n".format(
        len(list(Path(music_library).rglob("*.opus"))),
        sum(f.stat().st_size for f in Path(music_library).rglob("*.opus"))
    ))
    f.write(".ogg files found in library: \t{}\t{}\n".format(
        len(list(Path(music_library).rglob("*.ogg"))),
        sum(f.stat().st_size for f in Path(music_library).rglob("*.ogg"))
    ))
    f.write(".mp4 files found in library: \t{}\t{}\n".format(
        len(list(Path(music_library).rglob("*.mp4"))),
        sum(f.stat().st_size for f in Path(music_library).rglob("*.mp4"))
    ))

print('-' * os.get_terminal_size().columns)
with open(stats, "r") as f:
    print(f.read())

