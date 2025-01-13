```
# SomaFM Playlist Fetcher

This Python script fetches the playlist URLs of SomaFM channels with the highest quality in MP3 format and creates separate playlists for each channel in extended M3U format with the channel name included.

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

5. The script will create a folder named `channels` in the current directory and save individual M3U playlists for each SomaFM channel in that folder.

## File Structure

- `soma_fm_playlist_fetcher.py`: The Python script to fetch and create SomaFM playlists.
- `README.md`: This README file providing instructions and information about the script.
- `channels/`: Folder containing the generated M3U playlist files for each SomaFM channel.

## License

This project is licensed under the [MIT License](LICENSE).
```
