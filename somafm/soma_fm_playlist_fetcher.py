#!/usr/bin/env python3

"""
Homelab SomaFM Playlist Fetcher

This script fetches the playlist URLs of SomaFM channels with the highest quality in MP3 format and creates separate playlists for each channel in extended M3U format with the channel name, along with each channel's icon image.

Dependencies:
    - requests: HTTP library for Python (https://requests.readthedocs.io)
"""

import argparse
import os
import requests
from requests.exceptions import HTTPError

# SomaFM's channels.json exposes each channel's icon at three sizes, keyed
# by these JSON field names.
ICON_SIZES = {
    120: 'image',
    256: 'largeimage',
    512: 'xlimage',
}


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
    Extracts the playlist URLs with the highest quality in MP3 format, and each
    channel's icon URL, from the response.

    Args:
        response (requests.Response): The response object containing the channel list.

    Returns:
        dict: A dictionary containing channel names as keys, and a dict of
        'urls' (playlist URLs) and 'icon_urls' (by size) as values.
    """
    playlists = {}  # Store channel playlists
    for channel in response.json()['channels']:
        channel_name = channel['title']
        for playlist in channel['playlists']:
            if playlist['quality'] == 'highest' and playlist['format'] == 'mp3':
                if channel_name not in playlists:
                    playlists[channel_name] = {'urls': [], 'icon_urls': {}}
                playlists[channel_name]['urls'].append(playlist['url'])

        for size, field in ICON_SIZES.items():
            icon_url = channel.get(field)
            if icon_url:
                playlists[channel_name]['icon_urls'][size] = icon_url

    return playlists


def download_icon(channel_name, icon_url, folder):
    """
    Downloads a channel's icon image and saves it alongside its playlist.

    Args:
        channel_name (str): The name of the channel.
        icon_url (str): The URL of the icon image to download.
        folder (str): The folder to save the icon image in.

    Returns:
        str: The icon's file name (relative to folder), or None if the
        download failed.
    """
    image_ext = os.path.splitext(icon_url)[1] or '.png'
    file_name = f"{channel_name}{image_ext}"
    try:
        response = requests.get(icon_url)
        response.raise_for_status()
    except HTTPError as http_err:
        print(f'HTTP error downloading icon for {channel_name}:\n {http_err}')
        return None
    except Exception as err:
        print(f'Other error downloading icon for {channel_name}: {err}')
        return None

    with open(os.path.join(folder, file_name), 'wb') as f:
        f.write(response.content)

    return file_name


def create_playlist_file(channel_name, channel_data, folder, icon_size):
    """
    Creates a playlist file in extended M3U format for the given channel,
    downloading and referencing its icon image if available.

    Args:
        channel_name (str): The name of the channel.
        channel_data (dict): 'urls' (playlist URLs) and 'icon_urls' (by size).
        folder (str): The folder to save the playlist file and icon in.
        icon_size (int): Which icon size (120, 256, or 512) to download.
    """
    icon_url = channel_data['icon_urls'].get(icon_size)
    icon_file_name = download_icon(channel_name, icon_url, folder) if icon_url else None

    file_name = os.path.join(folder, f"{channel_name}.m3u")
    with open(file_name, 'w') as f:
        f.write(f"#EXTM3U\n#EXTINF:-1,{channel_name}\n")
        if icon_file_name:
            f.write(f"#EXTIMG:{icon_file_name}\n")
        for url in channel_data['urls']:
            f.write(f"{url}\n")


def main():
    parser = argparse.ArgumentParser(description='Fetch SomaFM channel playlists and icons.')
    parser.add_argument('-s', '--size', type=int, choices=sorted(ICON_SIZES), default=120,
                         help='Channel icon size in pixels to download (default: 120)')
    args = parser.parse_args()

    folder = "playlists"
    if not os.path.exists(folder):
        os.makedirs(folder)

    url = "https://somafm.com/channels.json"
    response = get_channels(url)
    channel_playlists = get_playlists(response)

    for channel_name, channel_data in channel_playlists.items():
        create_playlist_file(channel_name, channel_data, folder, args.size)


if __name__ == "__main__":
    main()

