#!/usr/bin/env python3
"""
alarmpd

A playlist-based alarm clock daemon for MPD. Scheduling an alarm is done
entirely through your MPD client: create (or rename) a stored playlist
using one of these name grammars, and alarmpd plays it at the right time.

Recurring, one or more days:
    Monday 7:30
    Monday,Wednesday,Friday 7:30
    Weekdays 7:30          (Weekdays/Weekends/Daily are built-in groups)
    Monday 7:30 max=60      (fades to 60% instead of the configured default)

One-shot, a specific date (never recurs, and expires once past -- run
this script with --prune to delete expired ones, since they otherwise
just sit there unused):
    2026-08-12 7:30
    2026-08-12 7:30 max=60

Prefixes:
    !Monday 7:30    permanently disabled -- ignored entirely until renamed back
    ~Monday 7:30     skip just the next occurrence, then alarmpd renames it
                     back to "Monday 7:30" automatically

If two playlists resolve to the exact same next occurrence, alarmpd refuses
to schedule either and logs the collision until it's resolved (e.g. by
renaming one of them), rather than silently picking one.

Fading: set fade_duration in alarmpd.conf to the number of seconds it
should take to go from 0 to 100% volume (0 disables fading, jumping
straight to the target volume). An alarm's own "max=" suffix caps how far
it fades, at the same seconds-per-percent rate, so a lower cap finishes
faster. Turning the volume down manually while fading restarts the ramp,
which doubles as a snooze -- alarmpd only stops adjusting the volume once
it reaches the target.

Connection settings (host/port/password) come from
~/.config/mpd-scripts/alarmpd/alarmpd.conf, seeded from alarmpd.conf.example
on first run; -H/-P/-a on the command line override the config file for a
single invocation.
"""

import argparse
import configparser
import logging
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import date, datetime, time as dt_time, timedelta

from mpd import MPDClient, CommandError
from mpd import ConnectionError as MPDConnectionError

CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".config", "mpd-scripts", "alarmpd")
CONFIG_FILE = os.path.join(CONFIG_DIR, "alarmpd.conf")

STATE_DIR = os.path.join(os.path.expanduser("~"), ".local", "state", "alarmpd")
PID_FILE = os.path.join(STATE_DIR, "alarmpd.pid")
LOG_FILE = os.path.join(STATE_DIR, "alarmpd.log")

DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
DAY_INDEX = {name.lower(): i for i, name in enumerate(DAY_NAMES)}
NAMED_DAY_GROUPS = {
    "weekdays": frozenset(range(0, 5)),
    "weekends": frozenset(range(5, 7)),
    "daily": frozenset(range(0, 7)),
}

RECURRING_PATTERN = re.compile(
    r"^(?P<days>[A-Za-z]+(?:,[A-Za-z]+)*) (?P<hour>[01]?[0-9]|2[0-3]):(?P<minute>[0-5][0-9])(?: max=(?P<max>\d{1,3}))?$"
)
ONE_SHOT_PATTERN = re.compile(
    r"^(?P<year>\d{4})-(?P<month>\d{2})-(?P<day>\d{2}) (?P<hour>[01]?[0-9]|2[0-3]):(?P<minute>[0-5][0-9])(?: max=(?P<max>\d{1,3}))?$"
)


@dataclass
class Schedule:
    """A parsed alarm playlist name.

    `days` holds weekday indices (Monday=0) for a recurring alarm and is
    empty for a one-shot alarm, which uses `fire_date` instead.
    """

    playlist_name: str
    days: frozenset
    fire_date: "date | None"
    fire_time: dt_time
    max_volume: int
    skip_once: bool

    def next_occurrence(self, now: datetime) -> "datetime | None":
        """Return the next time this schedule fires at or after `now`.

        One-shot alarms never roll forward -- once their date has passed,
        this returns None rather than jumping a year ahead.
        """
        if self.fire_date is not None:
            candidate = datetime.combine(self.fire_date, self.fire_time, tzinfo=now.tzinfo)
            return candidate if candidate >= now else None

        best = None
        for weekday in self.days:
            days_ahead = (weekday - now.weekday()) % 7
            candidate = datetime.combine(now.date(), self.fire_time, tzinfo=now.tzinfo) + timedelta(days=days_ahead)
            if candidate < now:
                candidate += timedelta(days=7)
            if best is None or candidate < best:
                best = candidate
        return best


def parse_entry(playlist_name: str, default_max_volume: int) -> "Schedule | None":
    """Parse a stored playlist name into a Schedule, or None if it doesn't
    match either the recurring or one-shot grammar (including anything
    "!"-disabled, since that prefix never matches either pattern).
    """
    skip_once = playlist_name.startswith("~")
    remainder = playlist_name[1:] if skip_once else playlist_name

    match = RECURRING_PATTERN.match(remainder)
    if match:
        days = set()
        for token in match.group("days").split(","):
            key = token.strip().lower()
            if key in NAMED_DAY_GROUPS:
                days |= NAMED_DAY_GROUPS[key]
            elif key in DAY_INDEX:
                days.add(DAY_INDEX[key])
            else:
                return None  # Unrecognized day name/group -- don't silently ignore a typo.

        max_volume = int(match.group("max")) if match.group("max") else default_max_volume
        if not (0 <= max_volume <= 100):
            return None
        fire_time = dt_time(int(match.group("hour")), int(match.group("minute")))
        return Schedule(playlist_name, frozenset(days), None, fire_time, max_volume, skip_once)

    match = ONE_SHOT_PATTERN.match(remainder)
    if match:
        max_volume = int(match.group("max")) if match.group("max") else default_max_volume
        if not (0 <= max_volume <= 100):
            return None
        try:
            fire_date = date(int(match.group("year")), int(match.group("month")), int(match.group("day")))
        except ValueError:
            return None
        fire_time = dt_time(int(match.group("hour")), int(match.group("minute")))
        return Schedule(playlist_name, frozenset(), fire_date, fire_time, max_volume, skip_once)

    return None


def load_config() -> configparser.SectionProxy:
    """Load ~/.config/mpd-scripts/alarmpd/alarmpd.conf, seeding it from the
    alarmpd.conf.example template shipped alongside this script on first run.

    Returns:
        configparser.SectionProxy: the "alarmpd" section.
    """
    if not os.path.exists(CONFIG_FILE):
        os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
        template = os.path.join(os.path.dirname(os.path.abspath(__file__)), "alarmpd.conf.example")
        with open(template) as src, open(CONFIG_FILE, "w") as dst:
            dst.write(src.read())
        os.chmod(CONFIG_FILE, 0o600)  # May contain an MPD password

    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    return config["alarmpd"]


def check_permissions() -> None:
    """Ensure STATE_DIR (holding the PID and log files) exists and is
    writable, creating it if needed. Exits the process if it can't be."""
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
    except OSError as e:
        print(f"Permission denied: cannot create {STATE_DIR}: {e}")
        sys.exit(1)

    if not os.access(STATE_DIR, os.W_OK):
        print(f"Permission denied: cannot write to {STATE_DIR}.")
        sys.exit(1)


class AlarmDaemon:
    """Polls MPD's stored playlists for alarm schedules, fires the soonest
    one when its time comes, and (optionally) fades the volume in."""

    def __init__(self, host, port, password=None, interval=20, fade_duration=600,
                 default_max_volume=100, pre_hook="", post_hook="", verbose=False):
        self._host = host
        self._port = port
        self._password = password
        self._interval = interval
        # Seconds-per-percent, derived from a total 0->100 duration so a
        # lower per-alarm "max=" cap finishes proportionally faster instead
        # of needing its own separate duration setting.
        self._fade_tick_interval = fade_duration / 100.0 if fade_duration > 0 else 0
        self._default_max_volume = default_max_volume
        self._pre_hook = pre_hook
        self._post_hook = post_hook
        self._verbose = verbose

        self._client = MPDClient()
        self._running = False
        self._fading = False
        self._fade_target = 100
        self._fade_last_tick = 0.0
        self._scheduled_time = None
        self._scheduled_schedule = None

        log_level = logging.DEBUG if verbose else logging.INFO
        logging.basicConfig(
            filename=LOG_FILE if not verbose else None,
            level=log_level,
            format="%(asctime)s - %(levelname)s - %(message)s",
        )
        self._logger = logging.getLogger("alarmpd")

    def log(self, message: str, level: int = logging.INFO) -> None:
        if self._verbose:
            print(f"[alarmpd] {message}")
        self._logger.log(level, message)

    def connect(self) -> None:
        self._client = MPDClient()
        self._client.connect(self._host, self._port)
        if self._password:
            self._client.password(self._password)
        self.log(f"Connected to MPD at {self._host}:{self._port}.")

    def connect_with_retry(self) -> None:
        """Keeps attempting to connect until successful or told to stop,
        instead of giving up after one failed attempt (e.g. MPD not started
        yet, or restarting). Only used by run()'s daemon loop; fire_test()
        connects once and fails immediately instead."""
        while self._running:
            try:
                self.connect()
                return
            except (MPDConnectionError, OSError) as e:
                self.log(f"Failed to connect to MPD ({e}). Retrying in 5s...", logging.WARNING)
                time.sleep(5)

    def handle_signal(self, signum, frame) -> None:
        self.log("Stopping alarmpd...")
        self._running = False

    def _iter_schedules(self):
        for entry in self._client.listplaylists():
            schedule = parse_entry(entry["playlist"], self._default_max_volume)
            if schedule is not None:
                yield schedule

    def compute_next(self, now: datetime):
        """Return (time, schedule) for the soonest alarm, or (None, None)
        if there is none -- including when the soonest slot is a tie
        between two different playlists, which is refused rather than
        resolved silently."""
        candidates = []
        for schedule in self._iter_schedules():
            occurrence = schedule.next_occurrence(now)
            if occurrence is not None:
                candidates.append((occurrence, schedule))

        if not candidates:
            return None, None

        candidates.sort(key=lambda c: c[0])
        soonest_time = candidates[0][0]
        tied = [c for c in candidates if c[0] == soonest_time]
        if len(tied) > 1:
            names = ", ".join(repr(schedule.playlist_name) for _, schedule in tied)
            self.log(
                f"Multiple alarms scheduled for the same time ({soonest_time}): {names}. "
                "Refusing to schedule either until this is resolved.",
                logging.ERROR,
            )
            return None, None

        return tied[0]

    def maybe_reschedule(self, now: datetime) -> None:
        new_time, new_schedule = self.compute_next(now)
        if new_time != self._scheduled_time:
            self._scheduled_time = new_time
            self._scheduled_schedule = new_schedule
            if new_time is not None:
                self.log(f"Next alarm: {new_schedule.playlist_name!r} at {new_time}")

    def run_hook(self, command: str) -> None:
        if not command:
            return
        try:
            subprocess.Popen(command, shell=True)
        except OSError as e:
            self.log(f"Failed to run hook {command!r}: {e}", logging.WARNING)

    def fire_alarm(self, schedule: Schedule) -> None:
        if schedule.skip_once:
            self.log(f"Skipping alarm {schedule.playlist_name!r} (one-time skip).")
            restored_name = schedule.playlist_name[1:]
            try:
                self._client.rename(schedule.playlist_name, restored_name)
            except CommandError as e:
                self.log(f"Failed to restore playlist name after skip: {e}", logging.WARNING)
            return

        self.log(f"Firing alarm: {schedule.playlist_name!r}")
        self.run_hook(self._pre_hook)

        offset = len(self._client.playlistinfo())
        self._client.load(schedule.playlist_name)

        if self._fade_tick_interval > 0:
            self._client.setvol(0)
            self._fading = True
            self._fade_target = schedule.max_volume
            self._fade_last_tick = time.monotonic()
        else:
            self._client.setvol(schedule.max_volume)

        self._client.play(offset)

        if not self._fading:
            self.run_hook(self._post_hook)

    def fade_tick(self) -> None:
        """Advance the volume fade by one step, if enough time has passed
        since the last one. Stops (and fires the post-alarm hook) once the
        target volume is reached -- turning the volume down manually before
        then just makes this ramp again on the next tick, which is the
        snooze mechanism."""
        if time.monotonic() - self._fade_last_tick < self._fade_tick_interval:
            return
        self._fade_last_tick = time.monotonic()

        current_volume = int(self._client.status().get("volume", 0))
        if current_volume >= self._fade_target:
            self._fading = False
            self.run_hook(self._post_hook)
            return
        self._client.setvol(current_volume + 1)

    def run(self) -> None:
        self._running = True
        signal.signal(signal.SIGTERM, self.handle_signal)
        signal.signal(signal.SIGINT, self.handle_signal)

        self.connect_with_retry()
        self.log("alarmpd started.")

        while self._running:
            now = datetime.now().astimezone()
            try:
                self.maybe_reschedule(now)
                if self._scheduled_time is not None and now >= self._scheduled_time:
                    self.fire_alarm(self._scheduled_schedule)
                    self._scheduled_time = None
                    self._scheduled_schedule = None
                if self._fading:
                    self.fade_tick()
            except (MPDConnectionError, OSError):
                self.log("Lost connection to MPD, reconnecting...", logging.WARNING)
                self.connect_with_retry()

            time.sleep(1 if self._fading else self._interval)

    def fire_test(self, playlist_name: str) -> None:
        """Fire a named playlist immediately, for verifying fade/volume/hook
        behavior without waiting for a real scheduled time. Doesn't require
        the name to match the alarm grammar -- any existing playlist works,
        falling back to the configured default max volume and no fade-once
        parsing if the name isn't schedule-shaped."""
        self._running = True
        signal.signal(signal.SIGTERM, self.handle_signal)
        signal.signal(signal.SIGINT, self.handle_signal)

        try:
            self.connect()
        except (MPDConnectionError, OSError) as e:
            print(f"Failed to connect to MPD: {e}", file=sys.stderr)
            sys.exit(1)

        schedule = parse_entry(playlist_name, self._default_max_volume)
        if schedule is None:
            schedule = Schedule(playlist_name, frozenset(), None, dt_time(0, 0), self._default_max_volume, False)

        self.fire_alarm(schedule)
        while self._running and self._fading:
            time.sleep(1)
            self.fade_tick()
        self.log("Test alarm complete.")

    def prune_expired(self, now: datetime) -> list:
        """Delete stored playlists for one-shot alarms whose date has
        already passed. Recurring alarms never expire and are left alone;
        a schedule counts as expired the same way next_occurrence already
        treats it (past one-shot dates never roll forward)."""
        removed = []
        for entry in self._client.listplaylists():
            name = entry["playlist"]
            schedule = parse_entry(name, self._default_max_volume)
            if schedule is None or schedule.fire_date is None:
                continue  # Not a one-shot alarm.
            if schedule.next_occurrence(now) is None:
                self._client.rm(name)
                removed.append(name)
        return removed

    def run_prune(self) -> None:
        """Connect, delete expired one-shot alarm playlists, print what was
        removed, then return -- doesn't enter the daemon loop."""
        try:
            self.connect()
        except (MPDConnectionError, OSError) as e:
            print(f"Failed to connect to MPD: {e}", file=sys.stderr)
            sys.exit(1)

        removed = self.prune_expired(datetime.now().astimezone())
        if removed:
            for name in removed:
                print(f"Pruned expired one-shot alarm: {name}")
        else:
            print("No expired one-shot alarms found.")


def build_daemon(args: argparse.Namespace, config: configparser.SectionProxy) -> AlarmDaemon:
    return AlarmDaemon(
        host=args.host or config.get("mpd_host", fallback="localhost"),
        port=args.port or config.getint("mpd_port", fallback=6600),
        password=args.password or config.get("mpd_password", fallback="") or None,
        interval=config.getint("interval", fallback=20),
        fade_duration=config.getint("fade_duration", fallback=600),
        default_max_volume=config.getint("default_max_volume", fallback=100),
        pre_hook=config.get("pre_alarm_hook", fallback=""),
        post_hook=config.get("post_alarm_hook", fallback=""),
        verbose=args.verbose,
    )


def start_daemon(daemon: AlarmDaemon) -> None:
    """Forks the process, creates a new session, and runs the daemon in the
    background, tracking its PID for later --stop."""
    if os.path.exists(PID_FILE):
        print("Daemon is already running.")
        sys.exit(1)

    pid = os.fork()
    if pid > 0:
        sys.exit(0)

    os.setsid()
    check_permissions()

    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))

    daemon.run()


def stop_daemon() -> None:
    """Sends SIGTERM to the PID recorded in PID_FILE, if it's still running."""
    if not os.path.exists(PID_FILE):
        print("Daemon is not running.")
        sys.exit(1)

    with open(PID_FILE) as f:
        pid = int(f.read().strip())

    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        print(f"No process found with PID {pid}. The daemon may have already stopped.")
        os.remove(PID_FILE)
        sys.exit(0)
    except PermissionError:
        print(f"Permission error while checking process with PID {pid}.")
        sys.exit(1)

    os.kill(pid, signal.SIGTERM)
    print("Daemon stopped.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="alarmpd: a playlist-based alarm clock for MPD")
    parser.add_argument("-H", "--host", default=None, help="MPD host. Overrides alarmpd.conf.")
    parser.add_argument("-P", "--port", default=None, type=int, help="MPD port. Overrides alarmpd.conf.")
    parser.add_argument("-a", "--password", default=None, help="MPD password. Overrides alarmpd.conf.")
    parser.add_argument("-s", "--stop", action="store_true", help="Stop the daemon")
    parser.add_argument("-v", "--verbose", action="store_true", help="Run in the foreground with console logging")
    parser.add_argument("-t", "--test", metavar="PLAYLIST", default=None,
                         help="Immediately fire the named playlist as a test alarm, then exit")
    parser.add_argument("--prune", action="store_true",
                         help="Delete expired one-shot alarm playlists, then exit")
    cli_args = parser.parse_args()

    if cli_args.stop:
        stop_daemon()
    else:
        check_permissions()  # AlarmDaemon.__init__ opens LOG_FILE under STATE_DIR right away
        cli_config = load_config()
        alarm_daemon = build_daemon(cli_args, cli_config)
        if cli_args.prune:
            alarm_daemon.run_prune()
        elif cli_args.test:
            alarm_daemon.fire_test(cli_args.test)
        elif cli_args.verbose:
            alarm_daemon.run()
        else:
            start_daemon(alarm_daemon)
