#!/usr/bin/env python3
"""
MPD Radio Tray

A system tray app (similar to RadioTray-NG) for managing categorized radio station URLs
with MPD (Music Player Daemon). Offers quick control via tray menu for:

- Stopping playback
- Categorized stations
- Refreshing station list
- Exiting application

Uses `python-mpd2` internally.

Configuration:
    Settings (MPD host/port, optional custom tray icon) live in
    ~/.config/mpd-radio-tray/mpd-radio-tray.conf, seeded from
    mpd-radio-tray.conf.example on first run. The station list lives in
    ~/.config/mpd-radio-tray/stations.txt, seeded from stations.txt.example.
"""

import configparser
import os
import shutil
import sys
from collections import defaultdict
from pathlib import Path
from typing import Optional, Dict, List, Tuple

from PyQt5.QtWidgets import QApplication, QMenu, QSystemTrayIcon, QAction
from PyQt5.QtGui import QIcon, QCursor
from mpd import MPDClient

SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_DIR = Path.home() / ".config" / "mpd-radio-tray"
CONFIG_FILE = CONFIG_DIR / "mpd-radio-tray.conf"
STATIONS_FILE = CONFIG_DIR / "stations.txt"

# Seconds to wait on an MPD connection/command before giving up, so a hung
# or unreachable server can't freeze the GUI (Qt's event loop is
# single-threaded, and every MPD call here runs synchronously on it).
MPD_TIMEOUT = 5


def load_config() -> Dict[str, object]:
    """
    Seed ~/.config/mpd-radio-tray/ from the .example templates shipped
    alongside this script on first run, then load settings from the config
    file there.
    """
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    if not CONFIG_FILE.exists():
        shutil.copy(SCRIPT_DIR / "mpd-radio-tray.conf.example", CONFIG_FILE)
        print(f"[Info] Created {CONFIG_FILE} -- edit it to customize settings.")

    if not STATIONS_FILE.exists():
        shutil.copy(SCRIPT_DIR / "stations.txt.example", STATIONS_FILE)
        print(f"[Info] Created {STATIONS_FILE} -- edit it to add your own stations.")

    parser = configparser.ConfigParser()
    parser.read(CONFIG_FILE)

    return {
        "mpd_host": parser.get("mpd-radio-tray", "mpd_host", fallback="localhost"),
        "mpd_port": parser.getint("mpd-radio-tray", "mpd_port", fallback=6600),
        "icon_path": parser.get("mpd-radio-tray", "icon_path", fallback="").strip(),
    }


CONFIG = load_config()


def connect_mpd(tray_icon: Optional["MPDTrayApp"] = None) -> Optional[MPDClient]:
    """Connect to the MPD server and return the client instance."""
    client = MPDClient()
    client.timeout = MPD_TIMEOUT
    try:
        client.connect(CONFIG["mpd_host"], CONFIG["mpd_port"])
        return client
    except Exception as e:
        message = f"Could not connect to MPD: {e}"
        print(f"[MPD Error] {message}")
        if tray_icon:
            tray_icon.notify_error(message)
        return None


def load_stations() -> Dict[str, List[Tuple[str, str]]]:
    """
    Load stations from file, grouped by category.

    Returns:
        Dictionary of categories to list of (name, url) tuples.
    """
    stations_by_category = defaultdict(list)

    if not STATIONS_FILE.exists():
        print(f"[Warning] Station file '{STATIONS_FILE}' not found.")
        return stations_by_category

    with open(STATIONS_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("|", 2)
            if len(parts) == 3:
                category, name, url = parts
                stations_by_category[category].append((name, url))
            else:
                print(f"[Warning] Malformed station line: {line}")

    return stations_by_category


def load_station(url: str, tray_icon: Optional["MPDTrayApp"] = None) -> None:
    """
    Load and play a radio URL using MPD.

    Args:
        url: The radio stream URL to play.
        tray_icon: Tray icon to surface errors on, if any.
    """
    client = connect_mpd(tray_icon)
    if not client:
        return

    try:
        client.clear()
        client.add(url)
        client.play()
        print(f"[Info] Now playing: {url}")
    except Exception as e:
        message = f"Failed to load URL: {e}"
        print(f"[MPD Error] {message}")
        if tray_icon:
            tray_icon.notify_error(message)
    finally:
        client.close()
        client.disconnect()


def stop_playback(tray_icon: Optional["MPDTrayApp"] = None) -> None:
    """Stop MPD playback and clear the queue."""
    client = connect_mpd(tray_icon)
    if not client:
        return

    try:
        client.stop()
        client.clear()
        print("[Info] Playback stopped.")
    except Exception as e:
        message = f"Failed to stop playback: {e}"
        print(f"[MPD Error] {message}")
        if tray_icon:
            tray_icon.notify_error(message)
    finally:
        client.close()
        client.disconnect()


class MPDTrayApp(QSystemTrayIcon):
    """Main tray application class."""

    def __init__(self, icon: QIcon, parent=None):
        super().__init__(icon, parent)
        self.menu = QMenu()
        self.refresh_menu()
        self.setContextMenu(self.menu)
        self.setToolTip("MPD Radio Tray")
        self.activated.connect(self.on_activate)
        self.check_mpd_connection()

    def check_mpd_connection(self) -> None:
        """
        Verify MPD is reachable at startup and give a visible indication
        (tray notification + tooltip) if it isn't, rather than staying
        silent until the user clicks a station and wonders why nothing
        happens. The tray icon and menu still come up either way, so the
        user can start MPD and hit Refresh without restarting this app.
        """
        client = connect_mpd()
        if client:
            client.close()
            client.disconnect()
        else:
            self.setToolTip("MPD Radio Tray (MPD not running)")
            self.notify_error("Could not connect to MPD -- is it running?")

    def notify_error(self, message: str) -> None:
        """Surface an error via a tray balloon notification, since print()
        output is invisible when this app is launched from a desktop
        launcher with no attached terminal."""
        self.showMessage("MPD Radio Tray", message, QSystemTrayIcon.Warning, 5000)

    def refresh_menu(self) -> None:
        """Rebuild the tray menu from station file."""
        # QMenu.clear() removes actions from the menu but doesn't
        # necessarily delete objects created with an explicit parent, so
        # explicitly release the previous rebuild's actions (and any
        # submenus they represent) first to avoid leaking them each time
        # this is called (e.g. via repeated manual Refresh clicks).
        for action in self.menu.actions():
            submenu = action.menu()
            if submenu is not None:
                submenu.deleteLater()
            action.deleteLater()
        self.menu.clear()

        stop_action = QAction("Stop", self.menu)
        stop_action.triggered.connect(lambda: stop_playback(self))
        self.menu.addAction(stop_action)

        stations_by_category = load_stations()
        for category, stations in stations_by_category.items():
            category_menu = QMenu(category, self.menu)
            for name, url in stations:
                action = QAction(name, category_menu)
                action.triggered.connect(lambda _, u=url: load_station(u, self))
                category_menu.addAction(action)
            self.menu.addMenu(category_menu)

        refresh_action = QAction("Refresh", self.menu)
        refresh_action.triggered.connect(self.refresh_menu)
        self.menu.addAction(refresh_action)

        exit_action = QAction("Exit", self.menu)
        exit_action.triggered.connect(QApplication.quit)
        self.menu.addAction(exit_action)

    def on_activate(self, reason: QSystemTrayIcon.ActivationReason) -> None:
        """Show context menu on left click."""
        if reason == QSystemTrayIcon.Trigger:
            self.contextMenu().popup(QCursor.pos())


def create_icon() -> QIcon:
    """Load the tray icon."""
    icon_path = CONFIG["icon_path"]
    if icon_path and os.path.exists(icon_path):
        return QIcon(icon_path)
    return QIcon.fromTheme("media-playback-start")


def main() -> None:
    """Application entry point."""
    app = QApplication(sys.argv)
    tray_icon = create_icon()
    tray_app = MPDTrayApp(tray_icon)
    tray_app.show()
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
