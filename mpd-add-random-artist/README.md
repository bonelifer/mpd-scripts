# Random Artist Track Adder

This script finds tracks by a specified artist and adds a random sample of them to the current MPD queue.

## Features

- Adds a configurable number of random tracks by an artist to the queue (`-t`/`--tracks`, default `10`).
- Matches the artist **exactly** by default (`mpc find`, case-sensitive), so unrelated artists whose name happens to contain the same substring aren't pulled in.
- `-l`/`--loose` switches to a substring, case-insensitive match (`mpc search`) instead, for when you're unsure of the exact spelling/capitalization, or want to catch variant taggings of the same artist. Loose matching can also pull in unrelated artists whose name merely contains the given string (e.g. `"Air"` loosely matching `"Air Supply"`), so prefer the exact default when you know the artist name precisely.
- If an exact match finds nothing, the script suggests retrying with `-l`/`--loose`.
- A track that fails to add is reported as a warning rather than aborting the whole run — the rest still get added.

## Requirements

- `mpc`

## Usage

```bash
./mpd-add-random-artist.sh [-t NUMBER] [-l] ARTIST_NAME
```

- `-t`, `--tracks NUMBER`: Number of random tracks to add (default: `10`).
- `-l`, `--loose`: Substring, case-insensitive match instead of the default exact match.

Example usage:

```bash
./mpd-add-random-artist.sh "The Beatles"          # Adds 10 random Beatles tracks (exact match)
./mpd-add-random-artist.sh -t 5 "Pink Floyd"      # Adds 5 random Pink Floyd tracks
./mpd-add-random-artist.sh -l "floyd"             # Loose match: catches "Pink Floyd" and similar
```

## Example Output

```bash
Added 5 random tracks by Pink Floyd to the queue.
Queue position: 3/28
```

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
