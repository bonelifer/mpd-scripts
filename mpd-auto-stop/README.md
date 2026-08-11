# mpd-auto-stop

A sleep-timer daemon for MPD: a small web UI and JSON API to start a countdown, and when it expires, fade the volume out and pause playback -- instead of cutting off abruptly mid-song.

## Features

* Web UI with preset duration buttons (+15m/+30m/+45m/+1h/+1.5h/+2h), a custom-duration field, and a live countdown -- usable from a phone browser on the same network, no app needed
* Light/dark/auto theme, following the system preference by default, remembered across visits
* Gentle fade-out over a configurable duration ending exactly when the timer would otherwise fire, instead of an abrupt `pause`; the pre-fade volume is restored right after pausing so the next play isn't silently at 0%
* Optional warning hook a configurable number of seconds before the timer fires, and a stop hook once it does -- shell commands, so they can drive a desktop notification, a push notification (e.g. `ntfy`), or a home-automation webhook, since this commonly runs headless with no notification daemon of its own
* Start / stop / restart / extend an active timer, same JSON API shape as the original tool this is based on
* Runs on Python 3 + `python-mpd2` only -- no web framework

## Requirements

* Python 3
* [`python-mpd2`](https://pypi.org/project/python-mpd2/)
* MPD running and reachable (defaults to `localhost:6600`; see Configuration)

## Installation

To install and configure mpd-auto-stop, clone or download this repository, then pick **one** of the following (don't run both).

Run [`./install.sh`](./install.sh) to be prompted which one you want (defaults to Option A after 30 seconds), or run either script directly if you already know:

### Option A: XDG autostart (default)

```bash
./install-xdg-autostart.sh
```

This script performs the following actions:

* Installs `python-mpd2` locally using `pip3`
* Copies `mpd-auto-stop.py`, `mpd-auto-stop.conf.example`, and `index.html` to `~/bin/`
* Ensures `~/bin` and `~/.local/bin` are in your `PATH`
* Creates an autostart entry in `~/.config/autostart/mpd-auto-stop.desktop`

After installation, restart your shell or run `source ~/.bashrc`. The daemon will automatically start on your next login.

### Option B: systemd `--user` service

```bash
./install-systemd.sh
```

This is an alternative to the XDG autostart entry, using [`mpd-auto-stop.service`](./mpd-auto-stop.service) instead: it installs and enables a `systemd --user` unit, which gives you auto-restart on crash and logs viewable via `journalctl` instead of the daemon's own log file. It runs the daemon with `--verbose` (foreground mode) under the hood, since that's what `Type=simple` expects.

```bash
systemctl --user status mpd-auto-stop.service
journalctl --user -u mpd-auto-stop.service -f
```

This also works on a headless machine with no desktop session (e.g. the Raspberry Pi the original tool was written for) -- run `sudo loginctl enable-linger $USER` once so the service keeps running after you log out.

Either way, the daemon creates its own state directory (`~/.local/state/mpd-auto-stop/`) and config directory (`~/.config/mpd-scripts/mpd-auto-stop/`) the first time it runs -- no `sudo` needed anywhere in installation.

## Usage

Open `http://<host>:9090/` (or whatever `http_host`/`http_port` you've configured) in a browser for the web UI, or use the JSON API directly:

| Endpoint | Description |
| --- | --- |
| `GET /timer` | Status: `{"status": "stopped"}` or `{"status": "started", "remaining_seconds": 930, "fading": false}` |
| `GET /timer/<duration>/start` | Start a timer. `<duration>` like `45m`, `1h`, `1.5h`, `3600s`. |
| `GET /timer/stop` | Cancel the running timer (just cancels the countdown -- doesn't pause playback itself). |
| `GET /timer/restart` | Re-arm the running timer with its original duration. |
| `GET /timer/<duration>/extend` | Add more time to the running timer. |

Stop the daemon (Option A / XDG autostart install):
```bash
mpd-auto-stop.py --stop
```
If you installed via `install-systemd.sh` (Option B) instead, use `systemctl --user stop mpd-auto-stop.service`.

Run manually in the foreground (for debugging):
```bash
mpd-auto-stop.py --verbose
```

## Configuration

Settings live in `~/.config/mpd-scripts/mpd-auto-stop/mpd-auto-stop.conf`, seeded automatically from [`mpd-auto-stop.conf.example`](./mpd-auto-stop.conf.example) the first time you run the script. Edit the copy there, not the template.

| Setting | Description | Default |
| --- | --- | --- |
| `http_host` | Address the web server listens on | `0.0.0.0` |
| `http_port` | Port the web server listens on | `9090` |
| `http_username` | Optional HTTP Basic Auth username (leave blank with `http_password` to disable) | *(blank)* |
| `http_password` | Optional HTTP Basic Auth password | *(blank)* |
| `mpd_host` | MPD server hostname/IP | `localhost` |
| `mpd_port` | MPD server port | `6600` |
| `mpd_password` | MPD password, if required (leave blank if none) | *(blank)* |
| `fade_duration` | Seconds to fade the volume to 0, ending when the timer fires (0 = instant pause) | `300` |
| `warning_lead_time` | Seconds before firing to run `warning_hook` (0 = disabled) | `60` |
| `warning_hook` | Shell command run `warning_lead_time` seconds before the timer fires | *(blank)* |
| `stop_hook` | Shell command run once playback is actually paused | *(blank)* |

`-a`/`--http-host`, `-p`/`--http-port`, `-U`/`--http-username`, `-W`/`--http-password`, `-H`/`--mpd-host`, `-P`/`--mpd-port`, and `-w`/`--mpd-password` override the config file for a single invocation.

## Security

The server has no access control by default and listens on `0.0.0.0` -- anyone on the same network can start/stop your timer. Set `http_username`/`http_password` (or `-U`/`-W`) to require HTTP Basic Auth on every request, including the web UI itself. Still worth keeping this off the open internet regardless; Basic Auth over plain HTTP protects against casual same-network access, not a hostile one.

## How fading works

`fade_duration` sets how many seconds it takes to ramp the volume down to 0, timed to finish exactly when the timer would otherwise fire -- a 1-hour timer with a 5-minute `fade_duration` stays at full volume for the first 55 minutes, then tapers off over the last 5. If `fade_duration` is longer than the timer itself, it's clamped down to fit rather than pushing the actual stop time later than requested. `warning_lead_time` fires independently at its own offset, whether that lands before, during, or (in a degenerate config) right at the moment of the fade completing -- either way it always fires exactly once and the timer never runs past the requested duration. Cancelling (`stop`), `restart`ing, or `extend`ing a timer mid-fade immediately restores the volume to what it was before fading started, since those all mean "keep playing normally," not "pause now."

## Logging

Logs are written to `~/.local/state/mpd-auto-stop/mpd-auto-stop.log`. With `--verbose`, logs go to the console instead, and the daemon doesn't fork to the background -- useful for debugging.

## Acknowledgments

Based on [mpd_auto_stop](https://github.com/vms20591/mpd_auto_stop) by Meenakshi Sundaram V. The original had two bugs fixed in this port: every error-response code path called the Python 2-only `exp.message` attribute, which was removed in Python 3 and made every error path raise an unhandled `AttributeError` instead of returning the intended JSON error body; and the server drove a private `_handle_request_noblock()` method directly instead of the public `serve_forever()`/`shutdown()` API, which meant a `SIGTERM` (e.g. from `systemctl stop`) wouldn't actually take effect until the next incoming HTTP request happened to arrive. Also dropped the Python 2 compatibility shims (Python 3 only now), and added the fade-out, warning/stop hooks, optional HTTP Basic Auth, and the web UI on top of the original's bare JSON API and link list.

A third bug was introduced and fixed during this port's own development: the warning and fade were originally chained sequentially ("wait for the warning, then wait for the rest of `fade_duration`"), which only produced the intended timing when `warning_lead_time > fade_duration`. With the shipped defaults (`fade_duration=300` > `warning_lead_time=60`) it actually ran the timer past its requested duration. Fixed by scheduling both as independent absolute-offset checkpoints and clamping the fade to whatever time is actually left, rather than always running for the full configured `fade_duration`.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
