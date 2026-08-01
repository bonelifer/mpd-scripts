#!/usr/bin/env python3
"""
MPD control notification icon + show song name in tooltip.
Based on https://github.com/sc8/MPD_Tray/

Note: uses AppIndicator3, which stock GNOME Shell doesn't support
natively -- install the "AppIndicator and KStatusNotifierItem Support"
extension if the icon doesn't appear.
"""

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
from gi.repository import Gtk, GLib, AppIndicator3
import subprocess
import threading
import time
import os

class MPDIndicator:
    """Tray icon showing the current MPD track, with Play/Pause/Next/Previous controls."""

    def __init__(self):
        """Builds the tray icon and its menu, then starts the background player-state watcher."""
        icon_path = self.get_icon_path()

        self.indicator = AppIndicator3.Indicator.new(
            "mpd-indicator",
            icon_path,
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS
        )
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        self.build_menu()

        # Show current state immediately, then update again only when MPD's
        # player state actually changes, via a background thread blocking on
        # `mpc idle player` -- no polling.
        self.update_track()
        threading.Thread(target=self.watch_player, daemon=True).start()

    def get_icon_path(self):
        """Returns the first existing icon path from a preference list, or a
        named fallback icon from the desktop theme if none exist."""
        paths = [
            os.path.expanduser("/usr/share/icons/hicolor/scalable/apps/mpd.svg"),
            "/usr/share/icons/gnome/22x22/actions/player_pause.png",
            "/usr/share/icons/Adwaita/22x22/legacy/media-playback-start.png"
        ]
        for path in paths:
            if os.path.exists(path):
                return path
        return "media-playback-start"

    def build_menu(self):
        """Builds the tray icon's context menu: current track label, playback
        controls, and quit."""
        self.menu = Gtk.Menu()

        self.track_item = Gtk.MenuItem(label="MPD starting...")
        self.menu.append(self.track_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        play_pause = Gtk.MenuItem(label="Play/Pause")
        play_pause.connect("activate", self.toggle)
        self.menu.append(play_pause)

        next_track = Gtk.MenuItem(label="Next")
        next_track.connect("activate", self.next_track)
        self.menu.append(next_track)

        prev_track = Gtk.MenuItem(label="Previous")
        prev_track.connect("activate", self.prev_track)
        self.menu.append(prev_track)

        self.menu.append(Gtk.SeparatorMenuItem())

        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", Gtk.main_quit)
        self.menu.append(quit_item)

        self.menu.show_all()
        self.indicator.set_menu(self.menu)

    def watch_player(self):
        """Blocks on `mpc idle player`, refreshing the label via the GTK main
        loop whenever playback state changes."""
        # Blocks until MPD reports a player-state change, then asks the GTK
        # main loop to refresh the label (GLib.idle_add is the safe way to
        # touch GTK widgets from a background thread). A non-zero exit
        # (MPD unreachable) backs off briefly instead of busy-looping.
        while True:
            result = subprocess.run(
                ['mpc', 'idle', 'player'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            if result.returncode != 0:
                time.sleep(2)
                continue
            GLib.idle_add(self.update_track)

    def update_track(self):
        """Fetches the current track from mpc and updates the tray label and
        tooltip, showing "MPD not running" if mpc fails."""
        try:
            result = subprocess.run(
                ['mpc', 'current'],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode != 0:
                raise RuntimeError(result.stderr.strip() or "mpc failed")

            track = result.stdout.strip() or "Stopped"
            self.track_item.set_label(track)
            self.indicator.set_label(track, "")

        except Exception:
            self.track_item.set_label("MPD not running")
            self.indicator.set_label("", "")

        return False  # one-shot: don't re-run this via GLib.idle_add

    def toggle(self, event):
        subprocess.Popen(['mpc', 'toggle'])

    def next_track(self, event):
        subprocess.Popen(['mpc', 'next'])

    def prev_track(self, event):
        subprocess.Popen(['mpc', 'prev'])

if __name__ == '__main__':
    # Check if MPD is running
    try:
        subprocess.check_call(["mpc", "status"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        print("MPD is not running. Please start MPD first.")
        exit(1)

    Gtk.init([])
    indicator = MPDIndicator()
    Gtk.main()
