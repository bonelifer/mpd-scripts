#!/usr/bin/env python3

"""
mpd-era-dj

Builds an MPD playlist the way a radio DJ of a chosen year would have, from
a list of candidate songs (normally written by the mpd-era-dj Claude Code
skill, which knows what each station format played that year).

The input is a JSON file:

    {
      "year": 1984,
      "format": "AOR",
      "mix": {"current": 0.6, "recurrent": 0.25, "gold": 0.15},
      "songs": [
        {"artist": "Bruce Springsteen", "title": "Dancing in the Dark", "year": 1984},
        {"artist": "Led Zeppelin", "title": "Rock and Roll", "year": 1971}
      ]
    }

Each song's "year" is its original release year. "mix" is optional and
falls back to the config file. Songs are sorted into three slots by year:

    current    released in the chosen year
    recurrent  released in the few years before it (recurrent_years)
    gold       anything older

The chosen year is a hard cutoff: a song with a later year, or no year at
all, is rejected before matching. The library's own date tags are not used
for the cutoff, because they hold the album's date, so a 1983 hit on a 1991
best-of would look too new.

Candidates are matched to the library by artist and title, ignoring case,
accents, punctuation, "&"/"and", a leading "The", "feat." credits and
trailing remaster/version notes. Live, demo, remix and similar versions are
used only when the song is in the library in no other form. The playlist is
then filled slot by slot to the mix, keeping the same artist at least
artist_separation songs apart. When a slot runs out, the others fill the
remaining space; nothing newer than the chosen year is ever added.

The playlist is saved as a stored MPD playlist (the queue is left alone
unless --play is given). A report lists what was used, what was missing
from the library and what the cutoff rejected.

Connection and default settings come from
~/.config/mpd-scripts/mpd-era-dj/mpd-era-dj.conf, seeded from
mpd-era-dj.conf.example on first run.
"""

import argparse
import configparser
import json
import os
import random
import re
import sys
import unicodedata
from datetime import date

from mpd import MPDClient, CommandError
from socket import error as SocketError

CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".config", "mpd-scripts", "mpd-era-dj")
CONFIG_FILE = os.path.join(CONFIG_DIR, "mpd-era-dj.conf")

SLOTS = ("current", "recurrent", "gold")

# Words marking a version a DJ would not normally play in place of the
# original (checked in the title's trailing notes and in the album name).
UNWANTED_VERSION_RE = re.compile(
    r"\b(live|demo|remix|remixed|karaoke|instrumental|acoustic|rehearsal|"
    r"outtake|alternate|take \d+|backing track|re-?recorded)\b"
)

# Words marking a trailing " - ..." part of a title as a version note
# rather than part of the song name.
VERSION_NOTE_RE = re.compile(
    r"\b(remaster(ed)?|version|edit|mix|mono|stereo|single|live|demo|"
    r"acoustic|bonus|recording|take|\d{4})\b"
)


def load_config() -> configparser.SectionProxy:
    """Load ~/.config/mpd-scripts/mpd-era-dj/mpd-era-dj.conf, seeding it from
    the mpd-era-dj.conf.example template shipped alongside this script on
    first run.

    Returns:
        configparser.SectionProxy: the "mpd-era-dj" section.
    """
    if not os.path.exists(CONFIG_FILE):
        os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
        template = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mpd-era-dj.conf.example")
        with open(template) as src, open(CONFIG_FILE, "w") as dst:
            dst.write(src.read())
        os.chmod(CONFIG_FILE, 0o600)  # May contain an MPD password

    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    return config["mpd-era-dj"]


def die(msg: str) -> None:
    """Print an error message to stderr and exit with status 1."""
    sys.stderr.write(msg)
    sys.stderr.write("\n")
    sys.exit(1)


def config_number(config: configparser.SectionProxy, key: str, kind: type, minimum: float):
    """Read a numeric setting, exiting with a clear error if it is invalid.

    Args:
        config: the loaded config section.
        key: setting name.
        kind: int or float.
        minimum: smallest allowed value.

    Returns:
        The value converted to kind.
    """
    raw = config.get(key, "")
    try:
        value = kind(raw)
    except ValueError:
        die(f"Error: {key} in {CONFIG_FILE} must be a number, got '{raw}'.")
    if value < minimum:
        die(f"Error: {key} in {CONFIG_FILE} must be at least {minimum}, got {value}.")
    return value


def strip_accents(text: str) -> str:
    """Return text with accents removed (e.g. "Hüsker Dü" -> "Husker Du")."""
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch))


def simplify(text: str) -> str:
    """Lowercase, drop accents and punctuation, and collapse whitespace."""
    text = strip_accents(text).lower().replace("&", " and ")
    text = re.sub(r"['’`]", "", text)  # "Don't" -> "dont", not "don t"
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def normalize_artist(artist: str) -> str:
    """Matching key for an artist name: no "feat." credit and no leading "The"."""
    artist = re.split(r"\s+(?:feat\.?|ft\.?|featuring)\s+", artist, maxsplit=1, flags=re.IGNORECASE)[0]
    key = simplify(artist)
    if key.startswith("the "):
        key = key[4:]
    return key


def split_title(title: str) -> tuple[str, str]:
    """Split a title into its matching key and its trailing version notes.

    Trailing bracketed parts ("(2011 Remaster)", "[Live]") and a trailing
    " - ..." part that reads like a version note ("- Single Version") are
    removed from the key and returned as notes. Leading brackets, as in
    "(Don't Fear) The Reaper", stay part of the key.

    Returns:
        (key, notes), both simplified.
    """
    notes = []
    stripped = title.strip()
    while True:
        match = re.search(r"\s*[\(\[]([^\)\]]*)[\)\]]\s*$", stripped)
        if not match or match.start() == 0:
            break
        notes.append(match.group(1))
        stripped = stripped[:match.start()]
    match = re.search(r"\s+-\s+(.+)$", stripped)
    if match and VERSION_NOTE_RE.search(match.group(1).lower()):
        notes.append(match.group(1))
        stripped = stripped[:match.start()]
    feat = re.split(r"\s+(?:feat\.?|ft\.?|featuring)\s+", stripped, maxsplit=1, flags=re.IGNORECASE)
    return simplify(feat[0]), simplify(" ".join(notes))


def first_tag(song: dict, key: str) -> str:
    """Return a song tag as one string (MPD returns a list for repeated tags)."""
    value = song.get(key, "")
    if isinstance(value, list):
        value = value[0] if value else ""
    return str(value)


def artists_match(wanted: str, have: str) -> bool:
    """True when two normalized artists are the same act.

    Also accepts one credit extending the other with a band, such as
    "prince and the revolution" for "prince", or "huey lewis" for "huey
    lewis and the news".
    """
    return have == wanted or have.startswith(wanted + " and ") or wanted.startswith(have + " and ")


class Library:
    """Index of the MPD library by normalized title, for artist/title lookups."""

    def __init__(self, songs: list[dict]):
        self.by_title: dict[str, list[dict]] = {}
        for song in songs:
            title = first_tag(song, "title")
            if not title:
                continue
            key, notes = split_title(title)
            album = simplify(first_tag(song, "album"))
            artists = {normalize_artist(first_tag(song, "artist")), normalize_artist(first_tag(song, "albumartist"))}
            artists.discard("")
            entry = {
                "file": song["file"],
                "artists": artists,
                "seconds": float(song.get("duration", song.get("time", 0)) or 0),
                "unwanted": bool(UNWANTED_VERSION_RE.search(notes) or UNWANTED_VERSION_RE.search(album)),
                "album_year": album_year(first_tag(song, "date")),
            }
            self.by_title.setdefault(key, []).append(entry)

    def find(self, artist: str, title: str, year: int) -> dict | None:
        """Return the best library copy of a song, or None if it isn't there.

        Prefers a normal version over live/demo/remix ones, then a copy whose
        album date is no later than the song's year (the original album over
        a later compilation), then picks at random among equals.
        """
        wanted_artist = normalize_artist(artist)
        key, _ = split_title(title)
        found = [entry for entry in self.by_title.get(key, [])
                 if any(artists_match(wanted_artist, have) for have in entry["artists"])]
        if not found:
            return None
        best = min((entry["unwanted"], not (entry["album_year"] and entry["album_year"] <= year)) for entry in found)
        best_entries = [entry for entry in found
                        if (entry["unwanted"], not (entry["album_year"] and entry["album_year"] <= year)) == best]
        return random.choice(best_entries)


def album_year(date_tag: str) -> int | None:
    """Return the 4-digit year at the start of an MPD date tag, if any."""
    match = re.match(r"(\d{4})", date_tag)
    return int(match.group(1)) if match else None


def read_request(path: str) -> dict:
    """Load and validate the JSON song list.

    Args:
        path: file path, or "-" for stdin.

    Returns:
        The parsed request dict.
    """
    try:
        if path == "-":
            request = json.load(sys.stdin)
        else:
            with open(path, encoding="utf-8") as handle:
                request = json.load(handle)
    except OSError as e:
        die(f"Error: cannot read {path}: {e.strerror}.")
    except json.JSONDecodeError as e:
        die(f"Error: {path} is not valid JSON: {e}.")

    if not isinstance(request, dict):
        die("Error: the input must be a JSON object with \"year\" and \"songs\".")
    year = request.get("year")
    if not isinstance(year, int) or isinstance(year, bool) or not 1900 <= year <= date.today().year:
        die(f"Error: \"year\" must be a whole year between 1900 and {date.today().year}, got {year!r}.")
    songs = request.get("songs")
    if not isinstance(songs, list) or not songs:
        die("Error: \"songs\" must be a non-empty list.")
    for index, song in enumerate(songs, start=1):
        if not isinstance(song, dict):
            die(f"Error: song {index} must be an object with \"artist\", \"title\" and \"year\".")
        for field in ("artist", "title"):
            if not isinstance(song.get(field), str) or not song[field].strip():
                die(f"Error: song {index} needs a non-empty \"{field}\".")
    mix = request.get("mix")
    if mix is not None:
        if not isinstance(mix, dict) or set(mix) - set(SLOTS):
            die(f"Error: \"mix\" must be an object with only {', '.join(SLOTS)}.")
        for slot, share in mix.items():
            if not isinstance(share, (int, float)) or isinstance(share, bool) or share < 0:
                die(f"Error: mix \"{slot}\" must be a number of 0 or more.")
        if sum(mix.values()) <= 0:
            die("Error: the \"mix\" shares must not all be 0.")
    fmt = request.get("format", "")
    if not isinstance(fmt, str):
        die("Error: \"format\" must be a string.")
    return request


def slot_for(song_year: int, year: int, recurrent_years: int) -> str:
    """Return which rotation slot a song from song_year falls in."""
    if song_year == year:
        return "current"
    if song_year >= year - recurrent_years:
        return "recurrent"
    return "gold"


def build_pools(request: dict, library: Library, recurrent_years: int) -> tuple[dict, dict]:
    """Match the request's songs to the library and sort them into slots.

    Returns:
        (pools, report): pools maps each slot to its matched songs; report
        holds the "missing", "after_cutoff", "no_year" and "duplicates" lists.
    """
    year = request["year"]
    pools = {slot: [] for slot in SLOTS}
    report = {"missing": [], "after_cutoff": [], "no_year": [], "duplicates": 0}
    seen = set()
    for song in request["songs"]:
        artist, title = song["artist"].strip(), song["title"].strip()
        label = {"artist": artist, "title": title, "year": song.get("year")}
        song_year = song.get("year")
        if not isinstance(song_year, int) or isinstance(song_year, bool):
            report["no_year"].append(label)
            continue
        if song_year > year:
            report["after_cutoff"].append(label)
            continue
        key = (normalize_artist(artist), split_title(title)[0])
        if key in seen:
            report["duplicates"] += 1
            continue
        seen.add(key)
        match = library.find(artist, title, song_year)
        if match is None:
            report["missing"].append(label)
            continue
        slot = slot_for(song_year, year, recurrent_years)
        pools[slot].append({**label, "slot": slot, "file": match["file"],
                            "seconds": match["seconds"], "artist_key": key[0]})
    for pool in pools.values():
        random.shuffle(pool)
    return pools, report


def pick_song(pool: list[dict], recent: list[str], placed_files: set) -> dict | None:
    """Take a song from pool whose artist isn't among the recent ones.

    Returns None when every song left in the pool breaks the spacing rule.
    """
    for index, song in enumerate(pool):
        if song["artist_key"] not in recent and song["file"] not in placed_files:
            return pool.pop(index)
    return None


def build_playlist(pools: dict, mix: dict, max_songs: int | None, max_seconds: float | None,
                   separation: int) -> tuple[list[dict], int]:
    """Fill the playlist slot by slot, following the mix and artist spacing.

    At each step the slot furthest behind its share of the playlist so far
    (by song count, or by playing time when max_seconds is set) supplies the
    next song. A slot that is empty, or has only artists played too
    recently, is passed over for the next one; if every slot is blocked
    only by spacing, the rule is relaxed for that one song.

    Returns:
        (playlist, relaxed): the ordered songs and how many times the
        spacing rule had to be relaxed.
    """
    total_share = sum(mix.values())
    shares = {slot: mix.get(slot, 0) / total_share for slot in SLOTS}
    used = {slot: 0.0 for slot in SLOTS}
    playlist, recent, placed_files = [], [], set()
    relaxed = 0

    def amount(song: dict) -> float:
        return song["seconds"] if max_seconds is not None else 1.0

    while True:
        done = sum(used.values())
        if max_seconds is not None and done >= max_seconds:
            break
        if max_songs is not None and len(playlist) >= max_songs:
            break
        live = [slot for slot in SLOTS if pools[slot]]
        if not live:
            break
        # Slots with a share come first, furthest behind first; a slot with a
        # 0 share is used only once the others are exhausted.
        order = sorted(live, key=lambda slot: (shares[slot] == 0, used[slot] - shares[slot] * (done + 1)))
        song = None
        for slot in order:
            song = pick_song(pools[slot], recent, placed_files)
            if song:
                break
        if song is None:
            relaxed += 1
            song = pools[order[0]].pop(0)
        used[song["slot"]] += amount(song)
        playlist.append(song)
        placed_files.add(song["file"])
        if separation > 0:
            recent.append(song["artist_key"])
            del recent[:-separation]
    return playlist, relaxed


def save_playlist(client: MPDClient, name: str, files: list[str], replace: bool) -> None:
    """Write files to the stored playlist name, refusing to overwrite unless replace."""
    existing = {entry["playlist"] for entry in client.listplaylists()}
    if name in existing:
        if not replace:
            die(f"Error: a playlist named '{name}' already exists. Use -r/--replace to overwrite it, or -o/--name to pick another name.")
        client.playlistclear(name)
    client.command_list_ok_begin()
    for path in files:
        client.playlistadd(name, path)
    client.command_list_end()


def play_playlist(client: MPDClient, name: str) -> None:
    """Replace the queue with the stored playlist and start playing it."""
    client.clear()
    client.load(name)
    client.play(0)


def format_duration(seconds: float) -> str:
    """Format seconds as H:MM:SS."""
    seconds = int(seconds)
    return f"{seconds // 3600}:{seconds % 3600 // 60:02d}:{seconds % 60:02d}"


def print_report(result: dict) -> None:
    """Print the human-readable summary of a run."""
    year = result["year"]
    action = "Would save" if result["dry_run"] else "Saved"
    print(f"{action} playlist '{result['name']}': {len(result['playlist'])} songs, "
          f"{format_duration(result['seconds'])}.")
    counts = result["slot_counts"]
    print(f"  current ({year}): {counts['current']}, recurrent: {counts['recurrent']}, gold: {counts['gold']}")
    if result["short_of_current"]:
        print(f"  Only {result['matched']['current']} songs from {year} were found, so older songs filled the rest.")
    if result["short"]:
        print("  The playlist is shorter than asked: the library had no more matching songs.")
    if result["relaxed"]:
        print(f"  Artist spacing was relaxed {result['relaxed']} time(s) for lack of other artists.")
    if result["played"]:
        print("  Now playing (the queue was replaced).")
    print()
    for number, song in enumerate(result["playlist"], start=1):
        print(f"  {number:3d}. {song['artist']} - {song['title']} ({song['year']}, {song['slot']})")
    for key, heading in (("after_cutoff", f"Rejected, released after {year}"),
                         ("no_year", "Rejected, no release year given"),
                         ("missing", "Not in your library")):
        if result[key]:
            print(f"\n{heading} ({len(result[key])}):")
            for song in result[key]:
                print(f"  - {song['artist']} - {song['title']} ({song['year']})")


def connect(config: configparser.SectionProxy, args: argparse.Namespace) -> MPDClient:
    """Connect to MPD using command-line overrides, then the config file."""
    host = args.host or config.get("mpd_host", "localhost")
    port = args.port or config.get("mpd_port", "6600")
    password = args.password or config.get("mpd_password", "")
    client = MPDClient()
    client.timeout = 30
    try:
        client.connect(host, int(port))
        if password:
            client.password(password)
    except (SocketError, ConnectionError) as e:
        die(f"Error: cannot connect to MPD at {host}:{port}: {e}.")
    except ValueError:
        die(f"Error: MPD port must be a number, got '{port}'.")
    except CommandError as e:
        die(f"Error: MPD refused the password: {e}.")
    return client


def list_artists(client: MPDClient) -> None:
    """Print every artist and album artist in the library, one per line."""
    names = set()
    for tag in ("artist", "albumartist"):
        for row in client.list(tag):
            name = row.get(tag, "") if isinstance(row, dict) else row
            if name:
                names.add(name)
    for name in sorted(names, key=str.casefold):
        print(name)


def parse_args() -> argparse.Namespace:
    """Parse the command line, showing help when run with no arguments."""
    parser = argparse.ArgumentParser(
        description="Build an MPD playlist like a radio DJ of a chosen year, from a JSON list of candidate songs.",
        epilog="Songs released after the input's \"year\" are always rejected. Run with no arguments for this help.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("-i", "--input", metavar="FILE",
                      help="JSON song list to build the playlist from (\"-\" reads stdin).")
    mode.add_argument("-l", "--list-artists", action="store_true",
                      help="Print every artist in the library, one per line, then exit.")
    length = parser.add_mutually_exclusive_group()
    length.add_argument("-n", "--songs", type=int, metavar="N",
                        help="Playlist length in songs (default: default_songs in the config).")
    length.add_argument("-t", "--hours", type=float, metavar="H",
                        help="Playlist length in hours of playing time, instead of a song count.")
    parser.add_argument("-o", "--name", metavar="NAME",
                        help="Stored playlist name (default: \"<year> <format>\", e.g. \"1984 AOR\").")
    parser.add_argument("-r", "--replace", action="store_true",
                        help="Overwrite a stored playlist that already has this name.")
    parser.add_argument("-p", "--play", action="store_true",
                        help="Replace the current queue with the new playlist and start playing it.")
    parser.add_argument("-d", "--dry-run", action="store_true",
                        help="Show the playlist and report without saving or playing anything.")
    parser.add_argument("-s", "--separation", type=int, metavar="N",
                        help="Songs that must pass before the same artist plays again (default: artist_separation in the config).")
    parser.add_argument("-j", "--json", action="store_true",
                        help="Print the result as JSON instead of the readable report.")
    parser.add_argument("--seed", type=int, metavar="N",
                        help="Random seed, to make the same input give the same playlist.")
    parser.add_argument("-H", "--host", help="MPD host (overrides mpd_host in the config).")
    parser.add_argument("-P", "--port", help="MPD port (overrides mpd_port in the config).")
    parser.add_argument("-a", "--password", help="MPD password (overrides mpd_password in the config).")
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(0)
    args = parser.parse_args()
    if args.songs is not None and args.songs < 1:
        parser.error("-n/--songs must be at least 1.")
    if args.hours is not None and args.hours <= 0:
        parser.error("-t/--hours must be more than 0.")
    if args.separation is not None and args.separation < 0:
        parser.error("-s/--separation must be 0 or more.")
    if args.dry_run and (args.play or args.replace):
        parser.error("-d/--dry-run cannot be combined with -p/--play or -r/--replace.")
    return args


def main() -> None:
    """Run the requested mode."""
    args = parse_args()
    config = load_config()

    if args.list_artists:
        client = connect(config, args)
        list_artists(client)
        client.disconnect()
        return

    request = read_request(args.input)
    if args.seed is not None:
        random.seed(args.seed)

    recurrent_years = config_number(config, "recurrent_years", int, 0)
    separation = args.separation if args.separation is not None else config_number(config, "artist_separation", int, 0)
    mix = request.get("mix") or {slot: config_number(config, f"mix_{slot}", float, 0) for slot in SLOTS}
    if sum(mix.values()) <= 0:
        die(f"Error: mix_current, mix_recurrent and mix_gold in {CONFIG_FILE} must not all be 0.")
    max_seconds = args.hours * 3600 if args.hours is not None else None
    max_songs = None if max_seconds is not None else (args.songs or config_number(config, "default_songs", int, 1))
    name = args.name or " ".join(part for part in (str(request["year"]), request.get("format", "").strip()) if part)

    client = connect(config, args)
    library = Library([song for song in client.listallinfo() if "file" in song])
    pools, report = build_pools(request, library, recurrent_years)
    matched = {slot: len(pools[slot]) for slot in SLOTS}
    playlist, relaxed = build_playlist(pools, mix, max_songs, max_seconds, separation)
    seconds = sum(song["seconds"] for song in playlist)

    if not playlist:
        client.disconnect()
        die("Error: none of the songs were found in the library, so no playlist was made.")

    played = False
    if not args.dry_run:
        save_playlist(client, name, [song["file"] for song in playlist], args.replace)
        if args.play:
            play_playlist(client, name)
            played = True
    client.disconnect()

    slot_counts = {slot: sum(1 for song in playlist if song["slot"] == slot) for slot in SLOTS}
    wanted_current = mix.get("current", 0) / sum(mix.values()) * len(playlist)
    result = {
        "name": name,
        "year": request["year"],
        "format": request.get("format", ""),
        "dry_run": args.dry_run,
        "played": played,
        "seconds": seconds,
        "slot_counts": slot_counts,
        "matched": matched,
        "short_of_current": slot_counts["current"] < int(wanted_current),
        "short": (len(playlist) < max_songs) if max_songs is not None else (seconds < max_seconds),
        "relaxed": relaxed,
        "playlist": [{key: song[key] for key in ("artist", "title", "year", "slot", "file")} for song in playlist],
        **{key: report[key] for key in ("missing", "after_cutoff", "no_year")},
        "duplicates": report["duplicates"],
    }
    if args.json:
        json.dump(result, sys.stdout, indent=2, ensure_ascii=False)
        print()
    else:
        print_report(result)


if __name__ == "__main__":
    main()
