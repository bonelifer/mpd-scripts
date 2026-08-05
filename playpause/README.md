# mpd-scripts - playpause

Prints the currently playing MPD track, prefixed with a play/pause symbol, for use in a status bar (polybar, i3blocks, xmobar, etc).

## Features

- **Play/pause/stop indicator**: prints `► <title>` while MPD is playing, `∎∎ <title>` while paused, or just `■` when stopped (MPD reports no current-track line in that state, so no title is shown).
- **Configurable symbols**: the three symbols above can be overridden in the config file.
- **Title truncation**: `-l`/`--max-len LEN` truncates a long title to `LEN` characters with a trailing ellipsis, so it doesn't overflow a fixed-width status bar module. Off by default; can be made the default via the config file.
- **Empty-title fallback**: if `mpc` reports a blank current-track line (e.g. some internet radio streams with no tags), prints a configurable placeholder instead of a bare symbol with trailing whitespace.
- **Silent failure**: prints nothing if `mpc` fails (e.g. MPD isn't running), instead of cluttering the status bar with an error.

## Requirements

- `mpc`
- Bash 4 or later

## Configuration

Optional. `SYMBOL_PLAYING`, `SYMBOL_PAUSED`, `SYMBOL_STOPPED`, `MAX_LEN`, and `FALLBACK_TITLE` live in `~/.config/mpd-scripts/playpause/playpause.conf`, seeded from [`playpause.conf.example`](./playpause.conf.example). Without a config file, the built-in defaults shown in the example apply. Edit the copy in `~/.config/mpd-scripts/playpause/`, not the template.

## Usage

```bash
playpause.sh [-l LEN] [-h]
```

- `-l`, `--max-len LEN`: truncate the title to `LEN` characters, with an ellipsis when cut short (default: no limit, or `MAX_LEN` from the config file if set).
- `-h`, `--help`: show usage and exit.

Typical usage is wiring it up as a polybar/i3blocks custom script that polls on an interval or refreshes on an MPD event.

Example polybar module:

```ini
[module/mpd-playpause]
type = custom/script
exec = ~/bin/music/playpause.sh --max-len 40
interval = 2
```

## Acknowledgments

Based on a [gist](https://gist.github.com/fernandotakai/8138704) by [fernandotakai](https://gist.github.com/fernandotakai).

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
