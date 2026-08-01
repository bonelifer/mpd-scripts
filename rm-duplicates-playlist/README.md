# Playlist/Queue Duplicate Remover

This script removes duplicate entries (matched by file path, case-insensitively) from a saved MPD playlist or from the current MPD queue, and can also list the playlists MPD knows about. It combines what the two [`mpd-find-dup`](../mpd-find-dup/) scripts each do separately into a single tool, and adds a `.bak` backup of the playlist before it's modified.

## Features

- **Playlist mode (`-p`)**: Deduplicates a named, already-saved MPD playlist in place.
- **Queue mode (`-q`)**: Saves the current queue to a temporary playlist, deduplicates it, then clears and reloads the queue with the cleaned result and resumes playback.
- **List mode (`-l`)**: Lists all playlists MPD knows about, so you can find the name to pass to `-p`.
- Backs up the playlist file (`.bak`) before writing changes, and makes no changes at all if no duplicates are found.
- Cleans up its temporary queue-mode playlist on exit, even on error.

## Requirements

- `mpc`
- `awk`

## Configuration

Settings live in `~/.config/mpd-scripts/rm-duplicates-playlist/rm-duplicates-playlist.conf`, seeded automatically from [`rm-duplicates-playlist.conf.example`](./rm-duplicates-playlist.conf.example) the first time you run `-p` or `-q` (`-l` doesn't need it). Edit the copy in `~/.config/mpd-scripts/rm-duplicates-playlist/`, not the template.

- `PLAYLIST_DIR`: directory where MPD playlists are stored. **Must match MPD's own `playlist_directory`** — `mpc save`/`load`/`rm` operate through MPD's own config, independent of this value, which is only used to read/write playlist files directly.

The script won't run `-p`/`-q` until `PLAYLIST_DIR` has been changed from its placeholder value.

## Usage

```bash
./rm-duplicates-playlist.sh [-v] (-p <playlist_name> | -q | -l)
```

- `-p`, `--playlist NAME`: Remove duplicates from the named playlist.
- `-q`, `--queue`: Remove duplicates from the current MPD queue.
- `-l`, `--list`: List all available MPD playlists and exit.
- `-v`, `--verbose`: Enable verbose output.
- `-h`, `--help`: Show usage and exit.

Exactly one of `-p`, `-q`, or `-l` must be given.

Example usage:

```bash
./rm-duplicates-playlist.sh -l
./rm-duplicates-playlist.sh -v -p my_playlist
./rm-duplicates-playlist.sh -q
```

## Example Output

```bash
Processing playlist: my_playlist
Original playlist has 42 entries.
Removed 3 duplicate(s).
Updated playlist has 39 entries.
Processing complete. Updated playlist saved as 'my_playlist'.
```

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
