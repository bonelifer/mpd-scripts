# mpd-scripts - Tunein Radio Script

#### Based on the [StreamFinder::Tunein Perl Module](https://metacpan.org/pod/StreamFinder::Tunein) ([documentation](https://metacpan.org/pod/StreamFinder::Tunein)) for interacting with Tunein Radio stations.

### Description

This script interacts with the StreamFinder::Tunein Perl module to fetch Tunein Radio station URLs and generates M3U playlists along with associated information.

The script automates the process of fetching station URLs, generating M3U playlists, and acquiring relevant information.

### Installation

To use this script, ensure you have the following prerequisites installed:
- Perl
- StreamFinder::Tunein Perl module

You can install the StreamFinder::Tunein Perl module using CPAN:
```
sudo apt install cpanminus   # (if cpanm is not installed)
sudo cpanm StreamFinder::Tunein
```
### Usage

Ensure you have the StreamFinder::Tunein Perl module installed to utilize this script effectively.

Run the script with appropriate arguments or configuration to fetch station URLs, generate M3U playlists, and gather associated station information.

Each station is retried automatically up to 3 times before being skipped; override this with `--retries=N` (or `-r N`). Pass `--skip-existing` (or `-s`) to re-run the script multiple times without redoing stations that already succeeded in a previous run:

```
perl tunein.pl -s -r 5
```

Completed stations are tracked as marker files under `playlists/.completed/`; delete that directory (or an individual marker) to force a station to be re-fetched.

### Configuration

Station URLs live in [`stations.txt`](./stations.txt), one tunein.com URL per line (blank lines and `#`-prefixed comments are ignored) — edit that file to add or remove stations instead of editing `tunein.pl`. By default the script reads `stations.txt` next to itself; point it at a different file with `--stations=FILE` (or `-f FILE`).

By default the playlist/image filenames are derived from the station's title as fetched from tunein.com. To pin a specific filename instead, append it after a comma: `https://tunein.com/radio/some-station-s12345/,My Station Name`.

### License

This project is licensed under the **GNU General Public License v3.0**. For more information, see [LICENSE](../LICENSE).

