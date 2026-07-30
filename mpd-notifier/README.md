# mpd-scripts - mpd-notifier
- Uses mpd, mpc, bash and notify-send to provide desktop notifications with ARTST, TITLE, and ALBUMART.
- Takes into account, albums where the album art cover.jpg file might be missing and provides a generic eight-note image.
- Will notify user if mpd is currently stopped. 
- Will show the artist, title, albumart with (paused) appended at the end when mpd is paused.  
- On compilations, shows the track's real artist instead of the album artist (e.g. "Various Artists").

## Configuration

Settings live in `~/.config/mpd-notifier/mpd-notifier.conf`, seeded automatically from [`mpd-notifier.conf`](./mpd-notifier.conf) the first time you run the script. Edit the copy in `~/.config/mpd-notifier/`, not the template.

- `dir`: local music library path, used to look up `cover.jpg` next to the playing track (only used when `MPD_HOST` is empty).
- `MPD_HOST`: leave empty to treat MPD as local and read cover art from `dir`; set to a hostname/IP to query a remote MPD instead (cover art lookup is skipped in that case).
- `notify_duration`: how long the notification stays on screen, in milliseconds.
- `cache_dir`: where the fallback image and copied cover art are cached.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.