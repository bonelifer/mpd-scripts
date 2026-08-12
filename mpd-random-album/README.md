# mpd-random-album

Clears the current MPD queue and replaces it with a randomly selected collection of complete albums, then starts playback.

## Features

- Selects random unique album/album-artist combinations, using exact matching (`mpc find`, not `mpc search`) so similarly-named albums (e.g. `The Wall` vs. `The Wall (Remastered)`) don't get conflated -- including two *different artists'* albums that happen to share a title (e.g. two unrelated "Greatest Hits"), which are kept fully separate rather than treated as duplicates
- Optionally avoids re-picking any of the last `CACHE_SIZE` albums selected, remembered across runs, so consecutive invocations don't keep handing you the same few albums
- Optional `-y`/`--year` filter to restrict selection to albums with a track dated a given year, or within a year range
- Optional `-g`/`--genre` filter (case-insensitive substring match) to restrict selection to a genre
- Optional `-a`/`--artist` filter (exact match) to restrict selection to a specific album artist
- Optional `-p`/`--append` mode adds the selected albums to the end of the existing queue instead of replacing it, without disturbing current playback
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
| `-A`, `--allow-repeats` | Don't avoid recently-picked albums for this run, even if `AVOID_REPEATS` is on |
| `-a`, `--artist ARTIST` | Only select albums by `ARTIST` (exact match against the album artist) |
| `-d`, `--dry-run` | Select and resolve albums without changing the queue |
| `-f`, `--force` | Skip albums that fail to resolve instead of aborting the run |
| `-g`, `--genre GENRE` | Only select albums with a track whose genre contains `GENRE` (case insensitive) |
| `-p`, `--append` | Add the selected albums to the end of the existing queue instead of replacing it, without disturbing current playback |
| `-q`, `--quiet` | Suppress informational messages |
| `-y`, `--year YEAR` | Only select albums with a track dated `YEAR`, or a `YEAR-YEAR` range (e.g. `1970-1979`); a full `1975-06-12`-style date still matches a bare `1975` |
| `-h`, `--help` | Show help |

`ALBUM_COUNT` defaults to `DEFAULT_ALBUM_COUNT` from the config file if not given.

### Examples

```bash
mpd-random-album.sh              # one random album
mpd-random-album.sh 5             # five random albums
mpd-random-album.sh --quiet 3
mpd-random-album.sh --dry-run 10
mpd-random-album.sh --force 5     # don't abort if one of the 5 has vanished from the library
mpd-random-album.sh --year 1975 3      # three random albums with a track dated 1975
mpd-random-album.sh --year 1970-1979 3 # three random albums from that decade
mpd-random-album.sh --genre jazz 3     # three random albums tagged (or containing) "jazz"
mpd-random-album.sh --artist "Pink Floyd" 2 # two random albums by exactly "Pink Floyd"
mpd-random-album.sh --append 2         # add two random albums to the end of the queue, keep playing
mpd-random-album.sh --allow-repeats 1  # force a pick even if the whole pool is "recent"
```

## Configuration

Settings live in `~/.config/mpd-scripts/mpd-random-album/mpd-random-album.conf`, seeded automatically from [`mpd-random-album.conf.example`](./mpd-random-album.conf.example) the first time you run the script. Edit the copy there, not the template.

| Setting | Description | Default |
| --- | --- | --- |
| `DEFAULT_ALBUM_COUNT` | Number of albums selected when `ALBUM_COUNT` isn't given | `1` |
| `QUIET` | Suppress informational messages by default | `false` |
| `DRY_RUN` | Select/resolve without changing the queue, by default | `false` |
| `FORCE` | Skip failed albums instead of aborting, by default | `false` |
| `AVOID_REPEATS` | Avoid re-picking recently-selected albums by default | `true` |
| `CACHE_SIZE` | How many recently-picked albums to remember and avoid | `20` |
| `APPEND` | Add to the end of the existing queue instead of replacing it, by default | `false` |

Each setting can still be overridden per invocation with its corresponding flag.

## Behavior on album resolution failure

By default, if a selected album can't be resolved (e.g. it was removed from the library between selection and resolution), the run **aborts** and the original queue/state is restored -- nothing is left half-changed. Pass `--force` (or set `FORCE=true` in the config) to skip unresolvable albums instead and continue with whatever did resolve, exiting `2` if that means fewer albums were added than requested.

## Avoiding repeats

When `AVOID_REPEATS` is on (the default), each run excludes the last `CACHE_SIZE` albums picked -- recorded in `~/.cache/mpd-scripts/mpd-random-album/recent-albums.tsv`, keyed by the same exact `(albumartist, album)` pair used for selection and resolution, so two different artists' albums that happen to share a title are never confused with each other in the exclusion history either.

If excluding recent picks leaves too few albums to satisfy the requested count, that's treated exactly like an album vanishing from the library: it aborts and restores the original queue by default, or falls through to the usual partial-success/`--force` handling.

`-A`/`--allow-repeats` skips the exclusion for a single run without touching the config -- useful if the pool is nearly exhausted, or you just want to deliberately hear something recent again. Recording still happens afterward regardless of `-A`, so a normal (non-`-A`) run right after still correctly treats that album as "just played" rather than forgetting about it. Only permanently disabling `AVOID_REPEATS` in the config stops recording entirely.

A dry run (`-d`/`--dry-run`) never writes to the cache, since nothing was actually queued or played.

## Append mode

`-p`/`--append` (or `APPEND=true` in the config) adds the selected albums to the end of the existing queue instead of clearing and replacing it. Unlike the default mode, it never touches playback, the current song, or the random/repeat/single/consume settings -- it's meant for topping up the queue in the background without interrupting whatever's currently playing.

If a track fails to add partway through, only the tracks this run itself appended are removed; the pre-existing queue and playback are left exactly as they were, same as the default mode's own restore-on-failure guarantee.

## Acknowledgments

Derived from `RandAlbum` in [Alejandro-Roldan/mpc-scripts](https://github.com/Alejandro-Roldan/mpc-scripts). The recent-albums cache (`AVOID_REPEATS`/`CACHE_SIZE`/`-A`) was inspired by the equivalent feature in [ibeex/mpd_queue_random_album](https://github.com/ibeex/mpd_queue_random_album), reimplemented to key the cache by `(albumartist, album)` instead of the bare album title -- that project's version could conflate two different artists' albums sharing a common title (e.g. two unrelated "Greatest Hits") both in selection and in the recency cache, since it keyed and matched on album title alone.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
