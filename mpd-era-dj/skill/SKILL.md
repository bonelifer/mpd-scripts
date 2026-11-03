---
name: mpd-era-dj
description: Build an MPD playlist the way a radio DJ of a chosen year would have, for a station format the user picks (Top 40, AOR, Country, College Rock, and so on). Use when the user asks for a playlist "a DJ would have made in <year>", an era or decade radio playlist, or "what a <format> station played in <year>", from their own MPD library.
---

# MPD era DJ playlist

Make a playlist that sounds like a radio station of a chosen year. You
supply the musical judgment (which formats existed that year and what they
played); `mpd-era-dj.py` from mpd-scripts matches your picks to the user's
MPD library, enforces the year cutoff, mixes the slots, spaces artists out
and saves the playlist.

## The year rule

The chosen year is a hard cutoff. Nothing released after it may be
suggested. Any earlier year is allowed as gold, and songs from the chosen
year come first. The script rejects anything past the cutoff too, but get
it right in the list: every song needs its **original release year** (the
first single or album release, whichever came first), not the date of a
reissue or compilation.

## Steps

1. **Year.** If the user didn't give one, ask. Any year from the 1950s on
   works.

2. **Formats.** List the station formats that existed in that year, as a
   numbered list in two groups, commercial and college, each with one line
   and three or four example artists from that year. Use the table below;
   leave out formats that didn't exist yet. Ask which one, and how long
   (songs or hours; default 40 songs if they don't say). Wait for the
   answer.

3. **Library.** Find the script with `command -v mpd-era-dj.py`; if it isn't
   on PATH, use `mpd-era-dj/mpd-era-dj.py` in the mpd-scripts checkout. Save
   the library's artists to a scratch file with
   `mpd-era-dj.py -l > artists.txt` and search it (grep, case-insensitive)
   for the artists that fit the format. Favour artists the user owns: the
   library may be small or being rebuilt, and a list of songs they don't
   have makes a short playlist.

4. **Song list.** Write a JSON file in the scratchpad with about three times
   as many candidates as the playlist needs (at least 60 for 40 songs):

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

   - `current` = songs from the chosen year, `recurrent` = the two years
     before, `gold` = older. The script sorts them by `year`; you only set
     the `mix`.
   - Pick what the format actually played: chart hits for commercial
     formats, album tracks and new releases for college and AOR.
   - Use the artist and title as the record credited them. Leave out
     version notes such as "(Remastered)"; the script ignores them anyway.
   - Make sure there are enough candidates in each slot for the mix, with
     extras: many won't be in the library.

5. **Run it.**

   ```bash
   mpd-era-dj.py -i songs.json -n 40 -j
   ```

   Use `-t <hours>` instead of `-n` for a length in hours. The playlist is
   saved under the name "<year> <format>" (`-o` sets another).
   - If the playlist name already exists, the script stops. Ask the user
     before rerunning with `-r` (it overwrites that playlist), or pick a
     new name with `-o`.
   - Only add `-p` if the user asked to start playing: it **replaces the
     current queue**.
   - Use `-d` to preview without saving.

6. **Short playlist.** If the result says `short` or `short_of_current`, add
   more candidates (especially from owned artists that fit and aren't in
   the playlist yet) to the same file and rerun once with `-r`, since the
   playlist being replaced is the one this run just made. The script caps
   each artist (`artist_cap` in the result) and ends the playlist rather
   than stacking one artist, so more songs by an artist already at the cap
   won't help; only more artists will. If the user wants it longer anyway,
   `-m` raises the cap (for example `-m 0.2`), at the cost of hearing that
   artist more often.

7. **Report.** Tell the user the playlist name, length and slot counts, say
   if older songs had to fill in for missing current ones, and list the
   most useful missing songs (the best-known ones they don't have), not the
   whole missing list.

## Formats by era

Years are approximate; trust your own knowledge where it is more precise.

### Commercial

| Format | Years | Mix (current / recurrent / gold) | Notes |
| --- | --- | --- | --- |
| Top 40 | 1955–1983 | 0.65 / 0.25 / 0.10 | Singles chart hits, all genres that charted |
| CHR (Top 40) | 1983 on | 0.65 / 0.25 / 0.10 | The same format under its new name |
| R&B / Soul | 1955–1981 | 0.6 / 0.25 / 0.15 | Black radio before "Urban" |
| Urban Contemporary | 1981 on | 0.6 / 0.25 / 0.15 | R&B, funk, dance, early hip hop |
| MOR / Middle of the Road | 1955–1980 | 0.35 / 0.3 / 0.35 | Pop standards and soft hits |
| Adult Contemporary | 1970s on | 0.35 / 0.3 / 0.35 | Soft rock and ballads |
| Country | all | 0.5 / 0.25 / 0.25 | Country & Western before about 1970 |
| Progressive / Underground FM | 1967–1975 | 0.5 / 0.2 / 0.3 | Freeform album rock |
| AOR (Album Oriented Rock) | 1972 on | 0.45 / 0.25 / 0.3 | Rock album tracks and singles |
| Disco | 1975–1980 | 0.7 / 0.2 / 0.1 | Mainly 1978–1979 |
| Modern Rock / New Wave | 1979 on | 0.55 / 0.3 / 0.15 | KROQ-style: new wave, post-punk, synth-pop |
| Classic Rock | 1985 on | 0 / 0.1 / 0.9 | Rock from the late '60s and '70s |
| Oldies | 1970s on | 0 / 0 / 1 | Hits from 15–30 years before the chosen year |
| Beautiful Music / Easy Listening | 1960s–1980s | 0.2 / 0.2 / 0.6 | Soft instrumentals and vocals; a library may match few |
| Alternative | 1990 on | 0.55 / 0.3 / 0.15 | The post-Nirvana format |

### College

| Format | Years | Mix (current / recurrent / gold) | Notes |
| --- | --- | --- | --- |
| Freeform | all | 0.4 / 0.2 / 0.4 | DJ's choice across genres; the norm before about 1980 |
| College Rock / Indie | 1978 on | 0.55 / 0.25 / 0.2 | CMJ-chart sound: new indie and import records, album tracks |
| Hardcore / Punk show | 1977 on | 0.55 / 0.25 / 0.2 | Hardcore from about 1980 |
| Jazz show | all | 0.3 / 0.2 / 0.5 | New releases plus the classics |
| Reggae / World show | 1970s on | 0.4 / 0.2 / 0.4 | |
| Electronic / Industrial show | 1983 on | 0.5 / 0.3 / 0.2 | |

College stations played deep cuts and B-sides, not just singles; there,
"current" means records released that year. Local and regional shows are
left out: what a single town's bands played is too uncertain to pick from.
