# mpd-kb-control

Dispatches multimedia-key presses to MPD -- bind `XF86AudioPlay`/`XF86AudioNext`/etc. in your window manager to this script, and it handles play/pause, track navigation, volume, mute, and MPD's consume/random/repeat/single playback modes.

## Features

* Correct play/pause/stopped detection via MPD's own `state` field, not text-scraped `mpc` output -- unlike the script this is based on, pressing play while MPD is stopped actually starts playback instead of silently doing nothing
* Configurable volume step, with an optional ceiling so "raise" never pushes past a `max_volume` you set
* Mute/unmute with automatic previous-volume save and restore
* Toggle MPD's consume/random/repeat/single playback modes -- see below for binding these on a separate keypad, since they have no dedicated multimedia key
* Optional desktop notifications on play/pause/volume changes (off by default) -- also shown on failure (connection lost, empty queue, wrong password, etc.) when enabled, since this runs from a keybinding with no visible terminal to print an error to
* Mute/unmute is race-safe: two invocations firing close together (a double-tap, or an accidental duplicate keybinding) serialize instead of one clobbering the other's save

## Requirements

* Python 3
* [`python-mpd2`](https://pypi.org/project/python-mpd2/)
* MPD running and reachable (defaults to `localhost:6600`; see Configuration)
* `notify-send` (optional, only used if `notify` is enabled in the config)

## Usage

```
mpd-kb-control.py [-H HOST] [-P PORT] [-a PASSWORD] {play,next,prev,raise,lower,mute,consume,random,repeat,single}
```

| Command | Description |
| --- | --- |
| `play` | Toggle play/pause. Starts playback if MPD is currently stopped. |
| `next` | Skip to the next track. |
| `prev` | Skip to the previous track. |
| `raise` | Raise the volume by `volume_step` (clamped to `max_volume` if `enforce_max_volume` is on). |
| `lower` | Lower the volume by `volume_step`. |
| `mute` | Toggle mute: saves the current volume and zeroes it, or restores the last saved volume if already at 0. |
| `consume` | Toggle consume mode (played tracks are removed from the queue). |
| `random` | Toggle random (shuffle) mode. |
| `repeat` | Toggle repeat mode. |
| `single` | Toggle single mode (stop, or repeat the same track, after it finishes -- depends on `repeat`). |

### Example: binding in XFCE's keyboard settings

Open **Settings → Keyboard → Application Shortcuts**, click **Add**, type the command (e.g. `mpd-kb-control.py play`), then press the key you want to bind it to when prompted:

| Command | Key to press |
| --- | --- |
| `mpd-kb-control.py play` | `XF86AudioPlay` |
| `mpd-kb-control.py next` | `XF86AudioNext` |
| `mpd-kb-control.py prev` | `XF86AudioPrev` |
| `mpd-kb-control.py raise` | `XF86AudioRaiseVolume` |
| `mpd-kb-control.py lower` | `XF86AudioLowerVolume` |
| `mpd-kb-control.py mute` | `XF86AudioMute` |

XFCE often ships these keys pre-bound to its own volume OSD (via `xfce4-pulseaudio-plugin` or similar). If pressing the key doesn't prompt you to overwrite an existing shortcut, find and remove that default binding first (same Application Shortcuts list), or both will fire.

The same thing scripted via `xfconf-query`, useful for provisioning more than one machine (`-n` creates the property if it doesn't exist yet, so this is safe to re-run):

```bash
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/XF86AudioPlay        -n -t string -s "mpd-kb-control.py play"
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/XF86AudioNext        -n -t string -s "mpd-kb-control.py next"
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/XF86AudioPrev        -n -t string -s "mpd-kb-control.py prev"
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/XF86AudioRaiseVolume -n -t string -s "mpd-kb-control.py raise"
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/XF86AudioLowerVolume -n -t string -s "mpd-kb-control.py lower"
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/XF86AudioMute        -n -t string -s "mpd-kb-control.py mute"
```

### Example: a separate keypad for consume/random/repeat/single

`consume`/`random`/`repeat`/`single` don't correspond to any standard multimedia key, so there's nothing to bind them to on a normal keyboard. A cheap secondary USB numpad works well as a dedicated set of MPD mode toggles instead -- XFCE's Application Shortcuts editor accepts numpad keys the exact same way it accepts multimedia keys, no extra driver or udev rule needed. Add each one the same way (Add → type the command → press the numpad key):

| Command | Key to press |
| --- | --- |
| `mpd-kb-control.py consume` | `KP_1` |
| `mpd-kb-control.py random` | `KP_2` |
| `mpd-kb-control.py repeat` | `KP_3` |
| `mpd-kb-control.py single` | `KP_4` |

Or via `xfconf-query`:

```bash
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/KP_1 -n -t string -s "mpd-kb-control.py consume"
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/KP_2 -n -t string -s "mpd-kb-control.py random"
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/KP_3 -n -t string -s "mpd-kb-control.py repeat"
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/KP_4 -n -t string -s "mpd-kb-control.py single"
```

If the numpad's keys don't register as `KP_1` etc. in the Application Shortcuts dialog (some cheap keypads use a NumLock-dependent or otherwise remapped layout), run `xev` and press each key to see the keysym it actually sends, then use that instead.

### Bonus: Application Shortcuts aren't MPD-specific

The same mechanism binds any command, not just `mpd-kb-control.py` -- useful for filling out the rest of a spare numpad. For example, opening a URL in your default browser on `KP_5`:

```bash
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/KP_5 -n -t string -s "xdg-open https://github.com/bonelifer/mpd-scripts"
```

or the same thing through the GUI: Add → `xdg-open https://github.com/bonelifer/mpd-scripts` → press `KP_5`. `xdg-open` picks your configured default browser; swap in `firefox`/`chromium` directly if you'd rather target a specific one.

## Configuration

Settings live in `~/.config/mpd-scripts/mpd-kb-control/mpd-kb-control.conf`, seeded automatically from [`mpd-kb-control.conf.example`](./mpd-kb-control.conf.example) the first time you run the script. Edit the copy there, not the template.

| Setting | Description | Default |
| --- | --- | --- |
| `mpd_host` | MPD server hostname/IP | `localhost` |
| `mpd_port` | MPD server port | `6600` |
| `mpd_password` | MPD password, if required (leave blank if none) | *(blank)* |
| `volume_step` | Percentage points adjusted per `raise`/`lower` call | `5` |
| `enforce_max_volume` | If `true`, `raise` won't push the volume above `max_volume` | `false` |
| `max_volume` | Ceiling used when `enforce_max_volume` is on | `100` |
| `notify` | Show a desktop notification on play/pause/volume changes | `false` |

`-H`/`--host`, `-P`/`--port`, and `-a`/`--password` override the config file for a single invocation.

Mute state (the volume to restore on unmute) is stored separately in `~/.local/state/mpd-kb-control/volume_save`, since it's runtime state rather than configuration.

## Known limitations

Each invocation opens a fresh MPD connection and closes it -- fine for a tap, but if your window manager auto-repeats a held key (many do, around 20-25 times/sec), holding `raise`/`lower` down means that many new connections per second for as long as it's held. This is inherent to running as a one-shot CLI dispatch rather than a background daemon; if you want a smoother held-key ramp, bind the key to repeat less aggressively at the WM level instead.

## Acknowledgments

Based on [mpd_kb_control](https://github.com/nogaems/mpd_kb_control) by nogaems, ported from bash/`mpc` to Python 3 and `python-mpd2`. The original's play/pause detection text-scraped `mpc`'s human-readable output for a `[playing]`/`[paused]` bracket, which meant the documented "starts playback if stopped" behavior never actually worked -- there's no such bracket when MPD is stopped. Reading MPD's `state` field directly instead fixes that as a side effect of the port, alongside adding a configurable volume step, an optional max-volume ceiling (now enforced on mute-restore too, not just `raise`), desktop notifications (including on failure), race-safe mute via file locking, and toggles for MPD's consume/random/repeat/single playback modes.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
