# SomaFM Playlist Fetcher

This Python script fetches the playlist URLs of SomaFM channels with the highest quality in MP3 format and creates separate playlists for each channel in extended M3U format with the channel name included, along with each channel's icon image.

## Dependencies

- Python 3.x
- requests: HTTP library for Python (https://requests.readthedocs.io)

## Usage

1. Clone the repository or download the `soma_fm_playlist_fetcher.py` file.
2. Ensure you have Python installed on your system.
3. Install the `requests` library if you haven't already:

   ```
   pip install requests
   ```

4. Run the script:

   ```
   python soma_fm_playlist_fetcher.py
   ```

   Each channel's icon is downloaded at 120px by default; pass `--size` to choose 256px or 512px instead:

   ```
   python soma_fm_playlist_fetcher.py --size 512
   ```

5. The script will create a folder named `playlists` in the current directory and save individual M3U playlists and icon images for each SomaFM channel in that folder.

## File Structure

- `soma_fm_playlist_fetcher.py`: The Python script to fetch and create SomaFM playlists.
- `README.md`: This README file providing instructions and information about the script.
- `playlists/`: Folder containing the generated M3U playlist files and channel icon images for each SomaFM channel.

***
#### License: [GPLv3](../LICENSE)