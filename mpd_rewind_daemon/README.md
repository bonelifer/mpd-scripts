# MPD Rewind Daemon

MPD Rewind Daemon is a background service that automatically rewinds the currently playing track in [MPD (Music Player Daemon)](https://www.musicpd.org/) by a few seconds when playback is resumed after being paused. This helps you seamlessly resume where you left off — especially useful when listening to music, long mixes, or **audiobooks** where you might want a quick recap of the last few seconds.

## Features

* Automatically rewinds playback after resuming from pause
* Helpful for music, podcasts, and **audiobooks**, ensuring you don’t miss context
* Configurable rewind time (default: 5 seconds)
* Runs silently in the background as a user autostart application
* Logs to `~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.log`
* Safe shutdown and PID tracking
* Automatically reconnects (with retry/backoff) if MPD isn't up yet or restarts, instead of exiting
* Installer script for quick setup — entirely user-space, no `sudo` required

## Requirements

* Python 3
* [`python-mpd2`](https://pypi.org/project/python-mpd2/)
* MPD running on `localhost:6600`

## Installation

To install and configure the MPD Rewind Daemon:

1. Clone or download this repository.
2. Run the installer script:

```bash
./install.sh
```

This script performs the following actions:

* Installs `python-mpd2` locally using `pip3`
* Copies `mpd_rewind_daemon.py` to `~/bin/`
* Ensures `~/bin` and `~/.local/bin` are in your `PATH`
* Creates an autostart entry in `~/.config/autostart/mpd-rewind.desktop`

The daemon creates its own state directory (`~/.local/state/mpd_rewind_daemon/`) for its log and PID files the first time it runs — no `sudo` needed anywhere in installation.

After installation, restart your shell or run:

```bash
source ~/.bashrc
```

The daemon will automatically start on your next login.

## Usage

You can manually run the daemon (for debugging) using:

```bash
python3 ~/bin/mpd_rewind_daemon.py --verbose
```

To stop the daemon:

```bash
~/bin/mpd_rewind_daemon.py --stop
```

This reads the PID file and sends a graceful shutdown signal. (`pkill -f mpd_rewind_daemon.py` also works, but won't clean up the PID file itself — the daemon's own signal handler does that.)

## Configuration

These values are set within the script:

| Setting          | Description                              | Default                                                    |
| ---------------- | ---------------------------------------- | ----------------------------------------------------------|
| `SEEK_BACK_TIME` | How many seconds to rewind when resuming | `5.0` seconds                                              |
| `PID_FILE`       | Where to store the daemon's PID          | `~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.pid`   |
| `LOG_FILE`       | Log output file path                     | `~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.log`   |

To change these values, you can edit `mpd_rewind_daemon.py` directly.

## Logging

Logs are written to `~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.log`. You can view the log with:

```bash
tail -f ~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.log
```

With `--verbose`, logs go to the console instead (not to the log file), and the daemon doesn't fork to the background — useful for debugging.

## Troubleshooting

* **Permission denied for the state directory**: the daemon creates `~/.local/state/mpd_rewind_daemon/` itself on first run; this would only fail if `~/.local/state` somehow isn't writable by your user.
* **Daemon not autostarting**: Check the contents of `~/.config/autostart/mpd-rewind.desktop` and make sure the path is correct.
* **MPD not detected**: the daemon retries the connection (backing off between attempts) rather than giving up, so it's safe to start before MPD is up; check `--verbose` output if it never connects.

## Uninstallation

To uninstall:

```bash
~/bin/mpd_rewind_daemon.py --stop
rm ~/bin/mpd_rewind_daemon.py
rm ~/.config/autostart/mpd-rewind.desktop
rm -rf ~/.local/state/mpd_rewind_daemon
```

Also remove any `PATH` entries from `~/.bashrc` if you no longer use `~/bin` or `~/.local/bin`.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
