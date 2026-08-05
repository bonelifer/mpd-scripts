#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vim: ai ts=4 sw=4 sts=4 expandtab

from mpd import CommandError
from collections import deque
from db import env, lastqueued, lastplayed, skipcount, keyof
from client import connect
from paths import load_config, CONFIG_DIR
import logging
import random
import re
import time
import datetime
from dateutil.easter import easter
import mutagen
import os
import argparse
from pathlib import Path

# Load configuration
config = load_config()

# Initialize logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
log = logging.getLogger(os.path.basename(__file__))

FEATURES = {
    name: config.getboolean('features', name, fallback=True)
    for name in (
        "weighted_selection",
        "skip_detection",
        "artist_diversity",
        "album_diversity",
        "seasonal_filters",
        "time_profiles",
        "exclude_list",
        "low_eligible_alert",
        "new_music_boost",
        "rating_weighting",
        "spread_insertion",
    )
}

DIVERSITY_WINDOW = config.getint('behavior', 'diversity_window', fallback=5)
NEW_MUSIC_DAYS = config.getint('behavior', 'new_music_days', fallback=30)
NEW_MUSIC_WEIGHT = config.getfloat('behavior', 'new_music_weight', fallback=3.0)
RATING_SCALE_MAX = config.getfloat('behavior', 'rating_scale_max', fallback=10.0)


def _diversity_deque():
    return deque(maxlen=DIVERSITY_WINDOW if DIVERSITY_WINDOW > 0 else 1)


def _resolve_path(value):
    """Exclude/notify list file paths resolve against CONFIG_DIR (where
    paths.load_config() seeds them), not this script's own directory."""
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = CONFIG_DIR / path
    return path


def load_word_list(kind, value, lower=False):
    """Load a '#'-comment, one-entry-per-line list file"""
    if not value:
        return set()
    path = _resolve_path(value)
    if not path.exists():
        log.warning("%s file not found: %s", kind, path)
        return set()
    entries = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            entries.add(line.lower() if lower else line)
    return entries


_WEEKDAYS = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}
_DAY_NAMES = {v: k for k, v in _WEEKDAYS.items()}
_MONTHS = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}

# "4th-thu-of-nov" (Thanksgiving), "last-mon-of-may" (Memorial Day), etc,
# with an optional trailing +/-N day offset, e.g. "4th-thu-of-nov+1" for
# Black Friday.
_NTH_WEEKDAY_RE = re.compile(
    r"^(1st|2nd|3rd|4th|last)-(mon|tue|wed|thu|fri|sat|sun)-of-"
    r"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)([+-]\d+)?$"
)
# "easter", "easter-2" (Good Friday), "easter+1" (Easter Monday), etc.
_EASTER_RE = re.compile(r"^easter([+-]\d+)?$")


def _is_leap_year(year):
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


def _nth_weekday_of_month(year, nth, weekday, month):
    """nth is 1-4, or the string 'last'."""
    if nth == "last":
        next_month_first = (
            datetime.date(year + 1, 1, 1) if month == 12
            else datetime.date(year, month + 1, 1)
        )
        d = next_month_first - datetime.timedelta(days=1)
        while d.weekday() != weekday:
            d -= datetime.timedelta(days=1)
        return d

    d = datetime.date(year, month, 1)
    while d.weekday() != weekday:
        d += datetime.timedelta(days=1)
    return d + datetime.timedelta(weeks=nth - 1)


def _parse_date_spec(year, spec):
    """Resolve a season start/end spec to a concrete date for the given year.

    Supported forms: "MM-DD", "<1st|2nd|3rd|4th|last>-<weekday>-of-<month>"
    (optionally with a trailing +/-N day offset), and "easter" (optionally
    with a trailing +/-N day offset).
    """
    spec = spec.strip().lower()

    m = _EASTER_RE.match(spec)
    if m:
        offset = int(m.group(1)) if m.group(1) else 0
        return easter(year) + datetime.timedelta(days=offset)

    m = _NTH_WEEKDAY_RE.match(spec)
    if m:
        nth_raw, weekday_abbr, month_abbr, offset_raw = m.groups()
        nth = "last" if nth_raw == "last" else int(nth_raw[0])
        d = _nth_weekday_of_month(year, nth, _WEEKDAYS[weekday_abbr], _MONTHS[month_abbr])
        if offset_raw:
            d += datetime.timedelta(days=int(offset_raw))
        return d

    month, day = (int(p) for p in spec.split("-"))
    if month == 2 and day == 29 and not _is_leap_year(year):
        # Feb 29 doesn't exist this year - fall back to Feb 28, the usual
        # convention for an annual date that lands on a leap day.
        day = 28
    return datetime.date(year, month, day)


def _season_start(year, spec):
    return _parse_date_spec(year, spec)


def _season_end(year, spec, start_date):
    end_date = _parse_date_spec(year, spec)
    if end_date < start_date:
        end_date = _parse_date_spec(year + 1, spec)
    return end_date


def load_seasons():
    """Parse [season:*] sections from config into a list of season rules"""
    seasons = []
    for section in config.sections():
        if not section.startswith("season:"):
            continue
        name = section.split(":", 1)[1]
        genres = {
            g.strip().lower()
            for g in config.get(section, "genres", fallback="").split(",")
            if g.strip()
        }
        start_spec = config.get(section, "start", fallback=None)
        end_spec = config.get(section, "end", fallback=None)
        if not genres or not start_spec or not end_spec:
            log.warning("Skipping malformed [%s] season config", section)
            continue
        seasons.append({"name": name, "genres": genres, "start": start_spec, "end": end_spec})
    return seasons


def is_in_season(season, today):
    """Check today against the season anchored to this year AND last year,
    so dates like early January still match a season that started the
    previous November/December."""
    for year in (today.year, today.year - 1):
        start_date = _season_start(year, season["start"])
        end_date = _season_end(year, season["end"], start_date)
        if start_date <= today <= end_date:
            return True
    return False


def should_skip_due_to_season(genres, today, seasons):
    """Check if a song should be skipped based on its seasonal genres"""
    file_genres = {g.lower() for g in genres}
    for season in seasons:
        if season["genres"] & file_genres and not is_in_season(season, today):
            return True
    return False


def load_time_profiles():
    """Parse [profile:*] sections from config into a list of time-of-day /
    day-of-week rules that restrict selection to specific genres."""
    profiles = []
    for section in config.sections():
        if not section.startswith("profile:"):
            continue
        name = section.split(":", 1)[1]
        genres = {
            g.strip().lower()
            for g in config.get(section, "genres", fallback="").split(",")
            if g.strip()
        }
        days = {
            d.strip().lower()
            for d in config.get(section, "days", fallback="").split(",")
            if d.strip()
        }
        start_raw = config.get(section, "start_time", fallback=None)
        end_raw = config.get(section, "end_time", fallback=None)
        if not genres or not days or not start_raw or not end_raw:
            log.warning("Skipping malformed [%s] profile config", section)
            continue
        if days - set(_WEEKDAYS):
            log.warning("Skipping [%s]: unknown day(s) %s", section, days - set(_WEEKDAYS))
            continue
        try:
            start_time = datetime.datetime.strptime(start_raw.strip(), "%H:%M").time()
            end_time = datetime.datetime.strptime(end_raw.strip(), "%H:%M").time()
        except ValueError:
            log.warning("Skipping [%s]: start_time/end_time must be HH:MM", section)
            continue
        profiles.append({
            "name": name, "genres": genres, "days": days,
            "start_time": start_time, "end_time": end_time,
        })
    return profiles


def active_time_profile(now, profiles):
    """Return the first profile whose day/time window covers `now`, or None."""
    day_name = _DAY_NAMES[now.weekday()]
    current_time = now.time()
    for profile in profiles:
        if day_name not in profile["days"]:
            continue
        start, end = profile["start_time"], profile["end_time"]
        in_window = start <= current_time <= end if start <= end else (current_time >= start or current_time <= end)
        if in_window:
            return profile
    return None


def should_skip_due_to_profile(genres, profile):
    """Active profiles restrict to their genre list; untagged tracks are
    always allowed through since there's nothing to match against."""
    if profile is None or not genres:
        return False
    file_genres = {g.lower() for g in genres}
    return not (profile["genres"] & file_genres)


def notify_low_eligible(playlistlen, target, attempts):
    if not config.getboolean('notify', 'enabled', fallback=False):
        return
    urls = load_word_list("notify urls", config.get('notify', 'urls', fallback=None))
    if not urls:
        log.warning("low_eligible_alert is on but [notify] has no urls configured")
        return
    try:
        import apprise
    except ImportError:
        log.warning("apprise is not installed - skipping low-eligible-tracks notification")
        return
    ap = apprise.Apprise()
    for url in urls:
        ap.add(url)
    ap.notify(
        title="mpd-smart-shuffle: running low on eligible tracks",
        body=(
            f"Only reached {playlistlen}/{target} tracks after {attempts} attempts. "
            "The library may need more tracks, or min_replay_days may be too strict."
        ),
    )


def main():
    ap = argparse.ArgumentParser(description='Add random tracks to MPD playlist')
    ap.add_argument(
        "count",
        type=int,
        default=config.getint('behavior', 'default_playlist_length'),
        nargs="?",
        help="Target playlist length (default: %(default)s)"
    )
    ap.add_argument(
        "-n", "--dry-run", action="store_true",
        help="Log what would be queued without touching MPD's queue or the tracking databases"
    )
    args = ap.parse_args()

    # Initialize MPD connection
    client = connect(
        host=config['mpd']['host'],
        port=config['mpd']['port'],
        password=config['mpd']['password'] or None
    )

    try:
        TODAY = datetime.date.today()
        NOW_DT = datetime.datetime.now()
        NOW = time.time()
        MIN_DURATION = config.getint('behavior', 'min_replay_days') * 86400
        MAX_LAST = NOW - MIN_DURATION

        status = client.status()
        playlistlen = int(status['playlistlength'])
        current_song_index = int(status['song']) if 'song' in status else None
        log.info("Playlist has %d tracks, target is %d", playlistlen, args.count)
        refresh_time = NOW

        files = client.list("file")
        if not files:
            log.error("No files found in MPD database!")
            return

        seasons = load_seasons() if FEATURES["seasonal_filters"] else []
        time_profiles = load_time_profiles() if FEATURES["time_profiles"] else []
        active_profile = active_time_profile(NOW_DT, time_profiles) if FEATURES["time_profiles"] else None

        excluded_files = set()
        excluded_artists = set()
        excluded_genres = set()
        if FEATURES["exclude_list"]:
            excluded_files = load_word_list("exclude files", config.get('exclude', 'files', fallback=None))
            excluded_artists = load_word_list(
                "exclude artists", config.get('exclude', 'artists', fallback=None), lower=True
            )
            excluded_genres = load_word_list(
                "exclude genres", config.get('exclude', 'genres', fallback=None), lower=True
            )

        recent_artists = _diversity_deque()
        recent_albums = _diversity_deque()

        # Bounds the search so a library with too few eligible tracks (small
        # library, high min_replay_days) can't spin forever without ever
        # reaching args.count.
        max_attempts = len(files) * 3
        attempts = 0

        while playlistlen < args.count:
            attempts += 1
            if attempts > max_attempts:
                log.warning(
                    "Giving up after %d attempts - not enough eligible tracks to reach target of %d",
                    attempts, args.count
                )
                if FEATURES["low_eligible_alert"] and not args.dry_run:
                    notify_low_eligible(playlistlen, args.count, attempts)
                break

            file = random.choice(files)
            filename = file["file"]

            if FEATURES["exclude_list"] and filename in excluded_files:
                log.debug("Skipped - excluded file: %s", filename)
                continue

            filepath = os.path.join(config['paths']['music_dir'], filename)
            log.debug("Considering: %s", filename)

            # Skip if file doesn't exist
            if not os.path.exists(filepath):
                log.debug("File not found: %s", filepath)
                continue

            # Check last played/queued time from MPD stickers
            last_played = 0.0
            for sticker_name in ["lastplayed_unixtime", "lastqueued_unixtime"]:
                try:
                    last_played = float(client.sticker_get("song", filename, sticker_name))
                    break
                except CommandError as e:
                    if not str(e).endswith("no such sticker"):
                        log.warning("Sticker error for %s: %s", filename, str(e))

            if last_played >= MAX_LAST:
                log.debug("Skipped - played recently: %s", filename)
                continue

            # Soft cutoff: the longer a track has sat past min_replay_days,
            # the more likely it is to be accepted, instead of every track
            # past the cutoff being equally eligible.
            if FEATURES["weighted_selection"] and last_played > 0 and MIN_DURATION > 0:
                overdue = (NOW - last_played) - MIN_DURATION
                accept_prob = min(1.0, overdue / MIN_DURATION)
                if random.random() > accept_prob:
                    log.debug("Skipped - not yet weighted-due: %s", filename)
                    continue

            # New-music boost: recently-added tracks (by file mtime) always
            # pass this gate; older tracks only pass with probability
            # 1/NEW_MUSIC_WEIGHT, so new additions surface more often instead
            # of being diluted into a huge library. Note: this keys off mtime,
            # so a bulk retag that touches every file's mtime would defeat it.
            if FEATURES["new_music_boost"] and NEW_MUSIC_WEIGHT > 0:
                try:
                    mtime = os.path.getmtime(filepath)
                except OSError:
                    mtime = 0
                is_new = mtime > 0 and (NOW - mtime) < NEW_MUSIC_DAYS * 86400
                if not is_new and random.random() > (1.0 / NEW_MUSIC_WEIGHT):
                    log.debug("Skipped - new_music_boost pass: %s", filename)
                    continue

            # Rating weighting: MPD "rating" stickers (set by clients like
            # ncmpcpp) bias acceptance odds. Unrated tracks are unaffected.
            if FEATURES["rating_weighting"] and RATING_SCALE_MAX > 0:
                rating = None
                try:
                    raw_rating = client.sticker_get("song", filename, "rating")
                    rating = max(0.0, min(1.0, float(raw_rating) / RATING_SCALE_MAX))
                except CommandError as e:
                    if not str(e).endswith("no such sticker"):
                        log.warning("Rating sticker error for %s: %s", filename, str(e))
                if rating is not None:
                    rating_accept_prob = 0.3 + 0.7 * rating
                    if random.random() > rating_accept_prob:
                        log.debug("Skipped - rating weighting (%.2f): %s", rating, filename)
                        continue

            # Load file metadata
            try:
                tags = mutagen.File(filepath)
                if not tags or not hasattr(tags, 'tags'):
                    log.debug("No tags found in %s", filename)
                    continue
            except Exception as e:
                log.warning("Failed to read tags from %s: %s", filepath, str(e))
                continue

            # Skip if missing required tags
            if not all(key in tags.tags for key in ["ARTIST", "TITLE"]):
                log.debug("Missing required tags in %s", filename)
                continue

            artist = tags.tags["ARTIST"][0]
            title = tags.tags["TITLE"][0]
            album = tags.tags.get("ALBUM", ["N/A"])[0]
            genres_tag = tags.tags.get("GENRE", [])

            if FEATURES["exclude_list"] and artist.lower() in excluded_artists:
                log.debug("Skipped - excluded artist: %s", artist)
                continue

            if FEATURES["exclude_list"] and excluded_genres:
                file_genres = {g.lower() for g in genres_tag}
                if file_genres & excluded_genres:
                    log.debug("Skipped - excluded genre: %s", file_genres & excluded_genres)
                    continue

            if FEATURES["artist_diversity"] and artist.lower() in recent_artists:
                log.debug("Skipped - artist diversity window: %s", artist)
                continue

            if FEATURES["album_diversity"] and album != "N/A" and album.lower() in recent_albums:
                log.debug("Skipped - album diversity window: %s", album)
                continue

            # Seasonal music check
            if FEATURES["seasonal_filters"] and genres_tag:
                if should_skip_due_to_season(genres_tag, TODAY, seasons):
                    log.debug("Skipped - seasonal music out of season")
                    continue

            # Time-of-day / day-of-week profile check
            if FEATURES["time_profiles"] and should_skip_due_to_profile(genres_tag, active_profile):
                log.debug("Skipped - doesn't match active time profile [%s]", active_profile["name"])
                continue

            # Check play history in LMDB
            key = keyof(artist, title)
            skip = False

            with env.begin(db=lastqueued) as txn:
                if (last_q := txn.get(key)) and float(last_q.decode()) >= MAX_LAST:
                    log.debug("%s - %s queued recently", artist, title)
                    skip = True

            if not skip:
                with env.begin(db=lastplayed) as txn:
                    if (last_p := txn.get(key)) and float(last_p.decode()) >= MAX_LAST:
                        log.debug("%s - %s played recently", artist, title)
                        skip = True

            if not skip and FEATURES["skip_detection"]:
                with env.begin(db=skipcount) as txn:
                    raw = txn.get(key)
                skip_count = int(raw.decode()) if raw else 0
                if skip_count > 0 and random.random() > (1.0 / (1 + skip_count)):
                    log.debug("%s - %s skipped often (%d) - giving it a pass", artist, title, skip_count)
                    skip = True

            if skip:
                continue

            # Add eligible track
            if args.dry_run:
                log.info("[dry-run] Would add: %s - %s [%s]", artist, title, album)
            else:
                log.info("Adding: %s - %s [%s]", artist, title, album)
                if FEATURES["spread_insertion"] and current_song_index is not None and playlistlen > current_song_index + 1:
                    insert_pos = random.randint(current_song_index + 1, playlistlen)
                    client.addid(filename, str(insert_pos))
                else:
                    client.add(filename)

            if FEATURES["artist_diversity"]:
                recent_artists.append(artist.lower())
            if FEATURES["album_diversity"] and album != "N/A":
                recent_albums.append(album.lower())

            if args.dry_run:
                playlistlen += 1
                continue

            # Update tracking databases
            client.sticker_set("song", filename, "lastqueued_unixtime", str(NOW))
            with env.begin(db=lastqueued, write=True) as txn:
                txn.put(key, str(NOW).encode("utf-8"))

            # Update playlist length periodically
            if time.time() > refresh_time + 5:
                refresh_time = time.time()
                playlistlen = int(client.status()['playlistlength'])
                log.info("Progress: %d/%d tracks", playlistlen, args.count)
            else:
                playlistlen += 1
    finally:
        client.disconnect()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log.info("Interrupted by user")
    except Exception as e:
        log.error("Fatal error: %s", str(e), exc_info=True)
