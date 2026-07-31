#!/usr/bin/env python3

"""
Shared Last.fm authentication and current-track lookup for loved.py/unloved.py.

Handles config loading (seeded from lastfm-love.conf.example on first run),
the pylast web-auth session flow, and querying MPD via mpc for the
currently playing track.
"""

import configparser
import os
import subprocess
import sys
import time
import webbrowser

import pylast

CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".config", "lastfm-love")
CONFIG_FILE = os.path.join(CONFIG_DIR, "lastfm-love.conf")
SESSION_KEY_FILE = os.path.join(CONFIG_DIR, "session_key")


def load_config():
    """
    Loads Last.fm credentials from ~/.config/lastfm-love/lastfm-love.conf.

    If that doesn't exist yet, it's seeded from a lastfm-love.conf sitting
    next to this module if one exists (e.g. an already-filled-in config
    from before it was moved under ~/.config), otherwise from the blank
    lastfm-love.conf.example template.

    Returns:
        configparser.SectionProxy: the "lastfm-love" section.
    """
    if not os.path.exists(CONFIG_FILE):
        os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
        script_dir = os.path.dirname(os.path.abspath(__file__))
        local_conf = os.path.join(script_dir, "lastfm-love.conf")
        template = os.path.join(script_dir, "lastfm-love.conf.example")
        source = local_conf if os.path.exists(local_conf) else template

        with open(source) as src, open(CONFIG_FILE, "w") as dst:
            dst.write(src.read())
        os.chmod(CONFIG_FILE, 0o600)  # Contains credentials

        if source == template:
            print(f"Created {CONFIG_FILE} -- edit it with your Last.fm API key/secret and account details, then run this again.")
            sys.exit(1)
        else:
            print(f"Copied existing {local_conf} to {CONFIG_FILE}.")

    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    return config["lastfm-love"]


def get_network():
    """
    Builds an authenticated pylast.LastFMNetwork, running the one-time web
    auth flow if no cached session key exists yet.

    Returns:
        pylast.LastFMNetwork
    """
    config = load_config()
    network = pylast.LastFMNetwork(
        api_key=config["api_key"],
        api_secret=config["api_secret"],
        username=config["username"],
        password_hash=pylast.md5(config["password"]),
    )

    if not os.path.exists(SESSION_KEY_FILE):
        skg = pylast.SessionKeyGenerator(network)
        url = skg.get_web_auth_url()

        print(f"Please authorize this script to access your account: {url}\n")
        webbrowser.open(url)

        while True:
            try:
                session_key = skg.get_web_auth_session_key(url)
                with open(SESSION_KEY_FILE, "w") as f:
                    f.write(session_key)
                os.chmod(SESSION_KEY_FILE, 0o600)  # Contains credentials
                break
            except pylast.WSError:
                time.sleep(1)
    else:
        with open(SESSION_KEY_FILE) as f:
            session_key = f.read()

    network.session_key = session_key
    return network


def get_current_track():
    """
    Queries mpc for the currently playing track's artist and title.

    Prefers the track's own artist over the album artist, since compilation
    albums often have an album artist like "Various Artists" that doesn't
    match any individual track's real performer.

    Returns:
        tuple[str, str] | tuple[None, None]: (artist, title), or (None, None)
        if nothing is currently playing.
    """
    output = subprocess.run(
        ["mpc", "-f", "%artist%\n%albumartist%\n%title%"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    lines = output.split("\n")
    artist = lines[0] if len(lines) > 0 else ""
    albumartist = lines[1] if len(lines) > 1 else ""
    title = lines[2] if len(lines) > 2 else ""

    artist = artist or albumartist

    if not artist or not title:
        return None, None
    return artist, title
