# MPD Smart Shuffle

A smarter shuffle for [MPD](https://www.musicpd.org/). `monitor.py` runs in the background and records play history (last-played time, skip counts, play counts) as tracks actually play; `randomtrack.py` (run periodically via cron) uses that history to top up the MPD queue with tracks that haven't played recently, while dodging out-of-season holiday music, respecting exclude lists, favoring new additions, and more - all individually toggleable. `db_admin.py` is a small maintenance CLI for the underlying database.

## Features

- Avoids re-queueing anything played or queued within a configurable `min_replay_days` window, tracked both as MPD stickers and in a local LMDB database.
- **Weighted selection**: tracks past the cutoff aren't all equally eligible - the longer since last played, the more likely to get picked.
- **Skip detection**: `monitor.py` estimates how much of a track played before it changed and down-weights frequently-skipped tracks.
- **Artist/album diversity**: won't queue the same artist, or a track off the same album, twice within a configurable window.
- **New-music boost**: recently-added tracks (by file mtime) surface more often instead of getting diluted into a large library.
- **Rating weighting**: biases toward tracks with a higher MPD `rating` sticker (set by clients like ncmpcpp), if you use one.
- **Seasonal filtering**: config-driven, e.g. holding back Christmas music outside the holidays - supports fixed dates, computed holidays (Thanksgiving, Memorial Day, etc.), and Easter-relative dates.
- **Time-of-day / day-of-week profiles**: restrict selection to specific genres during recurring windows (e.g. upbeat music on weekday mornings).
- **Exclude lists**: permanently skip specific files, artists, or genres.
- **Low-eligible-tracks alert**: optional notification (via [apprise](https://github.com/caronc/apprise)) when `randomtrack.py` can't reach its target after exhausting its attempts.
- **Play counts**: tracked per track in LMDB; see `db_admin.py stats`.
- **Spread insertion**: new picks land at random positions in the queue instead of always appending at the tail.
- **Dry-run mode** (`randomtrack.py --dry-run`): preview what would be queued without touching MPD or the databases.

Every feature above (except dry-run, which is a per-invocation flag) is a `true`/`false` switch under `[features]` in the config - see [Configuration](#configuration).

## Requirements

- MPD, with `sticker_file` configured in `mpd.conf` (stickers are how this stores per-track history in MPD itself, alongside its own LMDB database)
- Python 3
- [`python-mpd2`](https://pypi.org/project/python-mpd2/), [`lmdb`](https://pypi.org/project/lmdb/), [`mutagen`](https://pypi.org/project/mutagen/), [`python-dateutil`](https://pypi.org/project/python-dateutil/)
- Optional: [`apprise`](https://pypi.org/project/apprise/), only if you enable the `low_eligible_alert` notification

## Installation

Run [`./install.sh`](./install.sh) (or let the root [`../install.sh`](../install.sh) offer it for you). It:

1. Installs the required Python dependencies (and optionally `apprise`).
2. Copies `client.py`, `db.py`, `paths.py`, `monitor.py`, `randomtrack.py`, `db_admin.py`, and the `.example` config/list templates to `~/bin`.
3. Offers to install `monitor.py` as an optional `systemd --user` background service (see [`install-systemd.sh`](./install-systemd.sh) / [`mpd-smart-shuffle-monitor.service`](./mpd-smart-shuffle-monitor.service)) - not required; `randomtrack.py` and `db_admin.py` work fine without it, but recency-based selection (`weighted_selection`, `min_replay_days`, etc.) needs `monitor.py` running to actually build up play history.

`config.ini` and the exclude/notify list files get seeded automatically, the first time any of the three scripts runs, from their `.example` templates into `~/.config/mpd-scripts/mpd-smart-shuffle/` - edit the copies there, not the templates. **Set `music_dir` before running `randomtrack.py` for real** - it must match MPD's own `music_directory`, since tracks are queued by path relative to it.

## Usage

```bash
monitor.py                  # start the background monitor (foreground; use a service manager to keep it running)
monitor.py -k                # stop a running monitor started this way
randomtrack.py [COUNT]       # top up the queue to COUNT tracks (default: config's default_playlist_length)
randomtrack.py -n [COUNT]    # --dry-run: log what would be queued without changing anything
```

Add `randomtrack.py` to your crontab to run it periodically:

```cron
@hourly /home/youruser/bin/randomtrack.py >> ~/.local/state/mpd-smart-shuffle/randomtrack.log 2>&1
```

## Configuration

Settings live in `~/.config/mpd-scripts/mpd-smart-shuffle/config.ini`, seeded from [`config.ini.example`](./config.ini.example) on first run:

```ini
[mpd]
host = localhost
port = 6600
password =

[paths]
music_dir = /path/to/your/music
db_file = status.lmdb

[behavior]
min_replay_days = 31
default_playlist_length = 100
skip_threshold = 0.5
diversity_window = 5
new_music_days = 30
new_music_weight = 3.0
rating_scale_max = 10

[features]
weighted_selection = true
skip_detection = true
artist_diversity = true
album_diversity = true
seasonal_filters = true
time_profiles = true
exclude_list = true
low_eligible_alert = true
play_counts = true
new_music_boost = true
rating_weighting = true
spread_insertion = true

[exclude]
files = exclude_files.txt
artists = exclude_artists.txt
genres = exclude_genres.txt

[notify]
enabled = false
urls = notify_urls.txt

[season:christmas]
genres = christmas,holiday,xmas
start = 4th-thu-of-nov+1
end = 01-15
```

`db_file` and the `[exclude]`/`[notify]` list-file values resolve relative to `~/.local/state/mpd-smart-shuffle/` and `~/.config/mpd-scripts/mpd-smart-shuffle/` respectively (not the install directory) unless given as absolute paths.

### Season date syntax

A `[season:<name>]` block's `start`/`end` value can be written three ways:

**1. A fixed date** — `MM-DD`, e.g. `10-31` for Halloween.

**2. The Nth (or last) weekday of a month** — for holidays that move every year but follow a fixed rule, like Thanksgiving or Memorial Day:

```
<nth>-<weekday>-of-<month>[+N|-N]
```

| Placeholder | Allowed values |
|---|---|
| `<nth>` | `1st`, `2nd`, `3rd`, `4th`, `last` |
| `<weekday>` | `mon`, `tue`, `wed`, `thu`, `fri`, `sat`, `sun` |
| `<month>` | `jan`, `feb`, `mar`, `apr`, `may`, `jun`, `jul`, `aug`, `sep`, `oct`, `nov`, `dec` |
| `[+N\|-N]` | optional, a whole number of days to shift the result by |

Examples:

| Spec | Resolves to |
|---|---|
| `4th-thu-of-nov` | Thanksgiving (US) |
| `4th-thu-of-nov+1` | Black Friday |
| `1st-mon-of-sep` | Labor Day |
| `3rd-mon-of-jan` | MLK Day |
| `2nd-sun-of-may` | Mother's Day |
| `last-mon-of-may` | Memorial Day |

**3. Easter, or an offset from it** — `easter`, or `easter+N` / `easter-N`:

| Spec | Resolves to |
|---|---|
| `easter` | Easter Sunday |
| `easter-46` | Ash Wednesday |
| `easter-7` | Palm Sunday |
| `easter-2` | Good Friday |
| `easter+1` | Easter Monday |

`start` and `end` don't have to use the same form - `[season:christmas]` mixes a computed `start` (`4th-thu-of-nov+1`) with a fixed `end` (`01-15`). If `end` falls before `start` in the same calendar year, it's treated as falling in the next year. A literal `02-29` falls back to `02-28` on non-leap years.

### Time profile syntax

`[profile:<name>]` sections (used by `time_profiles`) restrict selection to a genre list during a recurring day/time window:

```ini
[profile:morning]
genres = upbeat,pop,electronic
days = mon,tue,wed,thu,fri
start_time = 06:00
end_time = 10:00
```

| Key | Format |
|---|---|
| `genres` | comma-separated, same matching rules as `[season:*]` |
| `days` | comma-separated `mon`/`tue`/`wed`/`thu`/`fri`/`sat`/`sun` |
| `start_time` / `end_time` | `HH:MM`, 24-hour |

Only one profile is active at a time (the first match wins if you define overlapping ones). While a profile is active, a track with no `GENRE` tag is always allowed through; a track *with* a `GENRE` tag is only allowed if it matches the active profile's `genres`. Outside of any profile's window, there's no restriction at all.

If a window crosses midnight (`start_time` later than `end_time`), list both calendar days it touches in `days`:

```ini
[profile:late_night]
genres = ambient,chill,jazz
days = fri,sat
start_time = 22:00
end_time = 02:00
```

## Database maintenance (`db_admin.py`)

```bash
# Back up all tracked LMDB data to a text file
db_admin.py backup -o status_backup.txt

# Write a compacted copy of the database (does not touch the live db -
# stop monitor.py/randomtrack.py and swap it in manually if you want to
# replace the original)
db_admin.py compact -o status_compacted.lmdb

# Show most/least played tracks (requires play_counts to be enabled)
db_admin.py stats -n 10
```

## Logging

`monitor.py` logs to `~/.local/state/mpd-smart-shuffle/monitor.log` (and the console, or `journalctl --user -u mpd-smart-shuffle-monitor.service` if installed as a systemd service). `randomtrack.py` and `db_admin.py` log to the console only - redirect output yourself (e.g. the cron example above) if you want a persistent log.

## Troubleshooting

- **Nothing ever gets queued / everything looks "recently played"**: check that `monitor.py` is actually running and connected to the same MPD instance - `weighted_selection`, `skip_detection`, and the recency checks all depend on it having built up history.
- **`randomtrack.py` gives up before reaching the target count**: the library may not have enough eligible tracks for the current `min_replay_days`/feature settings - check the log for "Giving up after N attempts", lower `min_replay_days`, or enable `low_eligible_alert` to get notified instead of having to notice manually.
- **`music_dir` mismatch**: tracks are queued via paths relative to `music_dir`, which must match MPD's own `music_directory` in `mpd.conf` - a mismatch means files that exist per MPD's database still fail the `os.path.exists()` check and get silently skipped.

## Uninstallation

```bash
systemctl --user disable --now mpd-smart-shuffle-monitor.service 2>/dev/null
rm -f ~/.config/systemd/user/mpd-smart-shuffle-monitor.service
rm -f ~/bin/client.py ~/bin/db.py ~/bin/paths.py ~/bin/monitor.py ~/bin/randomtrack.py ~/bin/db_admin.py
rm -f ~/bin/config.ini.example ~/bin/exclude_files.txt.example ~/bin/exclude_artists.txt.example ~/bin/exclude_genres.txt.example ~/bin/notify_urls.txt.example
rm -rf ~/.local/state/mpd-smart-shuffle ~/.config/mpd-scripts/mpd-smart-shuffle
```

Also remove the `randomtrack.py` cron entry if you added one.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
