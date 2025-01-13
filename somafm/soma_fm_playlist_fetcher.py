#!/usr/bin/env python3

"""
Homelab SomaFM Playlist Fetcher

This script fetches the playlist URLs of SomaFM channels with the highest quality in MP3 format and creates separate playlists for each channel in extended M3U format with the channel name.

Dependencies:
    - requests: HTTP library for Python (https://requests.readthedocs.io)
"""

import os
import requests
from requests.exceptions import HTTPError


def get_channels(url):
    """
    Fetches the list of SomaFM channels from the given URL.

    Args:
        url (str): The URL to fetch the channel list from.

    Returns:
        requests.Response: The response object containing the channel list.
    """
    try:
        response = requests.get(url)
        response.raise_for_status()

    except HTTPError as http_err:
        print(f'HTTP error occurred:\n {http_err}')
    except Exception as err:
        print(f'Other error occurred: {err}')
    
    return response


def get_playlists(response):
    """
    Extracts the playlist URLs with the highest quality in MP3 format from the response.

    Args:
        response (requests.Response): The response object containing the channel list.

    Returns:
        dict: A dictionary containing channel names as keys and playlist URLs as values.
    """
    playlists = {}  # Store channel playlists
    for channel in response.json()['channels']:
        channel_name = channel['title']
        for playlist in channel['playlists']:
            if playlist['quality'] == 'highest' and playlist['format'] == 'mp3':
                if channel_name not in playlists:
                    playlists[channel_name] = []
                playlists[channel_name].append(playlist['url'])

    return playlists


def create_playlist_file(channel_name, playlist_urls, folder="channels"):
    """
    Creates a playlist file in extended M3U format for the given channel.

    Args:
        channel_name (str): The name of the channel.
        playlist_urls (list): A list of playlist URLs for the channel.
        folder (str): The folder to save the playlist file.
    """
    file_name = os.path.join(folder, f"{channel_name}.m3u")
    with open(file_name, 'w') as f:
        f.write(f"#EXTM3U\n#EXTINF:-1,{channel_name}\n")
        for url in playlist_urls:
            f.write(f"{url}\n")


url = "https://somafm.com/channels.json"
response = get_channels(url)
channel_playlists = get_playlists(response)

# Create the channels folder if it does not exist
if not os.path.exists("channels"):
    os.makedirs("channels")

for channel_name, playlist_urls in channel_playlists.items():
    create_playlist_file(channel_name, playlist_urls)

