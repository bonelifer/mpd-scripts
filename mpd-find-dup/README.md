# MPD Duplicate Removal Scripts

## Overview

This repository contains two scripts for managing duplicate entries in your MPD (Music Player Daemon) queue or playlists:

1. **`mpd-remove-duplicates-queue.sh`**: Identifies and removes duplicate entries directly from the current MPD queue.
2. **`mpd-deduplicate-save-and-reload.sh`**: Saves the current queue to a playlist, removes duplicates from the saved file, and reloads the cleaned playlist back into MPD.

## Requirements

- **MPD (Music Player Daemon)**: Installed and configured.
- **MPC (Music Player Client)**: Installed and working.
- `awk`: Required by the second script for duplicate removal in playlist files.

## Scripts

---

### `mpd-remove-duplicates-queue.sh`

#### Description

This script scans the current MPD queue and removes duplicate entries based on file names. It operates directly on the in-memory queue.

#### Usage

```bash
./mpd-remove-duplicates-queue.sh
````

#### What It Does

1. Scans the MPD queue for the first duplicate file.
2. Deletes the first occurrence of the duplicate.
3. Repeats until no duplicates remain.

#### Example Output

```bash
Deleting duplicate at position 5...
Deleting duplicate at position 12...
No more duplicates found.
```

---

### `mpd-deduplicate-save-and-reload.sh`

#### Description

This script saves the current MPD queue to a `.m3u` playlist file, removes duplicate entries from that file (preserving order), and reloads the cleaned playlist back into MPD.

#### Configuration

Edit the following variable at the top of the script to match your environment:

```bash
PLAYLIST_DIR="/path/to/your/mpd/playlists/"
```

#### Usage

```bash
./mpd-deduplicate-save-and-reload.sh
```

#### What It Does

1. Saves the current MPD queue as a playlist.
2. Removes duplicate entries in the `.m3u` file using `awk`, preserving order.
3. Clears the current queue and reloads the cleaned playlist.

#### Example Output

```bash
Saving current queue to playlist file...
Removing duplicates from playlist file...
Clearing current MPD queue...
Reloading cleaned playlist into MPD...
Playlist reloaded.
Duplicate removal complete.
```

---

## Which Script Should I Use?

| Script                               | Best For                                                  | Speed                 | Requirements                                 |
| ------------------------------------ | --------------------------------------------------------- | --------------------- | -------------------------------------------- |
| `mpd-remove-duplicates-queue.sh`     | Removing duplicates **remotely** or via MPD commands only | Slower on large lists | MPD access only (no file access needed)      |
| `mpd-deduplicate-save-and-reload.sh` | Running **locally** on the same machine as MPD            | **Faster**            | Direct access to `.mpd/playlists/` directory |

**Note**:
`mpd-deduplicate-save-and-reload.sh` is significantly faster when you have direct file system access to the computer running MPD—ideal for local setups.

---

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
