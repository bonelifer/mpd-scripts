#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vim: ai ts=4 sw=4 sts=4 expandtab

import os
import sys
import signal
import time
import logging
import argparse
from mpd import CommandError
from db import env, lastplayed, skipcount, playcount, keyof
from client import connect
from paths import load_config, STATE_DIR, ensure_state_dir

# Configuration
config = load_config()
ensure_state_dir()

SKIP_DETECTION_ENABLED = config.getboolean('features', 'skip_detection', fallback=True)
PLAY_COUNTS_ENABLED = config.getboolean('features', 'play_counts', fallback=True)
SKIP_THRESHOLD = config.getfloat('behavior', 'skip_threshold', fallback=0.5)

# PID/log files - entirely user-space, no root needed (unlike the old
# /var/run + /var/log system-service layout this used to have).
PID_FILE = STATE_DIR / "monitor.pid"
LOG_FILE = STATE_DIR / "monitor.log"

# Logging setup
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(str(LOG_FILE)),
        logging.StreamHandler()
    ]
)
log = logging.getLogger('mpd_monitor')

def write_pid():
    """Write the current PID to file"""
    try:
        with open(PID_FILE, 'w') as f:
            f.write(str(os.getpid()))
        PID_FILE.chmod(0o644)
        log.info(f"PID file created at {PID_FILE}")
    except Exception as e:
        log.error(f"Failed to write PID file: {str(e)}")
        sys.exit(1)

def remove_pid():
    """Remove the PID file"""
    try:
        if PID_FILE.exists():
            PID_FILE.unlink()
            log.info("PID file removed")
    except Exception as e:
        log.error(f"Failed to remove PID file: {str(e)}")

def kill_existing():
    """Kill existing monitor process"""
    if not PID_FILE.exists():
        return False
        
    try:
        with open(PID_FILE) as f:
            pid = int(f.read().strip())

        os.kill(pid, signal.SIGTERM)
        time.sleep(1)

        if PID_FILE.exists():
            # SIGKILL can't be caught, so the process never gets to run its
            # own remove_pid() - clean up the stale file ourselves instead
            # of treating its continued presence as a failed kill.
            os.kill(pid, signal.SIGKILL)
            time.sleep(0.5)
            remove_pid()

        log.info(f"Stopped existing process (PID: {pid})")
        return True
    except ProcessLookupError:
        log.info("Process already gone")
        remove_pid()
        return True
    except Exception as e:
        log.error(f"Error killing existing process: {str(e)}")
        return False

def main():
    parser = argparse.ArgumentParser(description='MPD Play Monitor')
    parser.add_argument('-k', '--kill', action='store_true', help='Stop running monitor')
    args = parser.parse_args()

    if args.kill:
        if kill_existing():
            sys.exit(0)
        else:
            sys.exit(1)

    # Check for existing process
    if PID_FILE.exists():
        log.error("Monitor already running (PID file exists)")
        sys.exit(1)

    # Register signal handlers
    def handle_signal(signum, frame):
        log.info(f"Received signal {signum}, shutting down...")
        remove_pid()
        client.disconnect()
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    # Write PID file
    write_pid()

    # Initialize MPD connection
    client = connect(
        host=config['mpd']['host'],
        port=config['mpd']['port'],
        password=config['mpd']['password'] or None
    )

    log.info("Starting MPD play monitor...")

    # Tracks the currently-anchored song for skip detection: wall-clock time
    # is used as a stand-in for "elapsed", since MPD only tells us a track
    # changed after the fact, not how far the outgoing one got. This slightly
    # overestimates elapsed time if the track was paused mid-play, which only
    # biases toward under-counting skips, never over-counting them.
    track = {"song_id": None, "key": None, "duration": 0.0, "started_wall": 0.0}

    def record_skip_if_due():
        if not SKIP_DETECTION_ENABLED or track["key"] is None or track["duration"] <= 0:
            return
        played = max(0.0, time.time() - track["started_wall"])
        fraction = played / track["duration"]
        if fraction >= SKIP_THRESHOLD:
            return
        try:
            with env.begin(db=skipcount, write=True) as txn:
                prev = txn.get(track["key"])
                count = (int(prev.decode()) if prev else 0) + 1
                txn.put(track["key"], str(count).encode("utf-8"))
            log.debug(f"Recorded skip ({fraction:.0%} played, count={count})")
        except Exception as e:
            log.error(f"Failed to record skip: {str(e)}", exc_info=True)

    try:
        while True:
            events = client.idle()
            if "player" not in events:
                continue

            status = client.status()
            current = client.currentsong()

            song_id = current.get("id") if current else None
            if song_id != track["song_id"]:
                record_skip_if_due()
                track.update(song_id=song_id, key=None, duration=0.0, started_wall=0.0)

            if not current:
                continue

            if not all(key in current for key in ["file", "artist", "title"]):
                log.debug("Skipping incomplete track metadata")
                continue

            key = keyof(current["artist"], current["title"])

            if SKIP_DETECTION_ENABLED and status.get("state") == "play" and track["key"] is None:
                duration = float(current.get("duration") or status.get("duration") or 0)
                elapsed = float(status.get("elapsed", 0) or 0)
                track.update(key=key, duration=duration, started_wall=time.time() - elapsed)

            now = str(time.time())

            try:
                client.sticker_set("song", current["file"], "lastplayed_unixtime", now)
                with env.begin(write=True) as txn:
                    txn.put(key, now.encode("utf-8"), db=lastplayed)
                    if PLAY_COUNTS_ENABLED:
                        prev = txn.get(key, db=playcount)
                        count = (int(prev.decode()) if prev else 0) + 1
                        txn.put(key, str(count).encode("utf-8"), db=playcount)
                log.debug(f"Recorded play: {current['artist']} - {current['title']}")
            except Exception as e:
                log.error(f"Failed to record play: {str(e)}", exc_info=True)

    except Exception as e:
        log.error(f"Fatal error: {str(e)}", exc_info=True)
        sys.exit(1)
    finally:
        remove_pid()
        client.disconnect()

if __name__ == "__main__":
    main()
