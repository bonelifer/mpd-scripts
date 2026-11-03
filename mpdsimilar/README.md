# MPD Similar Artist Fetcher

This script fetches similar artists from Last.fm for the currently playing track (`-c`) or for every track already in the MPD queue (`-a`), matches those artists against your local library, and adds a random sample of their tracks to the queue.

## Features

- Fetches similar artists from Last.fm for the current track or every queued track.
- Matches similar artists against your local MPD library with exact (case-insensitive) tag matching, avoiding substring false positives.
- Deduplicates and shuffles candidate tracks before adding them to the queue.
- Respects a configurable Last.fm rate limit and a hard cap on MPD playlist size.
- `-s`/`--shuffle` to shuffle the queue after adding new tracks.
- `-i`/`--install` to install any missing required tools via `apt-get`.
- An on/off switch for pausing it (for example, a cron job) without editing the crontab, from the command line or, with the optional API, from a browser or `curl`.

## Requirements

- `curl`
- `jq`
- `mpc`

If any of these are missing, run with `-i`/`--install` to install them automatically via `apt-get`.

## Configuration

Settings live in `~/.config/mpd-scripts/mpdsimilar/mpdsimilar.conf`, seeded automatically from [`mpdsimilar.conf.example`](./mpdsimilar.conf.example) the first time `-c` or `-a` is used. Edit the copy in `~/.config/mpd-scripts/mpdsimilar/`, not the template.

- `lastfm_api_key`: your Last.fm API key — get one at [last.fm/api/account/create](https://www.last.fm/api/account/create). `-c`/`-a` won't run until this is changed from its placeholder value.
- `lastfm_api_url`: Last.fm API endpoint.
- `similar_limit`: number of similar artists fetched per query. Default `20`.
- `per_artist_limit`: maximum tracks sampled per similar artist. Default `5`.
- `current_total_limit`: total tracks added when using `-c`/`--current`. Default `20`.
- `per_track_limit`: total tracks added per queue entry when using `-a`/`--all`. Default `10`.
- `max_playlist_size`: hard cap on MPD playlist size (MPD default: 16 368). Can be overridden per-run with `-l`/`--length`. Default `16368`.
- `api_rate_limit_delay`: seconds to sleep between Last.fm API calls. Default `0.5`.
- `curl_max_time`: seconds before a Last.fm request times out. Default `10`.

## Usage

```bash
./mpdsimilar.sh [OPTIONS]
```

- `-c`, `--current`: Add similar artist tracks for the currently playing track. Crops the queue to the current track first.
- `-a`, `--all`: Add similar artist tracks for every track already in the queue.
- `-s`, `--shuffle`: Shuffle the queue after adding new tracks.
- `-l`, `--length N`: Override the max playlist size configured in `mpdsimilar.conf`, for this run.
- `-f`, `--force`: Run even when the on/off switch is off.
- `--on`, `--off`: Switch it on or off, then exit.
- `-t`, `--toggle`: Flip the switch (on to off, off to on), then exit.
- `-i`, `--install`: Install missing required packages via `apt-get`.
- `-h`, `--help`: Show usage and exit. Also shown when run with no options.

`-c` and `-a` are mutually exclusive.

Example usage:

```bash
./mpdsimilar.sh -c -s
./mpdsimilar.sh -a -l 5000
```

## On/off switch

`~/.config/mpd-scripts/mpdsimilar/state` holds `on` or `off`. While it says `off`, `-c` and `-a` exit before touching the queue (no crop, no additions, no shuffle) unless `-f` is given. A missing file counts as `on`. Any other content is an error, and nothing is added until it is fixed.

```bash
./mpdsimilar.sh --off   # pause, e.g. an hourly "mpdsimilar.sh -a -s" cron job
./mpdsimilar.sh -t      # flip it back on
```

### Switch API (optional)

`mpdsimilar-api.py` is a small web server (Python standard library, 3.8 or newer) that flips the same file, so you can switch it from a browser, a bookmark, or `curl`. Install it as a `systemd --user` service with:

```bash
./install-api.sh
```

It listens on `http://127.0.0.1:8095/` by default:

- `/`: a status page with Toggle, On, and Off buttons.
- `/status`: `on` or `off` (JSON with `?format=json`).
- `/on`, `/off`, `/toggle`: change the switch (GET or POST) and return the new state.

```bash
curl http://127.0.0.1:8095/toggle
```

To send the browser to another page afterwards, add `?next=URL`, for example `/off?next=http://localhost/`. The URL's host must be listed in `allowed_redirect_hosts`. Paths on the API server itself (`/...`) are always allowed. A refused URL doesn't undo the switch; the response says why it wasn't followed. `default_redirect` sets a page to go to when there's no `?next=`.

Settings live in `~/.config/mpd-scripts/mpdsimilar/api.conf`, seeded from [`api.conf.example`](./api.conf.example) on first start: `bind` (default `127.0.0.1`, this machine only), `port` (default `8095`), `default_redirect`, and `allowed_redirect_hosts`. The switch URLs work with a plain GET so bookmarks can use them, which also means any web page you open could trigger one. Keep `bind` on `127.0.0.1` unless you need it on your network.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
