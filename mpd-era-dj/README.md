# MPD Era DJ

Builds an MPD playlist the way a radio DJ of a chosen year would have: mostly songs from that year, recent hits from the years just before, and older "gold" to fill in, for a station format such as Top 40, AOR, Country or College Rock.

It comes in two parts:

- **[`skill/SKILL.md`](./skill/SKILL.md)**, a [Claude Code](https://www.anthropic.com/claude) skill. Ask Claude for "a playlist a DJ would have made in 1984" and it lists the commercial and college station formats that existed that year, asks which one you want, and writes a list of songs that format played.
- **`mpd-era-dj.py`**, which takes that song list, matches it to your MPD library, and saves the playlist. You can also give it a song list you wrote yourself.

## Features

- The chosen year is a hard cutoff: songs released after it, or with no year given, are rejected. Any earlier year is allowed.
- Songs are sorted by their original release year into **current** (the chosen year), **recurrent** (the few years before) and **gold** (older), and the playlist is filled to a mix of the three. When one runs out, the others fill the space.
- Matches by artist and title, so a hit on a later compilation still counts. Ignores case, accents, punctuation, `&`/`and`, a leading "The", `feat.` credits and notes like "(2011 Remaster)". Album date tags aren't used, since they hold the album's date, not the song's.
- Prefers the normal version of a song over live, demo, remix and similar versions, and the original album over a later compilation.
- Keeps the same artist a set number of songs apart.
- Length in songs (`-n`) or hours (`-t`).
- Saves a stored playlist and leaves the queue alone, unless `-p` is given. Won't overwrite an existing playlist without `-r`.
- Reports what was used, what is missing from your library, and what the cutoff rejected, as text or JSON (`-j`).

## Requirements

- Python 3.10 or newer
- [`python-mpd2`](https://pypi.org/project/python-mpd2/)
- Claude Code, for the skill

## Configuration

Settings live in `~/.config/mpd-scripts/mpd-era-dj/mpd-era-dj.conf`, seeded from [`mpd-era-dj.conf.example`](./mpd-era-dj.conf.example) on first run. Edit the copy there, not the template.

- `mpd_host`, `mpd_port`, `mpd_password`: MPD connection. Overridden by `-H`, `-P`, `-a`.
- `default_songs`: playlist length when neither `-n` nor `-t` is given. Default `40`.
- `artist_separation`: songs that must pass before the same artist plays again; `0` turns it off. Overridden by `-s`. Default `8`.
- `recurrent_years`: how many years before the chosen year count as recurrent. Default `2`.
- `mix_current`, `mix_recurrent`, `mix_gold`: the share of each slot, when the song list has no `mix` of its own. Only the proportions matter. Defaults `0.6`, `0.25`, `0.15`.

## Song list format

```json
{
  "year": 1984,
  "format": "AOR",
  "mix": {"current": 0.45, "recurrent": 0.25, "gold": 0.3},
  "songs": [
    {"artist": "Bruce Springsteen", "title": "Dancing in the Dark", "year": 1984},
    {"artist": "Led Zeppelin", "title": "Rock and Roll", "year": 1971}
  ]
}
```

`year` on each song is its original release year. `format` and `mix` are optional. List more songs than the playlist needs, since some won't be in your library.

## Usage

```bash
./mpd-era-dj.py -i FILE [OPTIONS]
./mpd-era-dj.py -l
```

- `-i`, `--input FILE`: the JSON song list (`-` reads stdin).
- `-l`, `--list-artists`: print every artist in the library, one per line, then exit.
- `-n`, `--songs N`: playlist length in songs.
- `-t`, `--hours H`: playlist length in hours of playing time, instead of songs.
- `-o`, `--name NAME`: playlist name. Default "<year> <format>", for example "1984 AOR".
- `-r`, `--replace`: overwrite a playlist that already has this name.
- `-p`, `--play`: replace the current queue with the new playlist and start playing it.
- `-d`, `--dry-run`: show the playlist and report without saving or playing anything.
- `-s`, `--separation N`: songs between repeats of the same artist.
- `-j`, `--json`: print the result as JSON.
- `--seed N`: random seed, so the same input gives the same playlist.
- `-H`, `--host`, `-P`, `--port`, `-a`, `--password`: MPD connection overrides.
- `-h`, `--help`: show usage and exit. Also shown when run with no options.

`-i` and `-l` are mutually exclusive, and so are `-n` and `-t`.

Example:

```bash
./mpd-era-dj.py -i 1984-aor.json -t 2 -d
./mpd-era-dj.py -i 1984-aor.json -t 2 -p
```

## Installing the skill

`install.sh` at the top of this repo offers to copy the skill to `~/.claude/skills/mpd-era-dj/` when Claude Code is set up. To do it yourself:

```bash
mkdir -p ~/.claude/skills/mpd-era-dj
cp skill/SKILL.md ~/.claude/skills/mpd-era-dj/
```

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
