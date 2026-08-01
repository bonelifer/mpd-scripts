# mpd-scripts - iHeartRadio Script

#### Based on the [StreamFinder::IHeartRadio Perl Module](https://metacpan.org/pod/StreamFinder::IHeartRadio) ([documentation](https://metacpan.org/pod/StreamFinder::IHeartRadio)) for interacting with iHeartRadio stations.

### Description

This script interacts with the StreamFinder::IHeartRadio Perl module to fetch iHeartRadio station URLs and generates M3U playlists along with associated information.

The script automates the process of fetching station URLs, generating M3U playlists, and acquiring relevant information.

### Installation

To use this script, ensure you have the following prerequisites installed:
- Perl
- StreamFinder::IHeartRadio Perl module

You can install the StreamFinder::IHeartRadio Perl module using CPAN:
```
sudo apt install cpanminus   # (if cpanm is not installed)
sudo cpanm StreamFinder::IHeartRadio
```
### Usage

Ensure you have the StreamFinder::IHeartRadio Perl module installed before running this script.

`--download` (or `-d`) is required to actually fetch anything; running the script with no arguments (or without `-d`) just prints usage and exits.

iheart.com intermittently serves a page without the embedded stream data it needs, so a station may fail even though it's valid. Each station is retried automatically up to 3 times before being skipped; override this with `--retries=N` (or `-r N`). Pass `--skip-existing` (or `-s`) to also let you re-run the script multiple times without redoing stations that already succeeded in a previous run:

```
perl iheart.pl -d -s -r 5
```

Completed stations are tracked as marker files under `playlists/.completed/`; delete that directory (or an individual marker) to force a station to be re-fetched.

### Configuration

Station URLs live in [`iheart-stations.txt`](./iheart-stations.txt), one iheart.com URL per line (blank lines and `#`-prefixed comments are ignored) — edit that file to add or remove stations instead of editing `iheart.pl`. By default the script reads `iheart-stations.txt` next to itself; point it at a different file with `--stations=FILE` (or `-f FILE`).

By default the playlist/image filenames are derived from the station's title as fetched from iheart.com. To pin a specific filename instead, append it after a comma: `https://www.iheart.com/live/some-station/,My Station Name`.

### License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.

