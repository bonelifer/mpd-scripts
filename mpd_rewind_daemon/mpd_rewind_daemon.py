#!/usr/bin/env python3
"""
MPD Rewind Daemon

This script runs as a daemon that listens to the MPD (Music Player Daemon) server.
When playback resumes from a paused state, it rewinds the track by a set amount of time.
The daemon supports logging and verbose output for debugging purposes.

Configuration:
- rewind_tiers, mpd_host, mpd_port, mpd_password, genre_filter_enabled,
  genre_filter: see
  ~/.config/mpd-scripts/mpd_rewind_daemon/mpd_rewind_daemon.conf (seeded
  from mpd_rewind_daemon.conf.example on first run).
- PID_FILE: Location to store the daemon process ID (PID) (default: "~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.pid").
- LOG_FILE: Location for the daemon log file (default: "~/.local/state/mpd_rewind_daemon/mpd_rewind_daemon.log").
- Permissions check for the state directory.
- Enhanced error logging for daemon mode.
"""

import sys
import os
import time
import signal
import argparse
import logging
import configparser
from mpd import MPDClient
from mpd import ConnectionError as MPDConnectionError

# Configuration Constants
STATE_DIR = os.path.join(os.path.expanduser("~"), ".local", "state", "mpd_rewind_daemon")
PID_FILE = os.path.join(STATE_DIR, "mpd_rewind_daemon.pid")  # Path for PID file
LOG_FILE = os.path.join(STATE_DIR, "mpd_rewind_daemon.log")  # Path for log file

CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".config", "mpd-scripts", "mpd_rewind_daemon")
CONFIG_FILE = os.path.join(CONFIG_DIR, "mpd_rewind_daemon.conf")

def load_config():
    """
    Loads settings from
    ~/.config/mpd-scripts/mpd_rewind_daemon/mpd_rewind_daemon.conf, seeding
    it from the mpd_rewind_daemon.conf.example template shipped alongside
    this script on first run.

    Returns:
        configparser.SectionProxy: the "mpd_rewind_daemon" section.
    """
    if not os.path.exists(CONFIG_FILE):
        os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
        template = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mpd_rewind_daemon.conf.example")
        with open(template) as src, open(CONFIG_FILE, "w") as dst:
            dst.write(src.read())
        os.chmod(CONFIG_FILE, 0o600)  # May contain an MPD password

    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    return config["mpd_rewind_daemon"]

DEFAULT_REWIND_TIERS = [(5.0, 5.0), (15.0, 15.0), (30.0, 30.0), (60.0, 60.0)]

def parse_rewind_tiers(raw):
    """
    Parses a "paused_seconds:rewind_seconds,..." string (e.g. from the
    rewind_tiers config setting) into a list of (threshold, rewind) float
    pairs, sorted ascending by threshold.

    Args:
        raw (str): The raw config value.

    Returns:
        list[tuple[float, float]]: Parsed tiers, or DEFAULT_REWIND_TIERS if
        raw is empty or malformed.
    """
    tiers = []
    for pair in raw.split(","):
        pair = pair.strip()
        if not pair:
            continue
        try:
            threshold_str, rewind_str = pair.split(":")
            tiers.append((float(threshold_str), float(rewind_str)))
        except ValueError:
            print(f"Warning: ignoring malformed rewind_tiers entry {pair!r}.")

    if not tiers:
        return DEFAULT_REWIND_TIERS
    tiers.sort(key=lambda tier: tier[0])
    return tiers

def parse_genre_filter(raw):
    """
    Parses a comma-separated genre_filter config value into a set of
    lowercased, trimmed genre names for case-insensitive membership checks.

    Args:
        raw (str): The raw config value.

    Returns:
        set[str]: Lowercased genre names (empty if raw has none).
    """
    return {genre.strip().lower() for genre in raw.split(",") if genre.strip()}

_config = load_config()
REWIND_TIERS = parse_rewind_tiers(_config.get("rewind_tiers", fallback=""))
MPD_HOST = _config.get("mpd_host", fallback="localhost")
MPD_PORT = _config.getint("mpd_port", fallback=6600)
MPD_PASSWORD = _config.get("mpd_password", fallback="")
GENRE_FILTER_ENABLED = _config.getboolean("genre_filter_enabled", fallback=False)
GENRE_FILTER = parse_genre_filter(_config.get("genre_filter", fallback=""))

def check_permissions():
    """
    Ensure the state directory (which holds the PID and log files) exists
    and is writable, creating it -- and any missing parent directories --
    if needed. If permissions are insufficient, the script exits.
    """
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
    except OSError as e:
        print(f"Permission denied: Cannot create {STATE_DIR}: {e}")
        sys.exit(1)

    if not os.access(STATE_DIR, os.W_OK):
        print(f"Permission denied: Cannot write to {STATE_DIR}.")
        sys.exit(1)

class MPDRewindDaemon:
    """
    MPD Rewind Daemon that listens for MPD pause events and rewinds playback when resumed.

    Attributes:
        verbose (bool): Flag to enable verbose logging.
        running (bool): Flag to control the running state of the daemon.
        client (MPDClient): MPD client for communication with the MPD server.
        last_state (str): Tracks the last state of the MPD player ("play" or "pause").
        pause_started_at (float | None): time.time() when the last pause began.
    """

    def __init__(self, verbose=False):
        """
        Initializes the MPD Rewind Daemon with logging setup.

        Args:
            verbose (bool): Whether to run in verbose mode (default: False).
        """
        self.verbose = verbose  # Set the verbose mode flag
        self.running = True  # Daemon is initially running
        self.client = None  # MPD client instance will be created later
        self.last_state = None  # Tracks last player state (play or pause)
        self.pause_started_at = None  # When the current/last pause began

        # Set logging configuration based on verbose mode
        log_level = logging.DEBUG if verbose else logging.INFO
        logging.basicConfig(filename=LOG_FILE if not verbose else None,
                            level=log_level,
                            format="%(asctime)s - %(levelname)s - %(message)s")
        self.logger = logging.getLogger()

    def log(self, message):
        """
        Logs a message to both the console (if verbose) and log file.

        Args:
            message (str): The message to log.
        """
        if self.verbose:
            print(f"[MPDRewindDaemon] {message}")
        self.logger.info(message)

    def connect(self):
        """
        Connects to the MPD server.

        This method creates a new MPDClient, closes the previous connection (if any),
        and attempts to connect to the MPD server at MPD_HOST:MPD_PORT (and
        authenticates if MPD_PASSWORD is set). Raises
        MPDConnectionError/OSError on failure; callers should use
        connect_with_retry() instead of calling this directly unless they
        want to handle a failed connection themselves.
        """
        if self.client:
            try:
                self.client.close()  # Close any existing client connection
                self.client.disconnect()  # Disconnect the client
            except Exception as e:
                self.log(f"Error disconnecting client: {e}")

        # Create a new MPD client and set timeouts
        self.client = MPDClient()
        self.client.timeout = 10  # Timeout for MPD client connection
        self.client.idletimeout = None  # Disable idle timeout

        self.client.connect(MPD_HOST, MPD_PORT)
        if MPD_PASSWORD:
            self.client.password(MPD_PASSWORD)
        self.log(f"Connected to MPD at {MPD_HOST}:{MPD_PORT}.")

    def connect_with_retry(self):
        """
        Keeps attempting to connect (e.g. MPD not started yet, or restarting)
        until successful or the daemon is told to stop, logging and backing
        off between attempts instead of giving up after one failed attempt.
        """
        while self.running:
            try:
                self.connect()
                return
            except (MPDConnectionError, OSError) as e:
                self.log(f"Failed to connect to MPD ({e}). Retrying in 5s...")
                time.sleep(5)

    def handle_signal(self, signum, frame):
        """
        Handles termination signals (SIGTERM and SIGINT) for graceful shutdown.

        This method ensures that the MPD client disconnects and the PID file is removed
        when the daemon is stopped.
        """
        self.log("Stopping MPD rewind daemon...")
        self.running = False  # Stop the daemon
        if self.client:
            try:
                self.client.close()
                self.client.disconnect()
            except Exception as e:
                self.log(f"Error disconnecting client during shutdown: {e}")

        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)  # Remove the PID file
            self.log("PID file removed.")

        sys.exit(0)

    def get_rewind_amount(self, pause_duration):
        """
        Looks up how many seconds to rewind based on how long playback was
        paused, using REWIND_TIERS (sorted ascending by threshold). Returns
        the rewind amount for the largest threshold that's <= pause_duration,
        or 0 if the pause was shorter than the smallest threshold.

        Args:
            pause_duration (float): How many seconds playback was paused for.

        Returns:
            float: Seconds to rewind (0 if no tier applies).
        """
        amount = 0.0
        for threshold, rewind in REWIND_TIERS:
            if pause_duration >= threshold:
                amount = rewind
            else:
                break
        return amount

    def current_track_genre_allowed(self):
        """
        Returns True if genre_filter_enabled is off, or the currently
        playing track's genre (case-insensitive) is in genre_filter. A
        track with no genre tag -- or one not in the list -- is not
        allowed once filtering is enabled, so an empty genre_filter with
        filtering enabled disables rewinding entirely.

        Returns:
            bool: Whether rewind_and_resume should proceed for this track.
        """
        if not GENRE_FILTER_ENABLED:
            return True

        try:
            current = self.client.currentsong()
        except Exception as e:
            self.log(f"Error fetching current song for genre filter: {e}")
            return False

        genre = current.get("genre", [])
        # MPD returns a list instead of a plain string when a track has
        # multiple genre tag values.
        genres = genre if isinstance(genre, list) else [genre]
        track_genres = {g.strip().lower() for g in genres if g.strip()}

        return bool(track_genres & GENRE_FILTER)

    def rewind_and_resume(self, pause_duration):
        """
        Pauses, rewinds, and resumes playback to ensure proper rewind.

        This method pauses the current track, seeks to a rewind position, and resumes playback.
        The rewind amount scales with how long playback was paused (see get_rewind_amount).
        Skipped entirely if genre_filter_enabled is on and the current
        track's genre isn't in genre_filter (see current_track_genre_allowed).

        Args:
            pause_duration (float): How many seconds playback was paused for.
        """
        if not self.current_track_genre_allowed():
            self.log("Current track's genre is not in genre_filter; skipping rewind.")
            return

        seek_back_time = self.get_rewind_amount(pause_duration)
        if seek_back_time <= 0:
            self.log(f"Paused for {pause_duration:.2f}s; too brief to rewind.")
            return

        try:
            status = self.client.status()  # Fetch current MPD status
            if status.get("state") == "play":
                position = float(status.get("elapsed", 0))  # Get current playback position
                seek_time = max(position - seek_back_time, 0)  # Calculate new seek position

                self.log(f"Pausing playback to rewind...")
                self.client.pause(1)  # Pause playback

                time.sleep(0.2)  # Small delay to ensure state change

                self.log(f"Paused for {pause_duration:.2f}s; rewinding {seek_back_time:.2f}s. Seeking to {seek_time:.2f}s...")
                self.client.seekcur(seek_time)  # Seek to the new position

                self.log("Resuming playback after rewind.")
                self.client.pause(0)  # Resume playback
        except Exception as e:
            self.log(f"Error during rewind operation: {e}")

    def listen(self):
        """
        Listens for MPD playback state changes (pause/unpause) and applies rewind on resume.

        This method runs in a loop and checks for changes in the player state. It triggers
        a rewind when playback resumes from a paused state.
        """
        signal.signal(signal.SIGTERM, self.handle_signal)  # Handle termination signal
        signal.signal(signal.SIGINT, self.handle_signal)  # Handle interrupt signal

        self.connect_with_retry()  # Connect to the MPD server, retrying until it's up
        self.log("MPD Rewind Daemon started. Listening for pause/unpause events...")

        while self.running:
            try:
                self.client.idle("player")  # Wait for player state change
                status = self.client.status()  # Fetch current status
                current_state = status.get("state")  # Get current playback state

                # Check for state transitions
                if current_state == "pause" and self.last_state == "play":
                    self.log("Detected MPD pause event.")
                    self.pause_started_at = time.time()

                elif current_state == "play" and self.last_state == "pause":
                    pause_duration = (time.time() - self.pause_started_at) if self.pause_started_at else 0.0
                    self.log(f"Detected playback resume event after {pause_duration:.2f}s pause. Applying rewind.")
                    self.rewind_and_resume(pause_duration)  # Apply rewind on resume
                    self.pause_started_at = None

                self.last_state = current_state  # Update last known state

            except (MPDConnectionError, OSError):
                self.log("Lost connection to MPD, attempting to reconnect...")
                self.connect_with_retry()  # Keep retrying until reconnected
            except Exception as e:
                self.log(f"Error during MPD state monitoring: {e}")
                time.sleep(2)  # Wait before retrying on error

def start_daemon():
    """
    Starts the script as a background daemon process.

    This method forks the process, creates a new session, checks permissions, and then
    starts the MPDRewindDaemon to listen for events.
    """
    if os.path.exists(PID_FILE):
        print("Daemon is already running.")
        sys.exit(1)

    pid = os.fork()  # Fork the process to run in the background
    if pid > 0:
        sys.exit(0)  # Parent process exits

    os.setsid()  # Create a new session to detach from the terminal

    # Ensure necessary permissions are set for PID and log files
    check_permissions()

    # Write the PID to a file for managing the daemon process
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))

    daemon = MPDRewindDaemon(verbose=False)  # Initialize the daemon
    daemon.listen()  # Start listening for MPD events

def stop_daemon():
    """
    Stops the daemon by killing the process with the stored PID.

    This method checks if the daemon is running, and if so, sends a SIGTERM signal
    to gracefully stop the process.
    """
    if not os.path.exists(PID_FILE):
        print("Daemon is not running.")
        sys.exit(1)

    with open(PID_FILE, "r") as f:
        pid = int(f.read().strip())  # Read the PID of the running daemon

    # Check if the process is still running
    try:
        os.kill(pid, 0)  # Check if the process exists without sending a signal
    except ProcessLookupError:
        # If the process does not exist
        print(f"No process found with PID {pid}. The daemon may have already stopped.")
        os.remove(PID_FILE)  # Remove the stale PID file
        sys.exit(0)
    except PermissionError:
        # If permission is denied to check the process
        print(f"Permission error while checking process with PID {pid}.")
        sys.exit(1)

    # If the process is running, send SIGTERM to stop it
    os.kill(pid, signal.SIGTERM)
    print("Daemon stopped.")

def run_interactive():
    """
    Runs the daemon in the foreground with verbose console logging, instead
    of forking to the background and writing a PID file. Useful for
    debugging (see --verbose).
    """
    daemon = MPDRewindDaemon(verbose=True)  # Initialize the daemon
    daemon.listen()  # Start listening for MPD events

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="MPD Rewind Daemon")
    parser.add_argument("-s", "--stop", action="store_true", help="Stop the daemon")
    parser.add_argument("-v", "--verbose", action="store_true", help="Run in interactive mode with logging")
    args = parser.parse_args()

    if args.stop:
        stop_daemon()  # Stop the daemon if requested
    elif args.verbose:
        run_interactive()  # Run in verbose mode if requested
    else:
        start_daemon()  # Start the daemon normally

