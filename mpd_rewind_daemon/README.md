# MPD Rewind Daemon

MPD Rewind Daemon is a background service that automatically rewinds the currently playing track in [MPD (Music Player Daemon)](https://www.musicpd.org/) by a few seconds when playback is resumed after being paused. This helps you seamlessly resume where you left off — especially useful when listening to music, long mixes, or **audiobooks** where you might want a quick recap of the last few seconds.

## Features

* Automatically rewinds playback after resuming from pause
* Helpful for music, podcasts, and **audiobooks**, ensuring you don’t miss context
* Rewind amount scales with how long you were paused (configurable tiers), so a quick pause barely rewinds while a long one rewinds further
* Configurable MPD host/port/password
* Runs silently in the background as a user autostart application, or as a systemd `--user` service
* Logs to `~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.log`
* Safe shutdown and PID tracking
* Automatically reconnects (with retry/backoff) if MPD isn't up yet or restarts, instead of exiting
* Installer script for quick setup — entirely user-space, no `sudo` required

## Requirements

* Python 3
* [`python-mpd2`](https://pypi.org/project/python-mpd2/)
* MPD running and reachable (defaults to `localhost:6600`; see Configuration)

## Installation

To install and configure the MPD Rewind Daemon, clone or download this repository, then pick **one** of the following (don't run both):

### Option A: XDG autostart (default)

```bash
./install-xdg-autostart.sh
```

This script performs the following actions:

* Installs `python-mpd2` locally using `pip3`
* Copies `mpd_rewind_daemon.py` to `~/bin/`
* Ensures `~/bin` and `~/.local/bin` are in your `PATH`
* Creates an autostart entry in `~/.config/autostart/mpd-rewind.desktop`

After installation, restart your shell or run `source ~/.bashrc`. The daemon will automatically start on your next login.

### Option B: systemd `--user` service

```bash
./install-systemd.sh
```

This is an alternative to the XDG autostart entry, using [`mpd-rewind-daemon.service`](./mpd-rewind-daemon.service) instead: it installs and enables a `systemd --user` unit, which gives you auto-restart on crash and logs viewable via `journalctl` instead of the daemon's own log file. It runs the daemon with `--verbose` (foreground mode) under the hood, since that's what `Type=simple` expects.

```bash
systemctl --user status mpd-rewind-daemon.service
journalctl --user -u mpd-rewind-daemon.service -f
```

Either way, the daemon creates its own state directory (`~/.local/state/mpd_rewind_daemon/`) and config directory (`~/.config/mpd-scripts/mpd_rewind_daemon/`) the first time it runs — no `sudo` needed anywhere in installation.

## Usage

You can manually run the daemon (for debugging) using:

```bash
python3 ~/bin/mpd_rewind_daemon.py --verbose
```

To stop the daemon (Option A / XDG autostart install):

```bash
~/bin/mpd_rewind_daemon.py --stop
```

This reads the PID file and sends a graceful shutdown signal. (`pkill -f mpd_rewind_daemon.py` also works, but won't clean up the PID file itself — the daemon's own signal handler does that.) If you installed via `install-systemd.sh` (Option B) instead, use `systemctl --user stop mpd-rewind-daemon.service` — that install runs the daemon in `--verbose`/foreground mode, so there's no PID file to manage.

## Configuration

Settings live in `~/.config/mpd-scripts/mpd_rewind_daemon/mpd_rewind_daemon.conf`, seeded automatically from [`mpd_rewind_daemon.conf.example`](./mpd_rewind_daemon.conf.example) the first time you run the script. Edit the copy in `~/.config/mpd-scripts/mpd_rewind_daemon/`, not the template.

| Setting        | Description                                       | Default                 |
| -------------- | --------------------------------------------------- | ----------------------- |
| `rewind_tiers` | How far to rewind based on how long you were paused | `5:5,15:15,30:30,60:60` |
| `mpd_host`     | MPD server hostname/IP                              | `localhost`              |
| `mpd_port`     | MPD server port                                     | `6600`                   |
| `mpd_password` | MPD password, if required (leave blank if none)     | *(blank)*                |

`rewind_tiers` is a comma-separated list of `paused_seconds:rewind_seconds` pairs. The longest threshold that's `<=` the actual pause duration wins, so with the default tiers, pausing for 20s rewinds 15s. Pausing for less than the smallest threshold (5s by default) doesn't rewind at all. Add, remove, or change tiers freely — e.g. `10:3,60:10,300:20` for a gentler curve.

Two more paths aren't in the config file, since changing them is a less common need — edit `mpd_rewind_daemon.py` directly if you want to:

| Setting    | Description                     | Default                                                  |
| ---------- | -------------------------------- | --------------------------------------------------------|
| `PID_FILE` | Where to store the daemon's PID | `~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.pid` |
| `LOG_FILE` | Log output file path            | `~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.log` |

## Logging

Logs are written to `~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.log`. You can view the log with:

```bash
tail -f ~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.log
```

With `--verbose`, logs go to the console instead (not to the log file), and the daemon doesn't fork to the background — useful for debugging.

## Troubleshooting

* **Permission denied for the state directory**: the daemon creates `~/.local/state/mpd_rewind_daemon/` itself on first run; this would only fail if `~/.local/state` somehow isn't writable by your user.
* **Daemon not autostarting (Option A)**: Check the contents of `~/.config/autostart/mpd-rewind.desktop` and make sure the path is correct.
* **Service not starting (Option B)**: `systemctl --user status mpd-rewind-daemon.service` and `journalctl --user -u mpd-rewind-daemon.service` will show why.
* **MPD not detected**: the daemon retries the connection (backing off between attempts) rather than giving up, so it's safe to start before MPD is up; double-check `mpd_host`/`mpd_port`/`mpd_password` in the config file, and check `--verbose`/journald output if it never connects.

## Uninstallation

If you installed via Option A (XDG autostart):

```bash
~/bin/mpd_rewind_daemon.py --stop
rm ~/bin/mpd_rewind_daemon.py
rm ~/.config/autostart/mpd-rewind.desktop
```

If you installed via Option B (systemd `--user`):

```bash
systemctl --user disable --now mpd-rewind-daemon.service
rm ~/.config/systemd/user/mpd-rewind-daemon.service
rm ~/bin/mpd_rewind_daemon.py
```

Either way, also remove its state and config:

```bash
rm -rf ~/.local/state/mpd_rewind_daemon ~/.config/mpd-scripts/mpd_rewind_daemon
```

Also remove any `PATH` entries from `~/.bashrc` if you no longer use `~/bin` or `~/.local/bin`.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
