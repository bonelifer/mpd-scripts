# mpd-random-album

Clears the current MPD queue and replaces it with a randomly selected collection of complete albums, then starts playback.

## Features

- Selects random unique album/album-artist combinations, using exact matching (`mpc find`, not `mpc search`) so similarly-named albums (e.g. `The Wall` vs. `The Wall (Remastered)`) don't get conflated
- Resolves every selected album *before* touching the existing queue -- nothing is modified until the whole selection succeeds (or degrades gracefully with `--force`)
- Saves the original queue and playback state (random/repeat/single/consume, play state, song position) beforehand, and restores it automatically if anything fails partway through
- Verifies the resulting queue actually contains what was intended before starting playback
- Dry-run mode to preview what would be selected without changing anything
- Distinct exit codes for scripting: `0` full success, `2` partial success, `1` failure, `130`/`143` on interrupt/terminate

## Requirements

- `mpc`
- `awk`, `shuf` (standard on virtually all Linux distros)

## Usage

```bash
mpd-random-album.sh [OPTIONS] [ALBUM_COUNT]
```

| Option | Description |
| --- | --- |
| `-d`, `--dry-run` | Select and resolve albums without changing the queue |
| `-f`, `--force` | Skip albums that fail to resolve instead of aborting the run |
| `-q`, `--quiet` | Suppress informational messages |
| `-h`, `--help` | Show help |

`ALBUM_COUNT` defaults to `DEFAULT_ALBUM_COUNT` from the config file if not given.

### Examples

```bash
mpd-random-album.sh              # one random album
mpd-random-album.sh 5             # five random albums
mpd-random-album.sh --quiet 3
mpd-random-album.sh --dry-run 10
mpd-random-album.sh --force 5     # don't abort if one of the 5 has vanished from the library
```

## Configuration

Settings live in `~/.config/mpd-scripts/mpd-random-album/mpd-random-album.conf`, seeded automatically from [`mpd-random-album.conf.example`](./mpd-random-album.conf.example) the first time you run the script. Edit the copy there, not the template.

| Setting | Description | Default |
| --- | --- | --- |
| `DEFAULT_ALBUM_COUNT` | Number of albums selected when `ALBUM_COUNT` isn't given | `1` |
| `QUIET` | Suppress informational messages by default | `false` |
| `DRY_RUN` | Select/resolve without changing the queue, by default | `false` |
| `FORCE` | Skip failed albums instead of aborting, by default | `false` |

Each setting can still be overridden per invocation with its corresponding flag.

## Behavior on album resolution failure

By default, if a selected album can't be resolved (e.g. it was removed from the library between selection and resolution), the run **aborts** and the original queue/state is restored -- nothing is left half-changed. Pass `--force` (or set `FORCE=true` in the config) to skip unresolvable albums instead and continue with whatever did resolve, exiting `2` if that means fewer albums were added than requested.

## Acknowledgments

Derived from `RandAlbum` in [Alejandro-Roldan/mpc-scripts](https://github.com/Alejandro-Roldan/mpc-scripts).

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
