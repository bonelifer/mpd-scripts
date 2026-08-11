# mpdmark

Bookmark playback positions in MPD, keyed by name, using the sticker database.

## Features

- **Named bookmarks**: save more than one bookmark per song (e.g. `intro`, `chapter5` on the same audiobook file) instead of a single implicit position.
- **List**: view every bookmark across the whole library, numbered for use with `load`/`del`/`rename`.
- **Load**: queue (if needed) and seek to any saved bookmark, even for a song that isn't currently playing.
- **Delete**: remove a single bookmark, by list number or by `--song`/`--name`.
- **Rename**: change a bookmark's name without losing its saved position.
- **Prune**: clean up bookmarks left behind on songs no longer in the library.
- **Stable addressing**: `del`/`load`/`rename` accept `--song`/`--name` as an alternative to the list index, which stays correct even if the bookmark set has changed since you last ran `list`.

## Requirements

- Python 3
- [`python-mpd2`](https://pypi.org/project/python-mpd2/) (`pip install --user python-mpd2`)
- MPD 0.15 or later with sticker support enabled (`sticker_file` set in `mpd.conf`)

## Configuration

On first run, a config file is created at
`~/.config/mpd-scripts/mpdmark/mpdmark.conf`, seeded from
[`mpdmark.conf.example`](./mpdmark.conf.example). Edit the copy there, not
the template.

| Setting | Description | Default |
| --- | --- | --- |
| `mpd_host` | MPD server hostname/IP | `localhost` |
| `mpd_port` | MPD server port | `6600` |
| `mpd_password` | MPD password, if required (leave blank if none) | *(blank)* |

`-H`/`--host`, `-P`/`--port`, and `-a`/`--password` override the config file for a single invocation.

## Usage

```
mpdmark.py [-H HOST] [-P PORT] [-a PASSWORD] {list,del,save,load,rename,prune} ...
```

| Command | Description |
| --- | --- |
| `list` | List all bookmarks, numbered. |
| `save [-n NAME]` | Save the current song's playback position under `NAME` (default: `default`). |
| `load [index]` \| `load -s SONG -n NAME` | Queue (if needed) and jump to a bookmark, by list index (default: `1`) or by song + name. |
| `del [index]` \| `del -s SONG -n NAME` | Delete a bookmark, by list index (default: `1`) or by song + name. |
| `rename [index] -t NEW_NAME` \| `rename -s SONG -n NAME -t NEW_NAME` | Rename a bookmark, keeping its saved position. |
| `prune` | Remove bookmarks for songs no longer in the library. |

`-s`/`--song` and `-n`/`--name` must be used together, and can't be combined with an index — they're an alternative addressing mode, not a filter.

### Examples

```bash
# Bookmark the current position as "chapter5"
mpdmark.py save -n chapter5

# Bookmark the current position with the default name
mpdmark.py save

# See everything you've bookmarked
mpdmark.py list

# Jump back to bookmark #2
mpdmark.py load 2

# Jump back to a bookmark by song + name instead of list index
mpdmark.py load -s "Audiobooks/Dune/01.mp3" -n chapter5

# Remove bookmark #2
mpdmark.py del 2

# Rename a bookmark
mpdmark.py rename -s "Audiobooks/Dune/01.mp3" -n chapter5 -t "part-one"

# Clean up bookmarks for songs that were deleted from the library
mpdmark.py prune

# Connect to a remote MPD server
mpdmark.py -H mpd.example.com -P 6600 list
```

## How it works

Each song's bookmarks are stored as a single JSON-encoded `bookmark` sticker (e.g. `{"intro": 12.0, "chapter5": 941.5}`), so listing every bookmark in the library only takes one `sticker find` call regardless of how many songs or names are involved. `list`'s numbering reflects the current bookmark set sorted by file then name, so it can shift if bookmarks are added or removed between calls; use `--song`/`--name` instead of an index for `del`/`load`/`rename` if the call isn't immediately following a `list`. MPD doesn't clean up stickers when a file disappears from the library, so run `prune` occasionally (or after a library reorganization) to clear out bookmarks left on deleted or moved files.

## Acknowledgments

Based on `mpdmark` from [Mic92/mpdtools](https://github.com/Mic92/mpdtools), ported to Python 3 and the maintained `python-mpd2` library, with named/multiple bookmarks per song added on top of the original single-bookmark-per-song design.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
