#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vim: ai ts=4 sw=4 sts=4 expandtab

"""Shared config/state path handling for mpd-algo-playlist.

Follows this repo's convention: user-editable settings live under
~/.config/mpd-scripts/mpd-algo-playlist/, seeded from the .example
templates shipped alongside the scripts the first time any of them run;
runtime state (LMDB database, PID file, monitor log) lives under
~/.local/state/mpd-algo-playlist/.
"""

import os
import shutil
import configparser
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_DIR = Path.home() / ".config" / "mpd-scripts" / "mpd-algo-playlist"
STATE_DIR = Path.home() / ".local" / "state" / "mpd-algo-playlist"

CONFIG_FILE = CONFIG_DIR / "config.ini"

# Companion list files seeded the same way as config.ini: template name ->
# live name, both ending up in CONFIG_DIR once seeded.
_SEEDED_LISTS = {
    "exclude_files.txt.example": "exclude_files.txt",
    "exclude_artists.txt.example": "exclude_artists.txt",
    "exclude_genres.txt.example": "exclude_genres.txt",
    "notify_urls.txt.example": "notify_urls.txt",
}


def _seed(template_name, live_path):
    if live_path.exists():
        return
    shutil.copyfile(SCRIPT_DIR / template_name, live_path)


def load_config():
    """Seed config.ini and the exclude/notify list files from their
    .example templates on first run, then parse and return config.ini."""
    CONFIG_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)

    _seed("config.ini.example", CONFIG_FILE)
    os.chmod(CONFIG_FILE, 0o600)  # may hold the MPD password

    for template_name, live_name in _SEEDED_LISTS.items():
        _seed(template_name, CONFIG_DIR / live_name)

    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    return config


def ensure_state_dir():
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    return STATE_DIR
