# Random Track Adder

This script adds a random selection of tracks from the local music library to the current MPD queue.

## Features

- Adds a configurable number of random tracks (`-t`/`--tracks`, default `10`) from anywhere in the library, not tied to a specific artist (see [`mpd-add-random-artist`](../mpd-add-random-artist/) for that).
- Matches `.mp3`, `.flac`, `.ogg`, `.m4a`, `.opus`, `.wav`, `.wma`, and `.aac` files.
- Follows symlinks, so a symlinked audio file or directory inside the music library is included rather than silently skipped.
- A track that fails to add is reported as a warning rather than aborting the whole run — the rest still get added.

## Requirements

- `mpc`
- `find`, `shuf` (present on virtually any Linux system by default)

## Configuration

Settings live in `~/.config/mpd-scripts/mpd-add-random/mpd-add-random.conf`, seeded automatically from [`mpd-add-random.conf.example`](./mpd-add-random.conf.example) the first time you run the script. Edit the copy in `~/.config/mpd-scripts/mpd-add-random/`, not the template.

- `MUSIC_DIR`: local music library path. **Must match MPD's own `music_directory`** — tracks are queued via `mpc add` using paths relative to this directory, which only resolve correctly in MPD if this matches its own config.

The script won't run until `MUSIC_DIR` has been changed from its placeholder value.

## Usage

```bash
./mpd-add-random.sh [-t NUMBER]
```

- `-t`, `--tracks NUMBER`: Number of random tracks to add (default: `10`).
- `-h`, `--help`: Show usage and exit.

Example usage:

```bash
./mpd-add-random.sh -t 5    # Adds 5 random tracks to the queue
./mpd-add-random.sh         # Defaults to 10 random tracks
```

## Example Output

```bash
Added 5 random tracks to the queue.
```

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
