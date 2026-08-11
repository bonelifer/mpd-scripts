# alarmpd

A playlist-based alarm clock daemon for [MPD](https://www.musicpd.org/). Scheduling an alarm is done entirely through your MPD client: create (or rename) a stored playlist using the name grammar below, and alarmpd plays it at the right time.

## Features

* Schedule alarms by naming a playlist -- no separate UI, works from any MPD client that can create/rename playlists
* One or more days per alarm (`Monday 7:30`, `Monday,Wednesday,Friday 7:30`, or the built-in `Weekdays`/`Weekends`/`Daily` groups)
* One-shot, non-recurring alarms for a specific date (`2026-08-12 7:30`), which expire on their own once past
* Per-alarm volume cap (`Monday 7:30 max=60`) instead of one global target for every alarm
* Gentle fade-in from 0% to the target volume, with a built-in snooze: turning the volume down manually while fading just restarts the ramp
* Permanent disable (`!Monday 7:30`) or a one-time skip (`~Monday 7:30`) that restores itself automatically after being consumed
* Refuses to guess: if two playlists resolve to the same exact time, neither is scheduled until the collision is resolved
* Optional pre-/post-alarm shell hooks (lights, notifications, whatever)
* A `--test` flag to fire an alarm immediately, for checking fade/volume/hook behavior without waiting
* Reconnects to MPD automatically (with backoff) if it's down or restarts
* alarmpd can run on a different machine than the one running MPD

## Requirements

* Python 3
* [`python-mpd2`](https://pypi.org/project/python-mpd2/)
* MPD running and reachable (defaults to `localhost:6600`; see Configuration)

## Installation

To install and configure alarmpd, clone or download this repository, then pick **one** of the following (don't run both).

Run [`./install.sh`](./install.sh) to be prompted which one you want (defaults to Option A after 30 seconds), or run either script directly if you already know:

### Option A: XDG autostart (default)

```bash
./install-xdg-autostart.sh
```

This script performs the following actions:

* Installs `python-mpd2` locally using `pip3`
* Copies `alarmpd.py` and `alarmpd.conf.example` to `~/bin/`
* Ensures `~/bin` and `~/.local/bin` are in your `PATH`
* Creates an autostart entry in `~/.config/autostart/alarmpd.desktop`

After installation, restart your shell or run `source ~/.bashrc`. The daemon will automatically start on your next login.

### Option B: systemd `--user` service

```bash
./install-systemd.sh
```

This is an alternative to the XDG autostart entry, using [`alarmpd.service`](./alarmpd.service) instead: it installs and enables a `systemd --user` unit, which gives you auto-restart on crash and logs viewable via `journalctl` instead of the daemon's own log file. It runs the daemon with `--verbose` (foreground mode) under the hood, since that's what `Type=simple` expects.

```bash
systemctl --user status alarmpd.service
journalctl --user -u alarmpd.service -f
```

Either way, the daemon creates its own state directory (`~/.local/state/alarmpd/`) and config directory (`~/.config/mpd-scripts/alarmpd/`) the first time it runs -- no `sudo` needed anywhere in installation.

## Scheduling alarms

Scheduling a new alarm is as easy as creating a playlist. The name determines when it fires:

| Name | Meaning |
| --- | --- |
| `Monday 7:30` | Recurs every Monday at 7:30 |
| `Monday,Wednesday,Friday 7:30` | Recurs on each listed day |
| `Weekdays 7:30` / `Weekends 9:00` / `Daily 6:45` | Built-in day groups |
| `Monday 7:30 max=60` | Fades to 60% instead of `default_max_volume` |
| `2026-08-12 7:30` | Fires once, on that date, then expires -- never reschedules |
| `!Monday 7:30` | Permanently disabled -- ignored entirely until renamed back |
| `~Monday 7:30` | Skips just the next occurrence, then alarmpd renames it back to `Monday 7:30` automatically |

Anything that doesn't match one of these forms (including typos in a day name) is ignored, not guessed at.

If two playlists resolve to the exact same next occurrence, alarmpd refuses to schedule either and logs the collision until it's resolved (e.g. by renaming one of them), rather than silently picking one.

## Fading / snooze

Set `fade_duration` in the config file to the number of seconds it should take to go from 0% to 100% volume; 0 disables fading and jumps straight to the target volume. An alarm's own `max=` suffix caps how far it fades, at the same seconds-per-percent rate, so a lower cap finishes proportionally faster than a full 0-100 fade.

Turning the volume down manually while an alarm is fading restarts the ramp, since alarmpd only stops adjusting the volume once it reaches the target -- so lowering the volume mid-fade doubles as a snooze button.

## Usage

Test a playlist immediately, without waiting for its scheduled time:
```bash
alarmpd.py --test "Monday 7:30"
```
Works even if the name doesn't match the schedule grammar -- any existing playlist can be tested, falling back to `default_max_volume`.

Stop the daemon (Option A / XDG autostart install):
```bash
alarmpd.py --stop
```
This reads the PID file and sends a graceful shutdown signal. If you installed via `install-systemd.sh` (Option B) instead, use `systemctl --user stop alarmpd.service`.

Run manually in the foreground (for debugging):
```bash
alarmpd.py --verbose
```

## Configuration

Settings live in `~/.config/mpd-scripts/alarmpd/alarmpd.conf`, seeded automatically from [`alarmpd.conf.example`](./alarmpd.conf.example) the first time you run the script. Edit the copy there, not the template.

| Setting | Description | Default |
| --- | --- | --- |
| `mpd_host` | MPD server hostname/IP | `localhost` |
| `mpd_port` | MPD server port | `6600` |
| `mpd_password` | MPD password, if required (leave blank if none) | *(blank)* |
| `interval` | Seconds between playlist re-scans while no alarm is imminent | `20` |
| `fade_duration` | Seconds to fade from 0% to 100% volume (0 disables fading) | `600` |
| `default_max_volume` | Volume an alarm fades/jumps to if its name has no `max=` override | `100` |
| `pre_alarm_hook` | Shell command run right before an alarm's playlist starts playing | *(blank)* |
| `post_alarm_hook` | Shell command run once an alarm's fade reaches its target | *(blank)* |

`-H`/`--host`, `-P`/`--port`, and `-a`/`--password` override the config file for a single invocation.

## Logging

Logs are written to `~/.local/state/alarmpd/alarmpd.log`. You can view the log with:

```bash
tail -f ~/.local/state/alarmpd/alarmpd.log
```

With `--verbose`, logs go to the console instead (not to the log file), and the daemon doesn't fork to the background -- useful for debugging.

## Troubleshooting

* **Permission denied for the state directory**: the daemon creates `~/.local/state/alarmpd/` itself on first run; this would only fail if `~/.local/state` somehow isn't writable by your user.
* **Daemon not autostarting (Option A)**: check the contents of `~/.config/autostart/alarmpd.desktop` and make sure the path is correct.
* **Service not starting (Option B)**: `systemctl --user status alarmpd.service` and `journalctl --user -u alarmpd.service` will show why.
* **MPD not detected**: the daemon retries the connection (backing off between attempts) rather than giving up, so it's safe to start before MPD is up; double-check `mpd_host`/`mpd_port`/`mpd_password` in the config file, and check `--verbose`/journald output if it never connects.
* **An alarm never fires**: check for a same-time collision with another playlist first (see Scheduling alarms above) -- alarmpd logs this instead of guessing which one to play.

## Uninstallation

If you installed via Option A (XDG autostart):

```bash
alarmpd.py --stop
rm ~/bin/alarmpd.py ~/bin/alarmpd.conf.example
rm ~/.config/autostart/alarmpd.desktop
```

If you installed via Option B (systemd `--user`):

```bash
systemctl --user disable --now alarmpd.service
rm ~/.config/systemd/user/alarmpd.service
rm ~/bin/alarmpd.py ~/bin/alarmpd.conf.example
```

Either way, also remove its state and config:

```bash
rm -rf ~/.local/state/alarmpd ~/.config/mpd-scripts/alarmpd
```

## Acknowledgments

Based on [alarmpd](https://github.com/ingobecker/alarmpd) by Ingo Becker, ported from Ruby to Python 3 and `python-mpd2`, with multi-day/named-group and one-shot alarm forms, per-alarm volume caps, one-time skip, collision detection, pre-/post-alarm hooks, a test-fire flag, and MPD reconnect-with-backoff added on top of the original single-day-per-playlist design.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
