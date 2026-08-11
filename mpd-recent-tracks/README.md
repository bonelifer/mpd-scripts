# MPD Recent Songs Playlist Creator

## Overview
This script **automatically generates a playlist** of songs **added or modified in the last X days** in your MPD library. It scans the configured music directory, finds recent files, and creates a new `.m3u` playlist, newest song first.

## Features
- **Customizable time range**: Specify the number of days via `-d/--days` (default: 30).
- **Newest-first ordering**: Songs are sorted by modification time, most recent first.
- **Optional size cap**: `-n/--limit` caps the playlist at N songs (still newest first).
- **Optional random sample**: `-r/--random` picks N songs at random from the recent-tracks pool instead of the newest N. Requires `shuf`; cannot be combined with `-n/--limit`.
- **Automatic playlist generation**: Finds recent music files and adds them to an `.m3u` playlist, with paths relative to `MUSIC_DIR` so MPD can resolve them.
- **Optional auto-load into MPD**: `-l/--load` runs `mpc load` on the generated playlist afterwards, leaving it paused unless `-p/--play` is also given.
- **Cron-friendly quiet mode**: `-q/--quiet` suppresses informational output; errors still print.
- **Configurable audio formats**: `EXTENSIONS` in the config controls which file extensions are scanned (default: `mp3 m4a flac ogg`).
- **Exclude patterns**: `exclude_paths.txt` lists glob patterns (relative to `MUSIC_DIR`) to skip, e.g. an entire `Podcasts/` folder.
- **Removes empty playlists**: If no new songs are found, the existing playlist is deleted. A failed run (e.g. a permission error) never touches an existing playlist — the new one is only swapped in once generation succeeds.
- **Named time-window presets**: `-P/--presets` generates one playlist per `PRESETS` entry in the config (e.g. a week/month/year set) in a single run, instead of one playlist per invocation.

## Requirements
- **MPD (Music Player Daemon)**
- **Bash (Linux/macOS)**
- **`find`** utility (with GNU-style `-printf` support)
- **`shuf`**, only if using `-r/--random`
- **`mpc`**, only if using `-l/--load`

## Configuration
On first run, a config file is created at
`~/.config/mpd-scripts/mpd-recent-tracks/mpd-recent-tracks.conf`, seeded
from `mpd-recent-tracks.conf.example`. Edit the copy there, not the
template, then run the script again.

| Variable           | Description                                                  | Default Value              |
|--------------------|----------------------------------------------------------------|-----------------------------|
| `PLAYLIST_DIR`     | Path to the MPD playlist directory                            | `/path/to/mpd/playlists`   |
| `MUSIC_DIR`        | Path to the music directory                                   | `/path/to/Music`           |
| `PLAYLIST_TITLE`   | Name of the generated playlist                                | `Recently Added`           |
| `DEFAULT_DAYS_OLD` | Default number of days if `-d/--days` isn't given             | `30`                       |
| `EXTENSIONS`       | Space-separated file extensions (no leading dot) to scan for  | `mp3 m4a flac ogg`         |
| `EXCLUDE_FILE`     | Exclude-patterns filename, resolved relative to the config dir| `exclude_paths.txt`        |
| `PRESETS`          | Array of `"NAME:DAYS"` entries used by `-P/--presets`         | see below                  |

### Playlist Location
- The single-playlist mode (no `-P`) writes to:
  ```
  [PLAYLIST_DIR]/[PLAYLIST_TITLE].m3u
  ```
- Each `-P/--presets` entry writes its own file instead:
  ```
  [PLAYLIST_DIR]/[NAME].m3u
  ```

### Presets
`PRESETS` is a bash array of `"NAME:DAYS"` strings, one per named playlist `-P/--presets` should generate:

```bash
PRESETS=(
    "New_Last_Week:7"
    "New_Last_Month:31"
    "New_Last_Year:365"
)
```

`NAME` becomes that entry's playlist title (avoid spaces in it -- use underscores, since it's split from `DAYS` on the first `:`); `DAYS` is that entry's own day count, independent of `DEFAULT_DAYS_OLD`. `-n/--limit`/`-r/--random` still apply, capping or sampling each generated playlist the same way they would in single-playlist mode. `-d/--days` and `-l/--load` can't be combined with `-P` -- day count comes from each preset individually, and there's no single resulting playlist for `-l/--load` to load.

### Excluding paths
`exclude_paths.txt` (seeded from `exclude_paths.txt.example` into the same
config directory as `mpd-recent-tracks.conf`) lists one glob pattern per
line, matched against each file's path relative to `MUSIC_DIR`:

```
# Exclude an entire top-level folder
Podcasts/*
# Exclude any "Live" subfolder one level down
*/Live/*
```

Lines starting with `#` and blank lines are ignored. Leave the file with
no active patterns to disable exclusion entirely.

## Usage
### Running the script:
```bash
./mpd-recent-tracks.sh [-d <days>] [-n <limit> | -r <count>] [-q] [-l [-p]]
./mpd-recent-tracks.sh -P [-n <limit> | -r <count>] [-q]
```

### Available Options
- **-d, --days N**: Number of days to look back for recently added/modified files. If not given, uses `DEFAULT_DAYS_OLD` from the config. Errors if combined with `-P/--presets`.
- **-n, --limit N**: Cap the playlist at N songs (newest first). With `-P/--presets`, applies to each generated playlist.
- **-r, --random N**: Pick N songs at random from the recent-tracks pool, instead of the newest N. Requires `shuf`. Errors if combined with `-n/--limit`.
- **-P, --presets**: Generate one playlist per `PRESETS` entry from the config instead of a single playlist. Errors if combined with `-d/--days` or `-l/--load`.
- **-q, --quiet**: Suppress informational output; only errors are printed.
- **-l, --load**: Load the generated playlist into MPD via `mpc load` after creating it. Requires `mpc`. Playback is left paused unless `-p/--play` is also given. Errors if combined with `-P/--presets`.
- **-p, --play**: With `-l/--load`, also start playback via `mpc play` after loading. Errors if given without `-l/--load`.
- **-h, --help**: Show usage and exit.

### Example Commands:
- **Generate a playlist for songs added in the last 10 days**:
  ```bash
  ./mpd-recent-tracks.sh -d 10
  ```
- **Use the configured default days**:
  ```bash
  ./mpd-recent-tracks.sh
  ```
- **Cap it at the 20 newest songs**:
  ```bash
  ./mpd-recent-tracks.sh -n 20
  ```
- **Pick 20 random songs from the recent-tracks pool**:
  ```bash
  ./mpd-recent-tracks.sh -r 20
  ```
- **Generate and load into MPD paused, suitable for a cron job**:
  ```bash
  ./mpd-recent-tracks.sh -q -l
  ```
- **Generate, load, and start playing immediately**:
  ```bash
  ./mpd-recent-tracks.sh -l -p
  ```
- **Generate the week/month/year preset playlists in one run**:
  ```bash
  ./mpd-recent-tracks.sh -P
  ```
- **Same, capped at 50 songs each**:
  ```bash
  ./mpd-recent-tracks.sh -P -n 50
  ```

## Error Handling
- On first run, or if `PLAYLIST_DIR`/`MUSIC_DIR` in the config are still the placeholder values, the script exits with an error telling you to edit the config.
- If the playlist or music directories don't exist, the script exits with an error.
- If `find` fails partway through (e.g. a permission error on a subdirectory), the script reports the failure and leaves any existing playlist untouched.
- If no recent songs are found (and the scan itself succeeded), the existing playlist is deleted.

## Example Output
```bash
Created the 'Recently Added' playlist with 42 songs at /path/to/mpd/playlists/Recently Added.m3u.
```

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
