#!/usr/bin/env python3
"""
Music Stats Recorder

This script records statistics about the music library, such as the number and size of files,
and MPD server stats. It also provides extended statistics including the duration of audio and video files.

Dependencies:
- os
- datetime
- pathlib
- mpd
- moviepy.editor
- pydub.utils.mediainfo
- mutagen

Usage:
python stats.py [-e|--extended]

Optional arguments:
  -e, --extended   Include extended statistics with audio and video file durations.

"""

import os
import sys
from datetime import datetime
from pathlib import Path
import mpd
from moviepy.editor import VideoFileClip
from pydub.utils import mediainfo
from mutagen.mp3 import MP3
from mutagen.mp4 import MP4
from mutagen.flac import FLAC
from mutagen.oggvorbis import OggVorbis
from mutagen.m4a import M4A
from mutagen.oggopus import OggOpus

# Function to read MPD configuration from mpd.conf file
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

# Connect to MPD server
client = mpd.MPDClient()
client.connect(host=mpd_host, port=int(mpd_port))
if mpd_password:
    client.password(mpd_password)

# Get MPD server stats
mpd_stats = client.stats()

# Function to get duration of audio/video file
def get_duration(filename):
    """
    Function to get the duration of an audio or video file.
    """
    try:
        # Get file extension
        _, ext = os.path.splitext(filename)

        # Check file type and extract duration accordingly
        if ext.lower() == ".mp3":
            audio = MP3(filename)
            duration = audio.info.length
        elif ext.lower() == ".mp4":
            video = VideoFileClip(filename)
            duration = video.duration
        elif ext.lower() == ".flac":
            audio = FLAC(filename)
            duration = audio.info.length
        elif ext.lower() == ".ogg":
            audio = OggVorbis(filename)
            duration = audio.info.length
        elif ext.lower() == ".m4a":
            audio = M4A(filename)
            duration = audio.info.length
        elif ext.lower() == ".wma":
            # Use mediainfo from pydub for WMA files
            info = mediainfo(filename)
            duration = float(info["duration"]) / 1000.0
        elif ext.lower() == ".avi":
            # Use moviepy for AVI files
            video = VideoFileClip(filename)
            duration = video.duration
        elif ext.lower() == ".opus":
            audio = OggOpus(filename)
            duration = audio.info.length
        else:
            # Exclude unsupported file types
            return 0

        return duration
    except Exception as e:
        print(f"Error getting duration of {filename}: {e}")
        return 0

# Function to format time
def format_time(seconds):
    """
    Function to convert seconds to human-readable format (days, hours, minutes, seconds).
    """
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    return f"{int(days)} days, {int(hours)} hours, {int(minutes)} minutes, {int(seconds)} seconds"

# Function to get total duration of files
def get_total_duration(base_dir):
    """
    Function to get the total duration of audio and video files in a directory.
    """
    total_duration = 0
    filetype_durations = {}
    for root, dirs, files in os.walk(base_dir):
        for file in files:
            filename = os.path.join(root, file)
            duration = get_duration(filename)
            if duration > 0:
                total_duration += duration
                _, ext = os.path.splitext(filename)
                if ext.lower() not in filetype_durations:
                    filetype_durations[ext.lower()] = duration
                else:
                    filetype_durations[ext.lower()] += duration
    return total_duration, filetype_durations

# Check for extended option
extended = '-e' in sys.argv or '--extended' in sys.argv

stats_file = os.path.join(music_library, "stats")

date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
with open(stats_file, "a") as f:
    f.write(date + "\n")
    f.write(str(mpd_stats) + "\n\n")
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

    # Add extended info if requested
    if extended:
        total_duration, filetype_durations = get_total_duration(music_library)
        f.write("\nTotal duration of all valid audio and video files: {}\n".format(format_time(total_duration)))
        f.write("Per-filetype durations:\n")
        for ext, duration in filetype_durations.items():
            f.write(f"  {ext}: {format_time(duration)}\n")

print('-' * os.get_terminal_size().columns)
with open(stats_file, "r") as f:
    print(f.read())

# Close MPD connection
client.close()
client.disconnect()

