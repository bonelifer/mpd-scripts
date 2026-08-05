# Music Queue Manager

## Description
This script allows you to interact with the music queue and manage song ratings and statuses using "stickers." The stickers feature is used to label songs, such as marking them as "broken" or applying ratings. The script supports several features including:

- Rating songs on a 5- or 10-point scale.
- Flagging songs as "bad" (broken), and clearing that flag.
- Removing the current song from the queue.
- Listing all songs marked as bad.
- Jumping to a random song in the queue.
- Jumping to a top-rated song.
- Viewing ratings for the whole library or a specific directory.
- Rescaling all stored ratings after changing the rating scale.

Compatible with clients like Cantata, mpedv, and myMPD.

## Features
- **Rate songs**: Assign a rating to the currently playing song.
- **Flag songs as broken**: Mark a song as "bad" if it is broken or problematic.
- **Unflag songs as broken**: Clear the "bad" flag from the current song.
- **Remove songs**: Remove the current song from the queue.
- **Jump to random song**: Skip to a random song in the queue.
- **Jump to a top-rated song**: Queue and play a top-rated song.
- **List bad songs**: View all songs marked as "bad" (broken).
- **List song ratings**: Display ratings for songs across the whole library or within a specified directory.
- **Rescale ratings**: Convert all stored ratings from one scale to another.

## Requirements
- `mpc` command-line utility for interacting with MPD.

## Configuration
On first run, a config file is created at
`~/.config/mpd-scripts/music_queue_manager/music_queue_manager.conf`, seeded
from `music_queue_manager.conf.example`. Edit the copy there, not the
template.

- **RATING_SCALE**: `5` or `10` (default `10`). Sets the maximum value
  accepted by `rate` and shown in usage. Changing this does not convert
  ratings already stored under the old scale — run `rescale` afterwards.
- **TOP_RATED_MODE**: `single` or `random` (default `single`). Controls how
  `top_rated` breaks ties for the highest rating: always the same song
  (`single`) or a random pick among the tied songs (`random`).

## Usage
### General Usage
```bash
$ ./music_queue_manager.sh <command> <args>
```

### Available Commands
- **remove**: Remove the current song from the queue.
- **random**: Jump to a random song in the queue.
- **flag_bad**: Flag the current song as "bad" (broken).
- **unflag_bad**: Clear the "bad" flag on the current song.
- **list_bad**: List all songs marked as "bad."
- **rate <0-N>**: Rate the current song, where N is `RATING_SCALE` from the config file (5 or 10).
- **ratings [dir]**: List ratings for all songs, optionally scoped to `[dir]`. Omit `[dir]` to list the whole library.
- **rescale <old> <new>**: Convert every stored rating from the `<old>` scale to the `<new>` scale (e.g. after changing `RATING_SCALE`).
- **top_rated**: Queue and jump to a top-rated song. Tie-breaking is controlled by `TOP_RATED_MODE`.

### Examples
- **Remove the current song from the queue**:
    ```bash
    $ ./music_queue_manager.sh remove
    ```

- **Jump to a random song**:
    ```bash
    $ ./music_queue_manager.sh random
    ```

- **Flag the current song as "bad"**:
    ```bash
    $ ./music_queue_manager.sh flag_bad
    ```

- **List all songs marked as "bad"**:
    ```bash
    $ ./music_queue_manager.sh list_bad
    ```

- **Rate the current song** (e.g., a rating of 7):
    ```bash
    $ ./music_queue_manager.sh rate 7
    ```

- **List ratings for songs in a specific directory**:
    ```bash
    $ ./music_queue_manager.sh ratings /path/to/music
    ```

- **List ratings for the whole library**:
    ```bash
    $ ./music_queue_manager.sh ratings
    ```

- **Clear the "bad" flag on the current song**:
    ```bash
    $ ./music_queue_manager.sh unflag_bad
    ```

- **Rescale all ratings after switching from a 10-point to a 5-point scale**:
    ```bash
    $ ./music_queue_manager.sh rescale 10 5
    ```

- **Jump to a top-rated song**:
    ```bash
    $ ./music_queue_manager.sh top_rated
    ```

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.

