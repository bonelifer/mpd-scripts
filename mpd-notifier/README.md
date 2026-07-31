# mpd-scripts - mpd-notifier
- Uses mpd, mpc, bash and notify-send to provide desktop notifications with ARTST, TITLE, and ALBUMART.
- Looks for a cover/folder/artwork/front image in the track's directory (not just a literal cover.jpg), optionally falls back to art embedded in the track's own tags (`embed_art_fallback`), and finally falls back to a generic eight-note image if neither is found.
- Will notify user if mpd is currently stopped. 
- Will show the artist, title, albumart with (paused) appended at the end when mpd is paused, and optionally shows the cover art in grayscale while paused (`grayscale_when_paused`).
- On compilations, shows the track's real artist instead of the album artist (e.g. "Various Artists").
- Each notification replaces the previous one instead of stacking, so repeated updates (e.g. from the watch script below) don't pile up.
- Can tag notifications with a category (`notify_categories`) so a notification daemon can filter or style them by playback state.

## Requirements

- `mpc`
- `notify-send` (`libnotify-bin`)
- `dunst` (optional — only needed for `use_dunstify`)
- `ffmpeg` (optional — only needed for `embed_art_fallback`)
- `imagemagick` (optional — only needed for `grayscale_when_paused`)

## Installation

1. Run [`../setup-path.sh`](../setup-path.sh) first if `~/bin` isn't already on your `PATH`.
2. Run the installer:

   ```bash
   ./install.sh
   ```

   This copies `mpd-notifier.sh`, `mpd-notifier-watch.sh`, `mpd-notifier.conf.example`, and `unknown.jpg` to `~/bin`, and adds an autostart entry (`~/.config/autostart/mpd-notifier.desktop`) that runs the watch script at login.

## Usage

`mpd-notifier.sh` sends a single notification for the currently playing track and exits — call it directly if you want to trigger a notification manually, or from your own script/cron job (see [Using mpdcron instead of the watch script](#using-mpdcron-instead-of-the-watch-script) below for a ready-made example of hooking it into an external trigger).

To get a notification automatically whenever the track changes (or play/pause/stop state changes), run [`mpd-notifier-watch.sh`](./mpd-notifier-watch.sh) instead, either via the installer's autostart entry or manually in the background:

```bash
./mpd-notifier-watch.sh &
```

It blocks on `mpc idle player` between events (no polling), and calls `mpd-notifier.sh` once per event. Seeking within the current track also triggers MPD's `player` event, but the watch script tracks the current file and play state and skips re-notifying unless one of those actually changed.

### Using mpdcron instead of the watch script

If you already run [mpdcron](https://github.com/alip/mpdcron) (`sudo apt install mpdcron`), it can trigger `mpd-notifier.sh` itself instead of running `mpd-notifier-watch.sh`. Point its `player` hook at the script, e.g. in `~/.mpdcron/hooks/player`:

```bash
#!/bin/bash
exec /path/to/mpd-notifier.sh
```

(make it executable, and list `player` in the `events` line of `~/.mpdcron/mpdcron.conf`). `mpd-notifier.sh` detects mpdcron's environment variables (`MPD_STATUS_STATE`, `MPD_SONG_TAG_TITLE`, etc.) automatically and reads track/status info from those directly instead of querying `mpc` itself. Since mpdcron's `player` event also fires on seeks, and each hook run is a fresh process with no memory of the last one, a `file|state` signature is persisted to `cache_dir/.last_signature` to skip re-notifying on seeks, the same as the watch script does in memory.

## Configuration

Settings live in `~/.config/mpd-notifier/mpd-notifier.conf`, seeded automatically from [`mpd-notifier.conf.example`](./mpd-notifier.conf.example) the first time you run the script. Edit the copy in `~/.config/mpd-notifier/`, not the template.

- `dir`: local music library path, used to look up `cover.jpg` next to the playing track (only used when `MPD_HOST` is empty).
- `MPD_HOST`: leave empty to treat MPD as local and read cover art from `dir`; set to a hostname/IP to query a remote MPD instead (cover art lookup is skipped in that case).
- `notify_duration`: how long the notification stays on screen, in milliseconds.
- `cache_dir`: where the fallback image and copied cover art are cached.
- `enable_actions`: set to `"true"` to add Play-Pause/Next buttons to the notification, plus Previous unless MPD's `consume` mode is on (in which case there's no previous track left in the queue to go back to). Off by default since it requires a notify-send that supports `-A`/`--action` (e.g. `libnotify-bin`) — not every provider does. When it isn't supported, this is detected automatically and the buttons are silently skipped. Note that whether actions actually render as clickable buttons also depends on your notification *daemon* (e.g. dunst, not just the `notify-send`/`dunstify` client) actually being the active one handling notifications.
- `use_dunstify`: set to `"true"` to send notifications via [dunst](https://github.com/dunst-project/dunst)'s `dunstify` instead of `notify-send` (install with e.g. `sudo apt install dunst`). Worth enabling if your system's stock notify-send is missing `-r`/`--replace-id` or `-A`/`--action` support — notably Ubuntu 22.04's `libnotify-bin`, which ships one version behind the release that added them. Default: `"false"`.
- `embed_art_fallback`: set to `"true"` to try extracting album art embedded in the track's own tags via `ffmpeg` (`sudo apt install ffmpeg`) when no cover/folder/artwork/front image file is found in the track's directory. Default: `"false"`.
- `grayscale_when_paused`: set to `"true"` to show a grayscale version of the cover art while paused, as a visual cue in addition to the "(paused)" text. Requires ImageMagick's `convert` (`sudo apt install imagemagick`). Default: `"false"`.
- `notify_categories`: set to `"true"` to tag notifications with a category (`mpd`/`mpd-paused`/`mpd-stopped`) via `-c`/`--category`, letting a notification daemon filter or style them by playback state. Only applied if the notify-send/dunstify in use advertises support (detected automatically). Default: `"false"`.

  Example [dunst rules](https://dunst-project.org/documentation/#rules) (`~/.config/dunst/dunstrc`) using all three categories:

  ```ini
  [mpd]
      category = "mpd"

  [mpd-paused]
      category = "mpd-paused"
      background = "#333333"
      timeout = 0

  [mpd-stopped]
      category = "mpd-stopped"
      timeout = 3000
  ```

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.