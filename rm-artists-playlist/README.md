# Artist Remover

This script removes songs by a list of artists from a saved MPD playlist or from the current MPD queue, and can also list the playlists MPD knows about. It's the artist-based counterpart to [`rm-duplicates-playlist`](../rm-duplicates-playlist/), sharing the same playlist/queue/list mode design.

## Features

- **Playlist mode (`-p`)**: Removes the listed artists' songs from a named, already-saved MPD playlist in place.
- **Queue mode (`-q`)**: Saves the current queue to a temporary playlist, removes the listed artists' songs, then clears and reloads the queue with the result and resumes playback.
- **List mode (`-l`)**: Lists all playlists MPD knows about, so you can find the name to pass to `-p`.
- Backs up the playlist file (`.bak`) before writing changes, and makes no changes at all if none of the listed artists appear in the playlist.
- Cleans up its temporary queue-mode playlist on exit, even on error.

## Requirements

- `mpc`

## Matching behavior (read this before using it)

Artist matching is an **unanchored, case-insensitive substring match** against each playlist entry's full file path, not an exact artist-tag match. A saved `.m3u` is just a flat list of file paths — once a playlist is on disk, there's no separate artist/album/title field left to match against, only the path string.

This means: **use full, specific artist names in your artist file.** A short or common name (e.g. `Air`) can match unrelated paths that merely contain that substring somewhere — another artist, an album title, even a track title (e.g. `Fair Warning`, `Air Supply`, `Repair Man`). This script does not attempt to anchor matches to a particular path segment, so the responsibility for precise names is on the artist list you provide.

**Blank lines in the artist file are ignored** (skipped before the match pattern is built). This matters: without that filtering, a blank line would produce an empty alternative in the underlying regex, which matches *every line* — silently removing the entire playlist or queue instead of just the named artists' songs.

## Configuration

Settings live in `~/.config/rm-artists-playlist/rm-artists-playlist.conf`, seeded automatically from [`rm-artists-playlist.conf.example`](./rm-artists-playlist.conf.example) the first time you run `-p` or `-q` (`-l` doesn't need it). Edit the copy in `~/.config/rm-artists-playlist/`, not the template.

- `PLAYLIST_DIR`: directory where MPD playlists are stored. **Must match MPD's own `playlist_directory`** — `mpc save`/`load`/`rm` operate through MPD's own config, independent of this value, which is only used to read/write playlist files directly.
- `ARTIST_FILE`: plain text file listing one artist name per line, to remove.

The script won't run `-p`/`-q` until both have been changed from their placeholder values.

## Usage

```bash
./rm-artists-playlist.sh [-v] (-p <playlist_name> | -q | -l)
```

- `-p`, `--playlist NAME`: Remove the listed artists' songs from the named playlist.
- `-q`, `--queue`: Remove the listed artists' songs from the current MPD queue.
- `-l`, `--list`: List all available MPD playlists and exit.
- `-v`, `--verbose`: Enable verbose output.
- `-h`, `--help`: Show usage and exit.

Exactly one of `-p`, `-q`, or `-l` must be given.

Example usage:

```bash
./rm-artists-playlist.sh -l
./rm-artists-playlist.sh -v -p my_playlist
./rm-artists-playlist.sh -q
```

## Example Output

```bash
Processing playlist: my_playlist
Original playlist has 42 songs.
Removed 5 songs.
Updated playlist has 37 songs.
Processing complete. Updated playlist saved as 'my_playlist'.
```

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
