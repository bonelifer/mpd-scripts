#!/usr/bin/env python3
"""
MPD Rewind Daemon

This script runs as a daemon that listens to the MPD (Music Player Daemon) server.
When playback resumes from a paused state, it rewinds the track by a set amount of time.
The daemon supports logging and verbose output for debugging purposes.

Configuration:
- SEEK_BACK_TIME: Time (in seconds) to rewind after playback resumes (default: 5 seconds).
- PID_FILE: Location to store the daemon process ID (PID) (default: "/tmp/mpd_rewind_daemon.pid").
- LOG_FILE: Location for the daemon log file (default: "/var/log/mpd_rewind_daemon.log").
- Permissions check for log and PID files.
- Enhanced error logging for daemon mode.
"""

import sys
import os
import time
import signal
import argparse
import logging
from mpd import MPDClient, ConnectionError

# Configuration Constants
SEEK_BACK_TIME = 5.0  # Time to rewind in seconds
PID_FILE = "/tmp/mpd_rewind_daemon.pid"  # Path for PID file
LOG_FILE = "/var/log/mpd_rewind_daemon.log"  # Path for log file

def check_permissions():
    """
    Ensure the necessary permissions for PID and log files.

    This function checks if the daemon has write access to the required directories
    and files (PID file and log file). If permissions are insufficient, the script exits.
    """
    if not os.access("/tmp", os.W_OK):
        print("Permission denied: Cannot write to /tmp.")
        sys.exit(1)

    if not os.access(LOG_FILE, os.W_OK) and not os.path.exists(LOG_FILE):
        print(f"Permission denied: Cannot write to {LOG_FILE}. Ensure proper permissions.")
        sys.exit(1)

class MPDRewindDaemon:
    """
    MPD Rewind Daemon that listens for MPD pause events and rewinds playback when resumed.

    Attributes:
        seek_time (float): Time to rewind (set to SEEK_BACK_TIME).
        verbose (bool): Flag to enable verbose logging.
        running (bool): Flag to control the running state of the daemon.
        client (MPDClient): MPD client for communication with the MPD server.
        last_state (str): Tracks the last state of the MPD player ("play" or "pause").
    """

    def __init__(self, verbose=False):
        """
        Initializes the MPD Rewind Daemon with logging setup.

        Args:
            verbose (bool): Whether to run in verbose mode (default: False).
        """
        self.seek_time = SEEK_BACK_TIME  # Set the rewind time
        self.verbose = verbose  # Set the verbose mode flag
        self.running = True  # Daemon is initially running
        self.client = None  # MPD client instance will be created later
        self.last_state = None  # Tracks last player state (play or pause)

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
        and attempts to connect to the MPD server on localhost:6600.
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

        try:
            # Attempt to connect to the MPD server
            self.client.connect("localhost", 6600)
            self.log("Connected to MPD.")
        except ConnectionError:
            self.log("Failed to connect to MPD. Is it running?")
            sys.exit(1)

    def handle_signal(self, signum, frame):
        """
        Handles termination signals (SIGTERM and SIGINT) for graceful shutdown.

        This method ensures that the MPD client disconnects and the PID file is removed
        when the daemon is stopped.
        """
        self.log("Stopping MPD rewind daemon...")
        self.running = False  # Stop the daemon
        if self.client:
            self.client.close()
            self.client.disconnect()

        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)  # Remove the PID file
            self.log("PID file removed.")

        sys.exit(0)

    def rewind_and_resume(self):
        """
        Pauses, rewinds, and resumes playback to ensure proper rewind.

        This method pauses the current track, seeks to a rewind position, and resumes playback.
        """
        try:
            status = self.client.status()  # Fetch current MPD status
            if status.get("state") == "play":
                position = float(status.get("elapsed", 0))  # Get current playback position
                seek_time = max(position - self.seek_time, 0)  # Calculate new seek position

                self.log(f"Pausing playback to rewind...")
                self.client.pause(1)  # Pause playback
                
                time.sleep(0.2)  # Small delay to ensure state change

                self.log(f"Rewinding {self.seek_time:.2f}s. Seeking to {seek_time:.2f}s...")
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
        self.connect()  # Connect to the MPD server
        signal.signal(signal.SIGTERM, self.handle_signal)  # Handle termination signal
        signal.signal(signal.SIGINT, self.handle_signal)  # Handle interrupt signal

        self.log("MPD Rewind Daemon started. Listening for pause/unpause events...")

        while self.running:
            try:
                self.client.idle("player")  # Wait for player state change
                status = self.client.status()  # Fetch current status
                current_state = status.get("state")  # Get current playback state

                # Check for state transitions
                if current_state == "pause" and self.last_state == "play":
                    self.log("Detected MPD pause event.")

                elif current_state == "play" and self.last_state == "pause":
                    self.log("Detected playback resume event. Applying rewind.")
                    self.rewind_and_resume()  # Apply rewind on resume

                self.last_state = current_state  # Update last known state

            except ConnectionError:
                self.log("Lost connection to MPD, attempting to reconnect...")
                time.sleep(2)  # Wait before reconnecting
                self.connect()  # Attempt to reconnect
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

