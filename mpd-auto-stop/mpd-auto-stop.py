#!/usr/bin/env python3
"""
mpd-auto-stop

A sleep-timer daemon for MPD: start a countdown (via a small HTTP API and
web UI), and when it expires, fade the volume out and pause playback.
Restart/extend an active timer, or cancel it outright.

Endpoints:
    GET /                          Web UI
    GET /timer                     Status: {"status": "stopped"} or
                                    {"status": "started", "remaining_seconds": N, "fading": bool}
    GET /timer/<duration>/start    Start a timer. Duration like "45m", "1h", "1.5h", "3600s".
    GET /timer/stop                Cancel the running timer (does not pause playback itself).
    GET /timer/restart             Re-arm the running timer with its original duration.
    GET /timer/<duration>/extend   Add more time to the running timer.

Connection settings and behavior come from
~/.config/mpd-scripts/mpd-auto-stop/mpd-auto-stop.conf, seeded from
mpd-auto-stop.conf.example on first run.
"""

import argparse
import base64
import configparser
import hmac
import json
import logging
import os
import re
import signal
import subprocess
import sys
import threading
import urllib.parse as urlparse
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from mpd import MPDClient
from mpd import ConnectionError as MPDConnectionError

VERSION = (2, 0, 0)

CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".config", "mpd-scripts", "mpd-auto-stop")
CONFIG_FILE = os.path.join(CONFIG_DIR, "mpd-auto-stop.conf")

STATE_DIR = os.path.join(os.path.expanduser("~"), ".local", "state", "mpd-auto-stop")
PID_FILE = os.path.join(STATE_DIR, "mpd-auto-stop.pid")
LOG_FILE = os.path.join(STATE_DIR, "mpd-auto-stop.log")

DURATION_PATTERN = re.compile(r"^([0-9]*\.?[0-9]+)([smh])$")


def parse_duration(duration: str) -> float:
    """Parse a "45m"/"1h"/"1.5h"/"3600s"-style duration into seconds."""
    duration = (duration or "").strip().lower()
    match = DURATION_PATTERN.match(duration)
    if not match:
        raise ValueError(f"Invalid duration: {duration!r}")
    value = float(match.group(1))
    unit = match.group(2)
    if unit == "m":
        value *= 60
    elif unit == "h":
        value *= 3600
    return value


def load_config() -> configparser.SectionProxy:
    """Load ~/.config/mpd-scripts/mpd-auto-stop/mpd-auto-stop.conf, seeding
    it from the mpd-auto-stop.conf.example template shipped alongside this
    script on first run.

    Returns:
        configparser.SectionProxy: the "mpd-auto-stop" section.
    """
    if not os.path.exists(CONFIG_FILE):
        os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
        template = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mpd-auto-stop.conf.example")
        with open(template) as src, open(CONFIG_FILE, "w") as dst:
            dst.write(src.read())
        os.chmod(CONFIG_FILE, 0o600)  # May contain an MPD password

    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    return config["mpd-auto-stop"]


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


class InvalidTimerStateError(Exception):
    pass


class MPDConnection:
    """Thread-safe wrapper around a single reused MPDClient connection.
    Reconnects (once) on a dropped connection before giving up, since this
    is a long-running daemon rather than a one-shot CLI call."""

    def __init__(self, host: str, port: int, password: str = None):
        self._host = host
        self._port = port
        self._password = password
        self._client = MPDClient()
        self._lock = threading.Lock()
        self._connected = False

    def _connect(self) -> None:
        self._client = MPDClient()
        self._client.connect(self._host, self._port)
        if self._password:
            self._client.password(self._password)
        self._connected = True

    def call(self, method_name: str, *args):
        """Thread-safely invoke an MPDClient method by name, reconnecting
        once on a dropped connection before letting the error propagate."""
        with self._lock:
            for attempt in (1, 2):
                try:
                    if not self._connected:
                        self._connect()
                    return getattr(self._client, method_name)(*args)
                except (MPDConnectionError, OSError):
                    self._connected = False
                    if attempt == 2:
                        raise


class Hooks:
    """Runs optional shell commands (warning_hook/stop_hook) from the
    config, fire-and-forget. Never fatal -- a missing/broken hook shouldn't
    affect the timer itself."""

    def __init__(self, config: configparser.SectionProxy):
        self._config = config

    def run(self, name: str) -> None:
        command = self._config.get(name, fallback="")
        if not command:
            return
        try:
            subprocess.Popen(command, shell=True)
        except OSError:
            pass


class Timer:
    """Sleep-timer state machine: start/stop/restart/extend a countdown
    that fades the volume out and pauses playback when it reaches zero.

    All public methods are safe to call concurrently from multiple HTTP
    handler threads; the countdown/fade itself runs in its own background
    thread so it never blocks request handling.
    """

    STOPPED = "stopped"
    STARTED = "started"

    def __init__(self, mpd: MPDConnection, config: configparser.SectionProxy, hooks: Hooks, logger: logging.Logger):
        self._mpd = mpd
        self._config = config
        self._hooks = hooks
        self._logger = logger
        self._lock = threading.Lock()

        self._status = Timer.STOPPED
        self._started_at = None
        self._duration = 0.0
        self._fading = False
        self._original_volume = None
        self._cancel_event = None
        self._thread = None

    @property
    def status(self) -> str:
        return self._status

    def _remaining_seconds(self) -> float:
        elapsed = (datetime.now() - self._started_at).total_seconds()
        return max(0.0, self._duration - elapsed)

    def get_status(self) -> dict:
        with self._lock:
            result = {"status": self._status}
            if self._status == Timer.STARTED:
                result["remaining_seconds"] = round(self._remaining_seconds(), 1)
                result["fading"] = self._fading
            return result

    def start(self, duration_str: str) -> dict:
        duration = parse_duration(duration_str)
        with self._lock:
            if self._status == Timer.STARTED:
                return {"remaining_seconds": round(self._remaining_seconds(), 1)}
            self._begin(duration)
            return {"remaining_seconds": round(self._remaining_seconds(), 1)}

    def stop(self) -> dict:
        with self._lock:
            if self._status == Timer.STARTED:
                self._cancel_run(restore_volume=True)
                self._status = Timer.STOPPED
                self._started_at = None
                self._duration = 0.0
                self._logger.info("Timer stopped")
            return {}

    def restart(self) -> dict:
        with self._lock:
            if self._status != Timer.STARTED:
                raise InvalidTimerStateError("Can't restart a stopped timer")
            duration = self._duration
            self._cancel_run(restore_volume=True)
            self._begin(duration)
            self._logger.info("Timer restarted with duration %s seconds", duration)
            return {"remaining_seconds": round(self._remaining_seconds(), 1)}

    def extend(self, duration_str: str) -> dict:
        with self._lock:
            if self._status != Timer.STARTED:
                raise InvalidTimerStateError("Can't extend a stopped timer")
            new_duration = self._remaining_seconds() + parse_duration(duration_str)
            self._cancel_run(restore_volume=True)
            self._begin(new_duration)
            self._logger.info("Timer extended with duration %s seconds", new_duration)
            return {"remaining_seconds": round(self._remaining_seconds(), 1)}

    # --- internal; callers must hold self._lock ---

    def _begin(self, duration: float) -> None:
        self._status = Timer.STARTED
        self._started_at = datetime.now()
        self._duration = duration
        self._fading = False
        self._original_volume = None
        self._cancel_event = threading.Event()
        self._thread = threading.Thread(target=self._run, args=(self._cancel_event, duration), daemon=True)
        self._thread.start()
        self._logger.info("Timer started with duration %s seconds", duration)

    def _cancel_run(self, restore_volume: bool) -> None:
        if self._cancel_event:
            self._cancel_event.set()
        if self._thread:
            self._thread.join(timeout=5)
        if restore_volume and self._fading and self._original_volume is not None:
            try:
                self._mpd.call("setvol", self._original_volume)
            except Exception:
                pass
        self._fading = False
        self._thread = None
        self._cancel_event = None

    def _run(self, cancel_event: threading.Event, duration: float) -> None:
        """Wait out `duration`, running the warning hook and the fade at
        their own independent offsets (whichever comes first), then pause.

        The two are scheduled as absolute checkpoints and processed in
        chronological order rather than chained sequentially, so this
        stays correct regardless of which one is configured to happen
        first -- with fade_duration > warning_lead_time (the shipped
        default: fade starts before the warning fires), the fade's
        remaining duration is clamped to whatever time is actually left,
        so it always finishes exactly at `duration` instead of overrunning
        it. Chaining these as "wait for warning, then wait for the rest of
        fade_duration" only produced fade_duration itself -- not the
        actual desired end time -- once the warning fired later than fade
        should have already started.
        """
        fade_duration = max(0.0, self._config.getfloat("fade_duration", fallback=0.0))
        warning_lead = max(0.0, self._config.getfloat("warning_lead_time", fallback=0.0))

        checkpoints = []
        if warning_lead > 0:
            checkpoints.append((max(0.0, duration - warning_lead), "warning"))
        if fade_duration > 0:
            checkpoints.append((max(0.0, duration - fade_duration), "fade"))
        checkpoints.sort(key=lambda checkpoint: checkpoint[0])

        elapsed = 0.0
        for offset, kind in checkpoints:
            wait_time = offset - elapsed
            if wait_time > 0:
                if cancel_event.wait(timeout=wait_time):
                    return
                elapsed = offset

            if kind == "warning":
                self._hooks.run("warning_hook")
            else:  # "fade" -- always run for exactly what's left until `duration`
                if not self._do_fade(cancel_event, duration - elapsed):
                    return
                elapsed = duration

        final_wait = duration - elapsed
        if final_wait > 0:
            if cancel_event.wait(timeout=final_wait):
                return

        self._do_stop_action()

        with self._lock:
            if self._cancel_event is cancel_event:  # not superseded by a restart/extend/stop meanwhile
                self._status = Timer.STOPPED
                self._started_at = None
                self._duration = 0.0
                self._fading = False
                self._thread = None
                self._cancel_event = None

    def _do_fade(self, cancel_event: threading.Event, fade_seconds: float) -> bool:
        """Ramp the volume down to 0 over fade_seconds seconds. Returns
        False if cancelled partway through."""
        try:
            start_volume = int(self._mpd.call("status").get("volume", 0))
        except Exception:
            start_volume = 0

        with self._lock:
            self._original_volume = start_volume
            self._fading = True

        if start_volume <= 0 or fade_seconds <= 0:
            return not cancel_event.is_set()

        steps = max(1, int(fade_seconds))
        tick_interval = fade_seconds / steps
        for step in range(1, steps + 1):
            if cancel_event.wait(timeout=tick_interval):
                return False
            target = max(0, round(start_volume * (1 - step / steps)))
            try:
                self._mpd.call("setvol", target)
            except Exception:
                pass
        return True

    def _do_stop_action(self) -> None:
        try:
            self._mpd.call("pause", 1)
        except Exception as e:
            self._logger.warning("Error pausing MPD: %s", e)
        # Restore volume for next time now that playback is paused --
        # otherwise the next play starts silently at 0.
        if self._original_volume is not None:
            try:
                self._mpd.call("setvol", self._original_volume)
            except Exception:
                pass
        self._logger.info("Timer fired, playback paused")
        self._hooks.run("stop_hook")


class Route:
    __slots__ = ("pattern", "method_name")

    def __init__(self, pattern: "re.Pattern", method_name: str):
        self.pattern = pattern
        self.method_name = method_name


def build_handler_class(timer: Timer, index_html: str, logger: logging.Logger,
                         http_username: str = "", http_password: str = ""):
    routes = [
        Route(re.compile(r"/?$"), "_index"),
        Route(re.compile(r"/timer$"), "_timer_status"),
        Route(re.compile(r"/timer/(?P<duration>[.0-9a-zA-Z]+)/start$"), "_timer_start"),
        Route(re.compile(r"/timer/stop$"), "_timer_stop"),
        Route(re.compile(r"/timer/restart$"), "_timer_restart"),
        Route(re.compile(r"/timer/(?P<duration>[.0-9a-zA-Z]+)/extend$"), "_timer_extend"),
    ]

    auth_required = bool(http_username or http_password)
    expected_header = "Basic " + base64.b64encode(f"{http_username}:{http_password}".encode()).decode()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            logger.info("%s - %s", self.address_string(), fmt % args)

        def _respond(self, status: int, content_type: str, body: str) -> None:
            body_bytes = body.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body_bytes)))
            self.end_headers()
            self.wfile.write(body_bytes)

        def _json(self, status: int, obj: dict) -> None:
            self._respond(status, "application/json", json.dumps(obj))

        def _authenticated(self) -> bool:
            if not auth_required:
                return True
            # Constant-time comparison so response timing can't leak how
            # much of the credential was guessed correctly.
            return hmac.compare_digest(self.headers.get("Authorization", ""), expected_header)

        def _require_auth(self) -> None:
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="mpd-auto-stop"')
            self.send_header("Content-Length", "0")
            self.end_headers()

        def do_GET(self):
            if not self._authenticated():
                self._require_auth()
                return

            path = urlparse.urlparse(self.path).path
            for route in routes:
                match = route.pattern.match(path)
                if match:
                    getattr(self, route.method_name)(match)
                    return
            self._respond(404, "text/plain", "Not found")

        def _index(self, match):
            self._respond(200, "text/html", index_html)

        def _timer_status(self, match):
            self._json(200, timer.get_status())

        def _timer_start(self, match):
            try:
                self._json(200, timer.start(match.group("duration")))
            except ValueError as e:
                self._json(400, {"error": str(e)})
            except Exception as e:
                self._json(500, {"error": str(e)})

        def _timer_stop(self, match):
            try:
                self._json(200, timer.stop())
            except Exception as e:
                self._json(500, {"error": str(e)})

        def _timer_restart(self, match):
            try:
                self._json(200, timer.restart())
            except InvalidTimerStateError as e:
                self._json(400, {"error": str(e)})
            except Exception as e:
                self._json(500, {"error": str(e)})

        def _timer_extend(self, match):
            try:
                self._json(200, timer.extend(match.group("duration")))
            except (ValueError, InvalidTimerStateError) as e:
                self._json(400, {"error": str(e)})
            except Exception as e:
                self._json(500, {"error": str(e)})

    return Handler


class App:
    """The HTTP server itself. Uses the public serve_forever()/shutdown()
    API (unlike the tool this is based on, which drove a private
    _handle_request_noblock() method directly -- that bypassed the
    select()-based wait serve_forever()/handle_request() rely on, so a
    SIGTERM wouldn't actually stop the process until the next incoming
    request happened to arrive)."""

    def __init__(self, host: str, port: int, handler_class, logger: logging.Logger):
        self._server = ThreadingHTTPServer((host, port), handler_class)
        self._logger = logger

    def run(self) -> None:
        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)
        self._logger.info("Starting server @ %s:%s", *self._server.server_address[:2])
        self._server.serve_forever()
        self._logger.info("Stopped.")

    def _handle_signal(self, signum, frame) -> None:
        self._logger.info("Received signal %s, stopping server...", signum)
        # shutdown() blocks until serve_forever()'s loop exits, so it must
        # run on a different thread than the one currently inside
        # serve_forever() (this signal handler runs on that same thread).
        threading.Thread(target=self._server.shutdown, daemon=True).start()


def build_logger(verbose: bool) -> logging.Logger:
    logger = logging.getLogger("mpd-auto-stop")
    logger.setLevel(logging.DEBUG if verbose else logging.INFO)
    if verbose:
        handler = logging.StreamHandler()
    else:
        handler = logging.FileHandler(LOG_FILE)
    handler.setFormatter(logging.Formatter("%(asctime)s - %(levelname)s - %(message)s"))
    logger.addHandler(handler)
    return logger


def build_app(args: argparse.Namespace, config: configparser.SectionProxy, logger: logging.Logger) -> App:
    mpd_host = args.mpd_host or config.get("mpd_host", fallback="localhost")
    mpd_port = args.mpd_port or config.getint("mpd_port", fallback=6600)
    mpd_password = args.mpd_password or config.get("mpd_password", fallback="") or None
    http_host = args.http_host or config.get("http_host", fallback="0.0.0.0")
    http_port = args.http_port or config.getint("http_port", fallback=9090)
    http_username = args.http_username or config.get("http_username", fallback="")
    http_password = args.http_password or config.get("http_password", fallback="")

    mpd = MPDConnection(mpd_host, mpd_port, mpd_password)
    hooks = Hooks(config)
    timer = Timer(mpd, config, hooks, logger)

    template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "index.html")
    with open(template_path) as f:
        index_html = f.read()

    handler_class = build_handler_class(timer, index_html, logger, http_username, http_password)
    return App(http_host, http_port, handler_class, logger)


def start_daemon(args: argparse.Namespace, config: configparser.SectionProxy) -> None:
    """Forks the process, creates a new session, and runs the server in the
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

    logger = build_logger(verbose=False)
    app = build_app(args, config, logger)
    app.run()
    os.remove(PID_FILE)


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


def main() -> None:
    parser = argparse.ArgumentParser(description="mpd-auto-stop: a sleep-timer daemon for MPD")
    parser.add_argument("-a", "--http-host", default=None, help="Host to run the server on. Overrides mpd-auto-stop.conf.")
    parser.add_argument("-p", "--http-port", default=None, type=int, help="Port for the server to listen on. Overrides mpd-auto-stop.conf.")
    parser.add_argument("-H", "--mpd-host", default=None, help="MPD host. Overrides mpd-auto-stop.conf.")
    parser.add_argument("-P", "--mpd-port", default=None, type=int, help="MPD port. Overrides mpd-auto-stop.conf.")
    parser.add_argument("-w", "--mpd-password", default=None, help="MPD password. Overrides mpd-auto-stop.conf.")
    parser.add_argument("-U", "--http-username", default=None, help="HTTP Basic Auth username. Overrides mpd-auto-stop.conf.")
    parser.add_argument("-W", "--http-password", default=None, help="HTTP Basic Auth password. Overrides mpd-auto-stop.conf.")
    parser.add_argument("-s", "--stop", action="store_true", help="Stop the daemon")
    parser.add_argument("-v", "--verbose", action="store_true", help="Run in the foreground with console logging")
    args = parser.parse_args()

    if args.stop:
        stop_daemon()
        return

    check_permissions()
    config = load_config()

    if args.verbose:
        logger = build_logger(verbose=True)
        app = build_app(args, config, logger)
        app.run()
    else:
        start_daemon(args, config)


if __name__ == "__main__":
    main()
