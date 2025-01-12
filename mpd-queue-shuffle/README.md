# Random Playlist Generator

This script generates a random playlist from a local music directory and saves it as an M3U playlist file in the specified playlist directory. The playlist is populated with tracks based on a set limit per artist, and if the number of filtered tracks is less than the target count, additional random tracks are added to meet the specified number of tracks. This prevents the playlist from being overwhelmed by artists in your collection who have more than the average number of albums.

## Features

- **Filter by Artist**: The script filters tracks by artist and limits how many tracks from each artist are included.
- **Random Track Selection**: If the filtered list is smaller than the desired number of tracks, the script fills the playlist with additional random tracks from the music directory.
- **Playlist Management**: If the playlist already exists in MPC, it will be removed before creating a new one.
- **Automatic Tool Installation**: The script checks for required utilities (`mpc`, `awk`, `shuf`, `ripgrep`, `parallel`) and installs them if they are missing.



## Usage

You can customize the playlist by specifying the target number of tracks and the playlist name using the following options:

- `-c` : Custom number of tracks in the playlist (e.g., `-c 20000`).
- `-p` : Custom playlist name (e.g., `-p my_playlist`).

If no options are provided, the script defaults to creating a playlist with 16,000 tracks named `random_playlist`.

### Command Line Options

- `-c TRACK_COUNT`: Set the number of tracks in the playlist. Default is 16,000.
- `-p PLAYLIST_NAME`: Set the name of the playlist. Default is `random_playlist`.
- `--fallback`: Use basic tools (`grep` and `shuf`) instead of `ripgrep` and `parallel`.

Example usage:

```bash
./mpd-queue-shuf.sh -c 15000 -p my_custom_playlist
```

## Example Output

```bash
Random playlist of 15000 tracks created and saved as 'random_playlist'.
```

## Prerequisites

Before running the script, ensure that the following utilities are installed:

- `mpc` (Music Player Client)
- `awk` (Text processing tool)
- `shuf` (Shuffling command)
- `ripgrep` (Search tool, optional for better performance)
- `parallel` (For parallel processing, optional for better performance)

If any of these tools are missing, the script will attempt to install them automatically.

## Setup

1. **Configure the Music Directory**:
   - Set the `MUSIC_DIR` variable to point to your local music directory containing MP3 files.
   - Example:
     ```bash
     MUSIC_DIR="/path/to/your/music/directory/"
     ```

2. **Configure the Playlist Directory**:
   - Set the `PLAYLIST_DIR` variable to the path where MPC saves its playlists.
   - Example:
     ```bash
     PLAYLIST_DIR="/path/to/your/mpc/playlists/directory/"
     ```

3. **Install Required Tools**:
   - The script will automatically check for and install the following utilities if they are not already installed:
     - `mpc`, `awk`, `shuf`, `ripgrep`, `parallel`.

#### License: [GPLv3](../LICENSE)
