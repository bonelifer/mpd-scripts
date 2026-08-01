# Random Playlist Generator

This script generates a random playlist from a local music directory and saves it as an M3U playlist file in the specified playlist directory. The playlist is populated with tracks based on a set limit per artist, and if the number of filtered tracks is less than the target count, additional random tracks are added to meet the specified number of tracks. This prevents the playlist from being overwhelmed by artists in your collection who have more than the average number of albums.

## Features

- **Filter by Artist**: The script filters tracks by artist and limits how many tracks from each artist are included.
- **Random Track Selection**: If the filtered list is smaller than the desired number of tracks, the script fills the playlist with additional random tracks from the music directory.
- **Playlist Management**: If the playlist already exists in MPC, it will be removed before creating a new one.
- **Tool Installation, with confirmation**: The script checks for required utilities (`mpc`, `awk`, `shuf`, and `ripgrep`/`parallel` unless `--fallback` is used) and offers to install any that are missing before proceeding.

## Requirements

- `mpc`
- `awk`, `shuf` (present on virtually any Linux system by default)
- `ripgrep`, `parallel` (optional, used for faster filtering unless `--fallback` is passed)

If any of these are missing, the script will offer to install them via `apt` (confirming first, unless `-y`/`--yes` is passed).

## Configuration

Settings live in `~/.config/mpd-scripts/mpd-queue-shuffle/mpd-queue-shuffle.conf`, seeded automatically from [`mpd-queue-shuffle.conf.example`](./mpd-queue-shuffle.conf.example) the first time you run the script. Edit the copy in `~/.config/mpd-scripts/mpd-queue-shuffle/`, not the template.

- `MUSIC_DIR`: local music directory containing MP3 files -- must match MPD's own `music_directory` so the generated playlist's paths resolve correctly.
- `PLAYLIST_DIR`: directory where `mpc` saves/loads playlists (MPD's `playlist_directory`).
- `DEFAULT_TARGET_TRACK_COUNT`: number of tracks in the playlist when `-c` isn't passed. Default `16000`.
- `DEFAULT_PLAYLIST_NAME`: playlist name when `-p` isn't passed. Default `random_playlist`.

The script won't run until `MUSIC_DIR`/`PLAYLIST_DIR` have been changed from their placeholder values.

## Usage

You can customize the playlist by specifying the target number of tracks and the playlist name using the following options:

- `-c TRACK_COUNT`: Set the number of tracks in the playlist (e.g., `-c 20000`).
- `-p PLAYLIST_NAME`: Set the name of the playlist (e.g., `-p my_playlist`).
- `-f`, `--fallback`: Use `grep`/`shuf` instead of `ripgrep`/`parallel`, even if the latter are installed.
- `-y`, `--yes`: Install any missing required tools without prompting first.

If `-c`/`-p` aren't provided, the script uses `DEFAULT_TARGET_TRACK_COUNT`/`DEFAULT_PLAYLIST_NAME` from the config file.

Example usage:

```bash
./mpd-queue-shuffle.sh -c 15000 -p my_custom_playlist
```

## Example Output

```bash
Random playlist of 15000 tracks created and saved as 'random_playlist'.
```

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
