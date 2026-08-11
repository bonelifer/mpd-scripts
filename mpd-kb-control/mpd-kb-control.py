#!/usr/bin/env python3
"""
mpd-kb-control

Dispatches multimedia-key presses to MPD, for binding to a window manager's
keybindings (XF86AudioPlay, XF86AudioNext, etc.).

Usage:
    mpd-kb-control.py {play,next,prev,raise,lower,mute,consume,random,repeat,single}

Commands:
    play     Toggle play/pause. If MPD is stopped, starts playback instead
             (unlike relying on a text-scraped "[playing]"/"[paused]"
             status, this reads MPD's actual state field directly, so the
             stopped case is handled rather than silently doing nothing).
    next     Skip to the next track.
    prev     Skip to the previous track.
    raise    Raise the volume by volume_step (clamped to max_volume, if
             enforce_max_volume is enabled).
    lower    Lower the volume by volume_step.
    mute     Toggle mute: saves the current volume and sets it to 0, or
             restores the last saved volume if already at 0.
    consume  Toggle consume mode (played tracks are removed from the queue).
    random   Toggle random (shuffle) mode.
    repeat   Toggle repeat mode.
    single   Toggle single mode (stop, or repeat the same track, after it
             finishes, depending on repeat).

None of consume/random/repeat/single have a dedicated multimedia key on a
standard keyboard -- see README.md for examples binding them on a separate
keypad instead.

Connection settings and behavior come from
~/.config/mpd-scripts/mpd-kb-control/mpd-kb-control.conf, seeded from
mpd-kb-control.conf.example on first run.
"""

import argparse
import configparser
import fcntl
import os
import subprocess
import sys

from mpd import MPDClient, CommandError
from socket import error as SocketError

CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".config", "mpd-scripts", "mpd-kb-control")
CONFIG_FILE = os.path.join(CONFIG_DIR, "mpd-kb-control.conf")

STATE_DIR = os.path.join(os.path.expanduser("~"), ".local", "state", "mpd-kb-control")
VOLUME_SAVE_FILE = os.path.join(STATE_DIR, "volume_save")
MUTE_LOCK_FILE = os.path.join(STATE_DIR, "mute.lock")


def die(msg: str) -> None:
    """Print an error message to stderr and exit with status 1."""
    sys.stderr.write(msg)
    sys.stderr.write("\n")
    sys.exit(1)


def load_config() -> configparser.SectionProxy:
    """Load ~/.config/mpd-scripts/mpd-kb-control/mpd-kb-control.conf, seeding
    it from the mpd-kb-control.conf.example template shipped alongside this
    script on first run.

    Returns:
        configparser.SectionProxy: the "mpd-kb-control" section.
    """
    if not os.path.exists(CONFIG_FILE):
        os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
        template = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mpd-kb-control.conf.example")
        with open(template) as src, open(CONFIG_FILE, "w") as dst:
            dst.write(src.read())
        os.chmod(CONFIG_FILE, 0o600)  # May contain an MPD password

    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    return config["mpd-kb-control"]


def notify(config: configparser.SectionProxy, message: str) -> None:
    """Show a desktop notification via notify-send, if notify is enabled in
    the config and notify-send is available. Never fatal -- a missing
    notification daemon (e.g. on a headless or minimal WM setup) shouldn't
    break volume/playback control."""
    if not config.getboolean("notify", fallback=False):
        return
    try:
        subprocess.run(["notify-send", "MPD", message], check=False, capture_output=True)
    except FileNotFoundError:
        pass


def cmd_play(client: MPDClient, config: configparser.SectionProxy) -> None:
    """Toggle play/pause; starts playback if MPD is currently stopped."""
    state = client.status()["state"]
    if state == "play":
        client.pause(1)
        notify(config, "Paused")
    else:
        client.play()
        notify(config, "Playing")


def cmd_next(client: MPDClient, config: configparser.SectionProxy) -> None:
    client.next()


def cmd_prev(client: MPDClient, config: configparser.SectionProxy) -> None:
    client.previous()


def _adjust_volume(client: MPDClient, config: configparser.SectionProxy, delta: int) -> None:
    current = int(client.status().get("volume", 0))
    target = max(0, min(100, current + delta))

    if delta > 0 and config.getboolean("enforce_max_volume", fallback=False):
        max_volume = config.getint("max_volume", fallback=100)
        target = min(target, max_volume)

    client.setvol(target)
    notify(config, f"Volume: {target}%")


def cmd_raise(client: MPDClient, config: configparser.SectionProxy) -> None:
    step = config.getint("volume_step", fallback=5)
    _adjust_volume(client, config, step)


def cmd_lower(client: MPDClient, config: configparser.SectionProxy) -> None:
    step = config.getint("volume_step", fallback=5)
    _adjust_volume(client, config, -step)


def cmd_mute(client: MPDClient, config: configparser.SectionProxy) -> None:
    """Toggle mute: save the current (non-zero) volume and zero it, or
    restore the last saved volume if already at 0.

    Held under an exclusive file lock spanning both the MPD status check
    and the save-file read/write, so two mute invocations firing close
    together (a double-tap, or a duplicate keybinding) serialize instead
    of racing -- the second one waits for the first to finish rather than
    both reading the pre-mute volume and stepping on each other's save.
    """
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(MUTE_LOCK_FILE, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)

        current_volume = int(client.status().get("volume", 0))
        if current_volume != 0:
            with open(VOLUME_SAVE_FILE, "w") as f:
                f.write(str(current_volume))
            client.setvol(0)
            notify(config, "Muted")
        else:
            try:
                with open(VOLUME_SAVE_FILE) as f:
                    saved_volume = int(f.read().strip())
            except (FileNotFoundError, ValueError):
                saved_volume = 0

            if config.getboolean("enforce_max_volume", fallback=False):
                max_volume = config.getint("max_volume", fallback=100)
                saved_volume = min(saved_volume, max_volume)

            client.setvol(saved_volume)
            notify(config, f"Unmuted ({saved_volume}%)")


def _make_toggle(mode: str, setter_name: str, label: str):
    """Build a command function that toggles one of MPD's boolean playback
    modes (consume/random/repeat/single): reads the current 0/1 value from
    status(), flips it via the matching setter method, and notifies."""

    def toggle(client: MPDClient, config: configparser.SectionProxy) -> None:
        current = client.status().get(mode, "0")
        new_value = 0 if current == "1" else 1
        getattr(client, setter_name)(new_value)
        notify(config, f"{label}: {'on' if new_value else 'off'}")

    toggle.__doc__ = f"Toggle {mode} mode."
    return toggle


cmd_consume = _make_toggle("consume", "consume", "Consume")
cmd_random = _make_toggle("random", "random", "Random")
cmd_repeat = _make_toggle("repeat", "repeat", "Repeat")
cmd_single = _make_toggle("single", "single", "Single")


COMMANDS = {
    "play": cmd_play,
    "next": cmd_next,
    "prev": cmd_prev,
    "raise": cmd_raise,
    "lower": cmd_lower,
    "mute": cmd_mute,
    "consume": cmd_consume,
    "random": cmd_random,
    "repeat": cmd_repeat,
    "single": cmd_single,
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Dispatch multimedia-key presses to MPD.")
    parser.add_argument("command", choices=sorted(COMMANDS), help="Action to perform")
    parser.add_argument("-H", "--host", default=None, help="MPD host. Overrides mpd-kb-control.conf.")
    parser.add_argument("-P", "--port", default=None, type=int, help="MPD port. Overrides mpd-kb-control.conf.")
    parser.add_argument("-a", "--password", default=None, help="MPD password. Overrides mpd-kb-control.conf.")
    args = parser.parse_args()

    config = load_config()
    host = args.host or config.get("mpd_host", fallback="localhost")
    port = args.port or config.getint("mpd_port", fallback=6600)
    password = args.password or config.get("mpd_password", fallback="") or None

    client = MPDClient()
    try:
        client.connect(host, port)
    except SocketError as e:
        # Invoked from a keybinding with no visible terminal, so stderr
        # alone would be silently lost -- surface failures as a
        # notification too (when enabled), not just an exit code no one
        # sees.
        notify(config, "Failed to connect to MPD")
        die(f"Failed to connect to MPD server: {e}")
    if password:
        try:
            client.password(password)
        except CommandError as e:
            notify(config, "MPD authentication failed")
            die(f"Error authenticating with MPD: {e}")

    try:
        COMMANDS[args.command](client, config)
    except CommandError as e:
        # Covers cases like play/next/prev on an empty queue, or setvol
        # with no mixer configured -- previously an uncaught traceback
        # dumped nowhere visible instead of a clean, notified failure.
        notify(config, f"'{args.command}' failed")
        die(f"MPD command failed: {e}")

    client.close()
    client.disconnect()


if __name__ == "__main__":
    main()
