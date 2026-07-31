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
###
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
| **[mpdsimilar](./mpdsimilar/)** | Fetches similar artist tracks from Last.fm for the currently playing track or every track in the queue, and adds a sample of them to the MPD queue. |
| **[rm-duplicates-playlist](./rm-duplicates-playlist/)** | Removes duplicate entries from a saved MPD playlist or the current queue, or lists available playlists, combining what the two `mpd-find-dup` scripts each do separately into one tool. |

### Prerequisites
Listed in each scripts README.md.


### Installation
Run [`./setup-path.sh`](./setup-path.sh) once to check whether a personal bin directory is already on your `PATH`, and, if not, create `~/bin` and add it for you.

Most scripts in this repository are standalone and only need to be copied into a directory on your `$PATH` (e.g. `~/bin` or `~/.local/bin`) and marked executable:

```bash
cp <script-dir>/<script-name> ~/bin/
chmod +x ~/bin/<script-name>
```

Check each script's own README for language-specific dependencies (Python, Perl, `mpc`/`python-mpd2`, etc.) before running it.

`mpd_rewind_daemon` ships its own installer instead:

```bash
cd mpd_rewind_daemon
./install.sh
```

See [`mpd_rewind_daemon/README.md`](./mpd_rewind_daemon/) for details.

## Contributing

Contributions are welcome!

- **Bug reports**: [Open an issue](https://github.com/bonelifer/mpd-scripts/issues).
- **Everything else** (questions, feature requests, ideas, general discussion): [Use Discussions](https://github.com/bonelifer/mpd-scripts/discussions).
- Pull requests are welcome for bug fixes or discussed features.

## Acknowledgments

- The original setup of this repository is by [William Jacoby](https://github.com/bonelifer). For a full list of all authors and contributors, see [the contributors page](https://github.com/bonelifer/mpd-scripts/contributors).
- Documentation updates assisted by [Claude](https://www.anthropic.com/claude).

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](LICENSE) for more information.

