# MPD Radio Tray

A PyQt5 system tray app (similar to RadioTray-NG) for managing categorized internet radio station URLs with MPD.

## Features

- Tray menu with Stop, categorized stations (submenus), Refresh, and Exit.
- A visible tray notification (and updated tooltip) if MPD isn't reachable — at startup, and whenever loading/stopping a station fails — rather than only printing to a terminal nobody's watching.
- MPD calls use a 5-second timeout, so a hung or unreachable server can't freeze the tray app.

## Requirements

- `mpc`-compatible MPD server
- PyQt5 (e.g. `sudo apt install python3-pyqt5`)
- `python-mpd2` (e.g. `pip install python-mpd2`)

## Configuration

Settings live in `~/.config/mpd-radio-tray/mpd-radio-tray.conf`, seeded automatically from [`mpd-radio-tray.conf.example`](./mpd-radio-tray.conf.example) the first time you run the script. Edit the copy in `~/.config/mpd-radio-tray/`, not the template.

- `mpd_host`, `mpd_port`: MPD server address. Default `localhost`/`6600`.
- `icon_path`: path to a custom tray icon image. Leave blank to use the desktop theme's `media-playback-start` icon.

Your station list lives in `~/.config/mpd-radio-tray/stations.txt`, seeded from [`stations.txt.example`](./stations.txt.example) (with placeholder URLs) the first time you run the script. Edit the copy in `~/.config/mpd-radio-tray/` to add your own stations, one per line:

```
category|display name|stream url
```

Blank lines and lines starting with `#` are ignored.

## Usage

```bash
./mpd-radio-tray.py
```

Left-click the tray icon for the menu. Click a station under its category to play it, "Stop" to stop playback, "Refresh" to reload the station list after editing it, and "Exit" to quit.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
