# add-current-song

Adds the currently playing MPD song to an M3U playlist.

## Features

- Creates the playlist (and optionally its parent directory) if it doesn't exist
- Prevents duplicate entries by default, with an option to allow them
- Optionally removes existing duplicate entries and/or sorts the playlist alphabetically
- Optionally strips blank lines and normalizes Windows CRLF line endings
- Detects MPD communication failures and reports diagnostics instead of failing silently
- Rejects extended M3U files (`#EXTM3U`/`#EXTINF`) rather than risking corrupting them, since this script's line-based sorting/dedup logic isn't extended-M3U-aware
- Uses a lock (`flock`) to prevent concurrent modifications, with a configurable timeout
- Rewrites the playlist via an atomic temp-file replacement, preserving the original file's permissions
- Cleans up temporary files if interrupted

## Requirements

- `mpc`
- `flock` (util-linux; present by default on virtually all Linux distros)

## Usage

```bash
add-current-song.sh /path/to/playlist.m3u
add-current-song.sh --help
```

## Configuration

Settings live in `~/.config/mpd-scripts/add-current-song/add-current-song.conf`, seeded automatically from [`add-current-song.conf.example`](./add-current-song.conf.example) the first time you run the script. Edit the copy there, not the template.

| Setting | Description | Default |
| --- | --- | --- |
| `SORT_PLAYLIST` | Sort the playlist alphabetically after adding a song | `true` |
| `CREATE_DIRECTORY` | Create the playlist's parent directory if it doesn't exist | `true` |
| `ALLOW_DUPLICATES` | Allow the current song to be added even if it's already in the playlist | `false` |
| `REMOVE_EXISTING_DUPLICATES` | Remove duplicate entries already present in the playlist | `false` |
| `REMOVE_BLANK_LINES` | Remove blank/whitespace-only lines when the playlist is rewritten | `false` |
| `NORMALIZE_CRLF` | Convert CRLF line endings to Unix LF | `true` |
| `MPD_FORMAT` | Format string passed to `mpc` to identify the current song ([format syntax and placeholders](https://www.musicpd.org/doc/mpc/html/)) | `%file%` |
| `VERBOSE` | Show status messages, not just errors | `true` |
| `REQUIRE_M3U_EXTENSION` | Require the playlist filename to end in `.m3u` or `.m3u8` | `true` |
| `LOCK_TIMEOUT` | Seconds to wait for the playlist lock (`0` = fail immediately if locked) | `5` |

## Acknowledgments

Derived from `AddSongToFavsPlaylist` in [Alejandro-Roldan/mpc-scripts](https://github.com/Alejandro-Roldan/mpc-scripts).

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
