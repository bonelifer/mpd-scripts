# MPD Rewind Daemon

MPD Rewind Daemon is a background service that automatically rewinds the currently playing track in [MPD (Music Player Daemon)](https://www.musicpd.org/) by a few seconds when playback is resumed after being paused. This helps you seamlessly resume where you left off — especially useful when listening to music, long mixes, or **audiobooks** where you might want a quick recap of the last few seconds.

## Features

* Automatically rewinds playback after resuming from pause
* Helpful for music, podcasts, and **audiobooks**, ensuring you don’t miss context
* Configurable rewind time (default: 5 seconds)
* Runs silently in the background as a user autostart application
* Logs to `/var/log/mpd_rewind_daemon.log`
* Safe shutdown and PID tracking
* Installer script for quick setup

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
* Creates a log file at `/var/log/mpd_rewind_daemon.log` with appropriate permissions

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

To stop the daemon manually:

```bash
pkill -f mpd_rewind_daemon.py
```

## Configuration

These values are set within the script:

| Setting          | Description                              | Default                          |
| ---------------- | ---------------------------------------- | -------------------------------- |
| `SEEK_BACK_TIME` | How many seconds to rewind when resuming | `5.0` seconds                    |
| `PID_FILE`       | Where to store the daemon's PID          | `/tmp/mpd_rewind_daemon.pid`     |
| `LOG_FILE`       | Log output file path                     | `/var/log/mpd_rewind_daemon.log` |

To change these values, you can edit `mpd_rewind_daemon.py` directly.

## Logging

Logs are written to `/var/log/mpd_rewind_daemon.log`. You can view the log with:

```bash
tail -f /var/log/mpd_rewind_daemon.log
```

Verbose logs (including console output) are only shown when run with `--verbose`.

## Troubleshooting

* **Permission denied for log file**: Ensure you have write access to `/var/log/`. The installer sets it up with `chmod 666`, but manual intervention may be needed on stricter systems.
* **Daemon not autostarting**: Check the contents of `~/.config/autostart/mpd-rewind.desktop` and make sure the path is correct.
* **MPD not detected**: Ensure MPD is running and accessible on `localhost:6600`.

## Uninstallation

To uninstall:

```bash
rm ~/bin/mpd_rewind_daemon.py
rm ~/.config/autostart/mpd-rewind.desktop
sudo rm /var/log/mpd_rewind_daemon.log
```

Also remove any `PATH` entries from `~/.bashrc` if you no longer use `~/bin` or `~/.local/bin`.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
