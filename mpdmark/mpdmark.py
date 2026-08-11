#!/usr/bin/env python3

"""
mpdmark

Bookmark playback positions in MPD using the sticker database (requires
MPD >= 0.15 with sticker support enabled).

Each song can hold multiple named bookmarks, stored as a single JSON-encoded
"bookmark" sticker per song (e.g. {"intro": 12.0, "chapter5": 941.5}), so one
MPD sticker_find call is enough to list every bookmark in the library. The
`list` command prints a flat, numbered view across all songs/names; `load`,
`del`, and `rename` address entries by that number, or by an explicit
--song/--name pair that stays valid even if the numbering has shifted.
`prune` removes bookmarks left behind on songs no longer in the library.

Connection settings (host/port/password) come from
~/.config/mpd-scripts/mpdmark/mpdmark.conf, seeded from mpdmark.conf.example
on first run; --host/--port/--password on the command line override the
config file for a single invocation.
"""

import argparse
import configparser
import json
import os
import sys
from os.path import basename

from mpd import MPDClient, CommandError
from socket import error as SocketError

STICKER_NAME = "bookmark"
DEFAULT_BOOKMARK_NAME = "default"

CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".config", "mpd-scripts", "mpdmark")
CONFIG_FILE = os.path.join(CONFIG_DIR, "mpdmark.conf")


def load_config() -> configparser.SectionProxy:
    """Load ~/.config/mpd-scripts/mpdmark/mpdmark.conf, seeding it from the
    mpdmark.conf.example template shipped alongside this script on first run.

    Returns:
        configparser.SectionProxy: the "mpdmark" section.
    """
    if not os.path.exists(CONFIG_FILE):
        os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
        template = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mpdmark.conf.example")
        with open(template) as src, open(CONFIG_FILE, "w") as dst:
            dst.write(src.read())
        os.chmod(CONFIG_FILE, 0o600)  # May contain an MPD password

    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    return config["mpdmark"]


def die(msg: str) -> None:
    """Print an error message to stderr and exit with status 1."""
    sys.stderr.write(msg)
    sys.stderr.write("\n")
    sys.exit(1)


def format_time(seconds: float) -> str:
    """Format a duration in seconds as MM:SS, or HH:MM:SS if an hour or more."""
    seconds = int(seconds)
    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    if hours == 0:
        return f"{minutes:02d}:{seconds:02d}"
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"


def get_elapsed(status: dict) -> float:
    """Return the current playback position in seconds from MPD's "elapsed" status field."""
    return float(status["elapsed"])


class App:
    def get_song_bookmarks(self, uri: str) -> dict:
        """Return the {name: elapsed_seconds} bookmark dict stored on a song, or {} if none."""
        try:
            raw = self._client.sticker_get("song", uri, STICKER_NAME)
        except CommandError:
            return {}
        try:
            return json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            return {}

    def set_song_bookmarks(self, uri: str, bookmarks: dict) -> None:
        """Store (or, if empty, delete) a song's bookmark dict."""
        if bookmarks:
            self._client.sticker_set("song", uri, STICKER_NAME, json.dumps(bookmarks))
        else:
            try:
                self._client.sticker_delete("song", uri, STICKER_NAME)
            except CommandError:
                pass

    def get_all_bookmarks(self) -> list[tuple[str, str, float]]:
        """Return every (uri, name, elapsed_seconds) bookmark in the library.

        Sorted by uri then name so the numbering `list` prints stays stable
        between calls as long as the bookmark set itself hasn't changed.
        """
        entries = []
        for row in self._client.sticker_find("song", "/", STICKER_NAME):
            uri = row["file"]
            _, _, raw_value = row["sticker"].partition("=")
            try:
                bookmarks = json.loads(raw_value)
            except (json.JSONDecodeError, TypeError):
                continue
            for name, elapsed in bookmarks.items():
                entries.append((uri, name, float(elapsed)))
        entries.sort(key=lambda entry: (entry[0], entry[1]))
        return entries

    def list_bookmarks(self, args: argparse.Namespace) -> None:
        """Print every bookmark in the library, numbered for use with load/del."""
        for i, (uri, name, elapsed) in enumerate(self.get_all_bookmarks(), start=1):
            info = self._client.listallinfo(uri)[0]
            total = format_time(float(info["time"]))
            title = info.get("title", basename(uri))
            print(f"({i}) [{name}] {format_time(elapsed)}/{total} {title}")

    def resolve_target(self, args: argparse.Namespace) -> tuple[str, str, float]:
        """Resolve a (uri, name, elapsed) bookmark from either a list index or
        an explicit --song/--name pair.

        --song/--name address a bookmark directly, which stays correct even
        if other bookmarks are added or removed in between calls -- unlike
        an index, which is only valid against the same `list` output it came
        from. Dies with a usage error if the argument combination is
        invalid, or if nothing matches.
        """
        if args.song is not None or args.name is not None:
            if args.song is None or args.name is None:
                die("--song and --name must be used together")
            if args.index is not None:
                die("Cannot combine an index with --song/--name")
            bookmarks = self.get_song_bookmarks(args.song)
            if args.name not in bookmarks:
                die(f"No bookmark named {args.name!r} on {args.song!r}")
            return args.song, args.name, float(bookmarks[args.name])

        entries = self.get_all_bookmarks()
        index = args.index if args.index is not None else 1
        if not (1 <= index <= len(entries)):
            die("Invalid bookmark index")
        return entries[index - 1]

    def delete_bookmark(self, args: argparse.Namespace) -> None:
        """Delete the resolved bookmark."""
        uri, name, _ = self.resolve_target(args)
        bookmarks = self.get_song_bookmarks(uri)
        bookmarks.pop(name, None)
        self.set_song_bookmarks(uri, bookmarks)
        print(f"Deleted bookmark {name!r} on {uri}")

    def save_bookmark(self, args: argparse.Namespace) -> None:
        """Save the current playback position under the given name for the current song."""
        current = self._client.currentsong()
        if not current:
            die("No song is currently playing.")
        status = self._client.status()
        elapsed = get_elapsed(status)

        bookmarks = self.get_song_bookmarks(current["file"])
        bookmarks[args.name] = elapsed
        self.set_song_bookmarks(current["file"], bookmarks)

    def rename_bookmark(self, args: argparse.Namespace) -> None:
        """Rename the resolved bookmark, keeping its saved position."""
        uri, name, elapsed = self.resolve_target(args)
        if args.to == name:
            return
        bookmarks = self.get_song_bookmarks(uri)
        if args.to in bookmarks:
            die(f"A bookmark named {args.to!r} already exists on {uri!r}")
        del bookmarks[name]
        bookmarks[args.to] = elapsed
        self.set_song_bookmarks(uri, bookmarks)
        print(f"Renamed bookmark {name!r} to {args.to!r} on {uri}")

    def load_bookmark(self, args: argparse.Namespace) -> None:
        """Queue (if needed) and seek to the resolved bookmark."""
        uri, _, elapsed = self.resolve_target(args)

        playlist = self._client.playlistid()
        songid = None
        for song in playlist:
            if song.get("file") == uri:
                songid = song["id"]
                break
        if songid is None:
            songid = self._client.addid(uri)
        self._client.seekid(songid, elapsed)
        self._client.playid(songid)

    def prune_bookmarks(self, args: argparse.Namespace) -> None:
        """Remove bookmarks for songs no longer in the library.

        MPD doesn't clean up stickers when a file disappears from the
        library, so bookmarks for deleted/moved files would otherwise
        accumulate silently.
        """
        library_uris = {obj["file"] for obj in self._client.listall() if "file" in obj}
        stale_uris = {uri for uri, _, _ in self.get_all_bookmarks()} - library_uris
        for uri in stale_uris:
            self.set_song_bookmarks(uri, {})
            print(f"Pruned bookmarks for missing song: {uri}")
        if not stale_uris:
            print("No stale bookmarks found.")

    def parse_args(self) -> argparse.Namespace:
        parser = argparse.ArgumentParser(description="Bookmark song positions in MPD")
        parser.add_argument("-H", "--host", help="Host address to connect to. Overrides mpdmark.conf.", default=None, type=str)
        parser.add_argument("-P", "--port", help="Port to connect to. Overrides mpdmark.conf.", default=None, type=int)
        parser.add_argument("-a", "--password", help="Password to authenticate with. Overrides mpdmark.conf.", default=None, type=str)
        sub_parser = parser.add_subparsers(dest="command", required=True)

        list_parser = sub_parser.add_parser("list", help="list all bookmarks")
        list_parser.set_defaults(func=self.list_bookmarks)

        del_parser = sub_parser.add_parser("del", help="delete a bookmark")
        del_parser.set_defaults(func=self.delete_bookmark)
        self._add_target_arguments(del_parser)

        save_parser = sub_parser.add_parser("save", help="save position of current song")
        save_parser.set_defaults(func=self.save_bookmark)
        save_parser.add_argument("-n", "--name", type=str, default=DEFAULT_BOOKMARK_NAME, help="Name for this bookmark")

        load_parser = sub_parser.add_parser("load", help="load a bookmark")
        load_parser.set_defaults(func=self.load_bookmark)
        self._add_target_arguments(load_parser)

        rename_parser = sub_parser.add_parser("rename", help="rename a bookmark")
        rename_parser.set_defaults(func=self.rename_bookmark)
        self._add_target_arguments(rename_parser)
        rename_parser.add_argument("-t", "--to", type=str, required=True, help="New name for the bookmark")

        prune_parser = sub_parser.add_parser("prune", help="remove bookmarks for songs no longer in the library")
        prune_parser.set_defaults(func=self.prune_bookmarks)

        return parser.parse_args()

    @staticmethod
    def _add_target_arguments(subparser: argparse.ArgumentParser) -> None:
        """Add the shared index / --song+--name addressing options used by
        del, load, and rename (see resolve_target)."""
        subparser.add_argument("index", type=int, nargs="?", default=None, help="Bookmark number from `list` (default: 1)")
        subparser.add_argument("-s", "--song", type=str, default=None, help="Song URI; use with --name instead of index")
        subparser.add_argument("-n", "--name", type=str, default=None, help="Bookmark name; use with --song instead of index")

    def __init__(self) -> None:
        args = self.parse_args()
        config = load_config()
        host = args.host or config.get("mpd_host", fallback="localhost")
        port = args.port or config.getint("mpd_port", fallback=6600)
        password = args.password or config.get("mpd_password", fallback="") or None

        self._client = MPDClient()
        try:
            self._client.connect(host, port)
        except SocketError as e:
            die(f"Failed to connect to MPD server: {e}")
        if password:
            try:
                self._client.password(password)
            except CommandError as e:
                die(f"Error authenticating with MPD: {e}")
        if "sticker" not in self._client.commands():
            die(
                "MPD does not support stickers, or they aren't enabled.\n"
                "This feature requires MPD 0.15 or later with sticker_file set.\n"
                f"Your version is {self._client.mpd_version}."
            )

        args.func(args)

        self._client.close()
        self._client.disconnect()


if __name__ == "__main__":
    App()
