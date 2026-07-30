# mpd-scripts - lastfm-love
#### Based on the [PyLast](https://github.com/pylast/pylast) ([readme](https://github.com/pylast/pylast/blob/main/README.md)) example with changes to automate submitting via info from mpc
  * loved.py    - when called will query mpc for the current artist and title and love the track on lastfm
  * unloved.py  - when called will query mpc for the current artist and title and unlove the track on lastfm

Prefers the track's own artist over the album artist, so compilation albums (where the album artist is often something like "Various Artists") still love/unlove against the correct performer.

## Requirements

- `mpc`
- Python 3, [`pylast`](https://github.com/pylast/pylast) (`pip install pylast`)

## Configuration

On first run, both scripts create `~/.config/lastfm-love/lastfm-love.conf` (from the [template](./lastfm-love.conf) shipped alongside them) and exit with instructions to fill it in. Edit the copy in `~/.config/lastfm-love/`, not the template.

- `api_key` / `api_secret`: obtain from https://www.last.fm/api/account/create
- `username`: your Last.fm username
- `password`: your Last.fm password, in plain text — it's hashed (via `pylast.md5`) before use and only the hash is ever sent to Last.fm

The first time you run either script, it opens a browser tab to authorize access; the resulting session key is cached in `~/.config/lastfm-love/session_key` so you're not prompted again. Both files are created with `0600`/`0700` permissions since they hold credentials.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.