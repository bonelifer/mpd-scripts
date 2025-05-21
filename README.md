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
| **[stats](./stats/)** | Scripts providing statistical information about music files. |
| **[mpd-queue-shuffle](./mpd-queue-shuffle/)** | This script generates a random playlist from a local music directory and saves it as an M3U playlist file in the specified playlist directory.  |
| **[somafm](./somafm/)** | This script fetches the playlist URLs of SomaFM channels with the highest quality in MP3 format and creates separate playlists for each channel in extended M3U format with the channel name. |
| **[mpd-find-dup](./mpd-find-dup/)** | Contains two scripts for deduplicating MPD queues: `mpd-remove-duplicates-queue.sh` interactively deletes duplicates from the current MPD playlist in-place, while `mpd-deduplicate-save-and-reload.sh` saves the current queue as a playlist, removes duplicates, then reloads the cleaned playlist. |
| **[mpd_rewind_daemon](./mpd_rewind_daemon/)** | A background daemon for MPD that automatically rewinds playback by a few seconds when resuming from pause, improving the experience for music, mixes, podcasts, and audiobooks. |

### Prerequisites
Listed in each scripts README.md.


### Installation
Add the desired scripts to a directory in your path.

## Support
Reach out to the maintainer at one of the following places:

- [GitHub Discussions](https://github.com/bonelifer/mpd-scripts/discussions)
- <a href="https://github.com/bonelifer/mpd-scripts/issues/new?assignees=&labels=bug&template=01_BUG_REPORT.md&title=bug%3A+">Report a Bug</a>
- <a href="https://github.com/bonelifer/mpd-scripts/issues/new?assignees=&labels=enhancement&template=02_FEATURE_REQUEST.md&title=feature%3A+">Request a Feature</a>

## Project assistance
If you want to say **thank you** or/and support active development of mpd-scripts:

- Add a [GitHub Star](https://github.com/bonelifer/mpd-scripts) to the project.
- See the [open issues](https://github.com/bonelifer/mpd-scripts/issues) for a list of proposed features (and known issues).

## Contributing
First off, thanks for taking the time to contribute! Contributions are what make the open-source community such an amazing place to learn, inspire, and create. Any contributions you make will benefit everybody else and are **greatly appreciated**.

Please read [our contribution guidelines](docs/CONTRIBUTING.md), and thank you for being involved!

## Authors & contributors

The original setup of this repository is by [William Jacoby](https://github.com/bonelifer).

For a full list of all authors and contributors, see [the contributors page](https://github.com/bonelifer/mpd-scripts/contributors).

## License

This project is licensed under the **GNU General Public License v3**.

See [LICENSE](LICENSE) for more information.

