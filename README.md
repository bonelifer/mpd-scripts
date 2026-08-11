<h1 align="center">
  <a href="https://github.com/bonelifer/mpd-scripts">
    <!-- Please provide path to your logo here -->
    <img src="./docs/images/logo.png" alt="Logo" width="100" height="100">
  </a>
</h1>

<div align="center">
  mpd-scripts
</div>

<div align="center">
<br />

[![GPLv3 license](https://img.shields.io/badge/License-GPLv3-blue.svg)](http://perso.crans.org/besson/LICENSE.html)

[![GitHub](https://badgen.net/badge/icon/github?icon=github&label)](https://github.com)
[![made-with-python](https://img.shields.io/badge/Made%20with-Python-1f425f.svg)](https://www.python.org/)
[![made-with-claude](https://img.shields.io/badge/Made%20with-Claude-1f425f.svg)](https://www.anthropic.com/claude)
![Static Badge](https://img.shields.io/badge/Some_made_with-ChatGPT-1f425f)
[![made-with-bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![Pull Requests welcome](https://img.shields.io/badge/PRs-welcome-ff69b4.svg?style=flat-square)](https://github.com/bonelifer/mpd-scripts/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22)
[![code with love by bonelifer](https://img.shields.io/badge/%3C%2F%3E%20with%20%E2%99%A5%20by-bonelifer-ff1414.svg?style=flat-square)](https://github.com/bonelifer)

</div>

---

## About
Collection of scripts related to mpd & mpc.

| Name              | Description              |
| --- | --- |
| **[lastfm-love](./lastfm-love/)** | Love or unlove tracks on lastfm |
| **[mpd-notifier](./mpd-notifier/)** | Notify users of playing track or mpd status with artwork |
| **[Tunein Radio Script](./tunein-radio/)** | Fetches Tunein Radio station URLs and generates M3U playlists along with associated information. Uses StreamFinder::Tunein Perl module. |
| **[iHeartRadio Script](./iheart-radio/)** | Fetches iHeartRadio station URLs and generates M3U playlists along with associated information. Uses StreamFinder::IHeartRadio Perl module. |
| **[volume](./volume/)** | Scripts allowing you to control the volume. |
| **[mpd-queue-shuffle](./mpd-queue-shuffle/)** | This script generates a random playlist from a local music directory and saves it as an M3U playlist file in the specified playlist directory.  |
| **[somafm](./somafm/)** | This script fetches the playlist URLs of SomaFM channels with the highest quality in MP3 format and creates separate playlists for each channel in extended M3U format with the channel name. |
| **[mpd-find-dup](./mpd-find-dup/)** | Contains two scripts for deduplicating MPD queues: `mpd-remove-duplicates-queue.sh` interactively deletes duplicates from the current MPD playlist in-place, while `mpd-deduplicate-save-and-reload.sh` saves the current queue as a playlist, removes duplicates, then reloads the cleaned playlist. |
| **[mpd_rewind_daemon](./mpd_rewind_daemon/)** | A background daemon for MPD that automatically rewinds playback by a few seconds when resuming from pause, improving the experience for music, mixes, podcasts, and audiobooks. |
| **[mpd-smart-shuffle](./mpd-smart-shuffle/)** | A smarter shuffle: a background monitor records play/skip history, and a cron-run script tops up the MPD queue avoiding recent repeats, with optional weighted selection, artist/album diversity, seasonal and time-of-day genre filtering, exclude lists, and more. |
| **[mpdsimilar](./mpdsimilar/)** | Fetches similar artist tracks from Last.fm for the currently playing track or every track in the queue, and adds a sample of them to the MPD queue. |
| **[rm-duplicates-playlist](./rm-duplicates-playlist/)** | Removes duplicate entries from a saved MPD playlist or the current queue, or lists available playlists, combining what the two `mpd-find-dup` scripts each do separately into one tool. |
| **[rm-artists-playlist](./rm-artists-playlist/)** | Removes songs by a list of artists from a saved MPD playlist or the current queue, or lists available playlists. |
| **[mpd-add-random-artist](./mpd-add-random-artist/)** | Adds a random sample of a specified artist's tracks to the current MPD queue, matching exactly by default or loosely with `-l`. |
| **[mpd-add-random](./mpd-add-random/)** | Adds a random selection of tracks from the local music library to the current MPD queue. |
| **[add-current-song](./add-current-song/)** | Adds the currently playing MPD song to an M3U playlist, with duplicate prevention, sorting, locking, and atomic rewrites. |
| **[mpd-tray-icon](./mpd-tray-icon/)** | A GTK3 tray icon showing the currently playing MPD track, with Play/Pause/Next/Previous controls. |
| **[mpd-radio-tray](./mpd-radio-tray/)** | A PyQt5 system tray app for managing and playing categorized internet radio station URLs with MPD, similar to RadioTray-NG. |
| **[music_queue_manager](./music_queue_manager/)** | Manages song ratings and "bad" flags via MPD stickers: rate on a 5- or 10-point scale, flag/unflag broken songs, remove or jump to a random/top-rated song, and list or rescale ratings. |
| **[mpdmark](./mpdmark/)** | Bookmark playback positions in MPD via stickers, with multiple named bookmarks per song, listing, loading, renaming, deleting, and pruning stale entries. |
| **[alarmpd](./alarmpd/)** | Playlist-named alarm clock daemon: schedule alarms by creating/renaming an MPD playlist, with multi-day/named-group and one-shot forms, per-alarm volume caps, gentle fade-in with snooze, one-time skip, and collision detection. |
| **[mpd-kb-control](./mpd-kb-control/)** | Dispatches multimedia-key presses (play/pause/next/prev/volume/mute) to MPD, plus consume/random/repeat/single mode toggles for a separate keypad, for binding in a window manager's keybindings. |
| **[mpd-auto-stop](./mpd-auto-stop/)** | Sleep-timer daemon with a web UI: start/extend/cancel a countdown, and it fades the volume out and pauses MPD when it fires instead of cutting off abruptly. |
| **[mpd-recent-tracks](./mpd-recent-tracks/)** | Generates an M3U playlist (newest first) of music files added or modified in the last N days, optionally capped in size and auto-loaded into MPD, paused or playing. |
| **[mpc-fade](./mpc-fade/)** | Fades MPD playback volume smoothly to a target level over a duration, or fades out/toggles play-pause/fades back in, using either MPD's own volume or a PulseAudio sink-input stream. |
| **[playpause](./playpause/)** | Prints the currently playing MPD track prefixed with a play/pause symbol, for use in a status bar (polybar, i3blocks, xmobar, etc). |

### Prerequisites
Listed in each script's README.md.


### Installation
Run [`./install.sh`](./install.sh) once — no manual copying needed. It:

1. Migrates any existing per-script settings from the old `~/.config/<script-name>/` layout into the new unified `~/.config/mpd-scripts/<script-name>/` layout (see Configuration below).
2. Checks whether a personal bin directory is already on your `PATH`, and, if not, creates `~/bin` and adds it for you. It also offers to create `~/bin/music` and add it to your `PATH` too, an optional separate directory for installing this repo's scripts, kept apart from other personal scripts in `~/bin`.
3. Offers to install any missing apt/pip/cpan dependencies the scripts below need (`mpc`, `curl`, `jq`, PyQt5, PyGObject/GTK3, `pylast`, `python-mpd2`, the Perl `StreamFinder` modules, etc.).
4. Copies every standalone script (and whatever companion file it needs alongside it, e.g. a `.conf.example` template or a station list) into the directory from step 2, and installs MPD Notifier via its own installer.
5. Offers to install the optional MPD Rewind Daemon, prompting you to choose between two methods (`install-xdg-autostart.sh` or `install-systemd.sh`, with a clear recommendation either way — see [`mpd_rewind_daemon/README.md`](./mpd_rewind_daemon/) for details); the optional [`mpd-smart-shuffle`](./mpd-smart-shuffle/) tool (history-aware smarter shuffle, with its own optional `systemd --user` background monitor); the optional [`alarmpd`](./alarmpd/) tool (playlist-named alarm clock daemon, with the same XDG-autostart/systemd `--user` install choice); the optional [`mpd-auto-stop`](./mpd-auto-stop/) tool (sleep-timer web UI daemon, same install choice again); and the optional volume control scripts, prompting you to choose between the `mpc`- and `python-mpd2`-based variants (installing only one, since both use the same filenames).

Check each script's own README for usage notes once it's installed.

## Contributing

Contributions are welcome!

- **Bug reports**: [Open an issue](https://github.com/bonelifer/mpd-scripts/issues).
- **Everything else** (questions, feature requests, ideas, general discussion): [Use Discussions](https://github.com/bonelifer/mpd-scripts/discussions).
- Pull requests are welcome for bug fixes or discussed features.

## Acknowledgments

- The original setup of this repository is by [William Jacoby](https://github.com/bonelifer). For a full list of all authors and contributors, see [the contributors page](https://github.com/bonelifer/mpd-scripts/contributors).
- [mpc-fade](./mpc-fade/) combines and builds on gists by [koppi](https://gist.github.com/koppi/60b9d1f14b0af2bdde1e49b9c225649d) and [Pablo1107](https://gist.github.com/Pablo1107/1d61cfa39e683289d96301230bf88fa5).
- [playpause](./playpause/) is based on a [gist](https://gist.github.com/fernandotakai/8138704) by [fernandotakai](https://gist.github.com/fernandotakai).
- [mpdmark](./mpdmark/) is based on `mpdmark` from [Mic92/mpdtools](https://github.com/Mic92/mpdtools).
- [alarmpd](./alarmpd/) is based on [alarmpd](https://github.com/ingobecker/alarmpd) by Ingo Becker.
- [mpd-kb-control](./mpd-kb-control/) is based on [mpd_kb_control](https://github.com/nogaems/mpd_kb_control) by nogaems.
- [mpd-auto-stop](./mpd-auto-stop/) is based on [mpd_auto_stop](https://github.com/vms20591/mpd_auto_stop) by Meenakshi Sundaram V.
- Documentation updates assisted by [Claude](https://www.anthropic.com/claude).

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](LICENSE) for more information.

