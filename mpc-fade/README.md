# mpd-scripts - mpc-fade

Fades MPD playback volume smoothly instead of jumping instantly.

## Features

- **Fade to a target volume**: `mpc-fade.sh <end volume> <duration in secs>` fades from the current volume to any target level over a fixed duration (from koppi's gist) — useful for wake-up alarms or scheduled fade-outs.
- **Fade-out / toggle / fade-in**: `-t`/`--toggle` fades out, toggles play/pause, then fades back in around the toggle (from Pablo1107's gist) — useful as a "pause gently" hotkey.
- **Two volume backends**: by default fades MPD's own volume (`mpc volume`); pass `-P`/`--pulse` to fade the PulseAudio sink-input stream feeding MPD instead, useful when other apps share the same audio sink and you don't want MPD's own volume control involved. The application name to match is configurable with `-a`/`--app` (default `mpd`, or the saved default below).
- **Sink picker**: `-l`/`--list-sinks` lists every active PulseAudio sink input in a numbered menu (application, media name, volume, sink id), and saves your pick as the default `--pulse` app so you don't have to pass `-a` every time.
- **Direct sink targeting**: `-i`/`--sink-id ID` fades a specific PulseAudio sink-input index directly (implies `--pulse`), for when more than one stream shares the same application name.
- **Logarithmic fade curve**: `-L`/`--log-curve` spends proportionally more time at quiet volumes instead of a constant %/sec pace, approximating a perceptually even fade (loudness is roughly logarithmic in volume%). Off by default; can be made the default via the config file.
- **Dry run**: `-n`/`--dry-run` prints what a fade or toggle would do without changing anything.
- **Visible progress**: prints when a fade starts and finishes, instead of running silently for the whole duration. Pass `-q`/`--quiet` to suppress this (errors still print).
- **Bounded `mpc`/`pactl` calls**: every call has a 5-second timeout, so an unreachable or misconfigured MPD/PulseAudio (bad `MPD_HOST`, firewalled, not running) fails fast with a clear message instead of hanging forever with no output.
- **Single-instance guard**: only one fade/toggle runs at a time; a second invocation while one is already in progress exits immediately instead of racing the first one's volume changes.
- **Clean interrupt**: Ctrl+C (or SIGTERM) during a fade jumps straight to the target volume before exiting, instead of leaving it stuck partway through.

## Requirements

- `mpc`, `bc`, `flock` (the last from `util-linux`, present by default on virtually any Linux system)
- `pactl` (from `pulseaudio-utils`), only if using `-P`/`--pulse`, `-i`/`--sink-id`, or `-l`/`--list-sinks`
- Bash 4 or later

## Configuration

Optional. `PULSE_APP`, `DEFAULT_SECS`, and `LOG_CURVE` live in `~/.config/mpd-scripts/mpc-fade/mpc-fade.conf`, seeded from [`mpc-fade.conf.example`](./mpc-fade.conf.example) (`PULSE_APP` is normally set by `-l`/`--list-sinks` saving a choice; the others can be edited directly). Without a config file, `-P` mode falls back to matching application name `mpd`, `--toggle` fades default to 2 seconds, and the fade curve defaults to linear. Edit the copy in `~/.config/mpd-scripts/mpc-fade/`, not the template.

## Usage

```bash
mpc-fade.sh <end volume> <duration in secs> [-P] [-a NAME|-i ID] [-L] [-q] [-n]
mpc-fade.sh -t [-s SECS] [-P] [-a NAME|-i ID] [-L] [-q] [-n]
mpc-fade.sh -l
```

- `-t`, `--toggle`: fade out, toggle play/pause, fade back in, instead of fading to a fixed target volume.
- `-s`, `--secs SECS`: fade duration in seconds for `--toggle` mode (default: `2`, or `DEFAULT_SECS` from the config file if set).
- `-P`, `--pulse`: fade the PulseAudio sink-input volume instead of MPD's own volume.
- `-a`, `--app NAME`: PulseAudio application name to match in `--pulse` mode (default: `mpd`, or `PULSE_APP` from the config file if set).
- `-i`, `--sink-id ID`: fade a specific PulseAudio sink-input index directly instead of matching by application name (implies `--pulse`).
- `-l`, `--list-sinks`: list active PulseAudio sink inputs and save your choice as the default `--pulse` app.
- `-L`, `--log-curve`: use a logarithmic fade curve instead of linear (default off, or `LOG_CURVE` from the config file if set).
- `-q`, `--quiet`: suppress the "Fading..."/"Done." progress messages. Errors still print.
- `-n`, `--dry-run`: print what would happen without changing anything.
- `-h`, `--help`: show usage and exit.

Only one fade/toggle runs at a time; a second invocation while one is already in progress exits immediately with an error rather than racing the first one's volume changes. Interrupting a fade with Ctrl+C (or `SIGTERM`) jumps straight to the target volume before exiting, instead of leaving it stuck partway through.

Example usage:

```bash
mpc-fade.sh 60 30        # fade current volume to 60% over 30 seconds
mpc-fade.sh 0 5          # fade out to 0% over 5 seconds
mpc-fade.sh -t           # fade out / toggle play-pause / fade back in
mpc-fade.sh -t -P -s 3   # same, fading the PulseAudio stream over 3s
mpc-fade.sh -l           # pick and save a default --pulse app
mpc-fade.sh 0 5 -q       # fade out silently, e.g. from a cronjob
mpc-fade.sh 0 5 -L       # fade out on a logarithmic curve
mpc-fade.sh 60 30 -n     # preview a fade without changing anything
```

Typical usage in shell scripts or cronjobs:

```bash
mpc stop
mpc clear
mpc volume 15          # start with volume 15%
mpc load "Radio Fantasy"
mpc play
mpc-fade.sh 60 30      # fade to volume 60% within 30 sec
sleep $((60*5))        # play for 5 min
mpc-fade.sh 0 5        # fade to volume 0% within 5 sec
mpc stop
```

## Acknowledgments

Combines and builds on two gists: [mpc-fade](https://gist.github.com/koppi/60b9d1f14b0af2bdde1e49b9c225649d) by [koppi](https://gist.github.com/koppi), which fades MPD's own volume to a target level over a duration, and [mpc-fade](https://gist.github.com/Pablo1107/1d61cfa39e683289d96301230bf88fa5) by [Pablo1107](https://gist.github.com/Pablo1107), which fades the PulseAudio sink-input volume around a play/pause toggle.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
