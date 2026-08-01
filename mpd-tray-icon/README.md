# MPD Control Tray Icon

A GTK3 tray icon showing the currently playing MPD track in its tooltip/menu, with Play/Pause, Next, and Previous controls. Based on [MPD_Tray](https://github.com/sc8/MPD_Tray/).

## Requirements

- `mpc`
- GTK3 and AppIndicator3 Python bindings (PyGObject), e.g. on Debian/Ubuntu: `sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1` (package name for the AppIndicator3 typelib varies by distro/version — look for `gir1.2-appindicator3` if the one above isn't available).
- A tray host that supports AppIndicator3/KStatusNotifierItem. Stock GNOME Shell doesn't — install the "AppIndicator and KStatusNotifierItem Support" extension if the icon doesn't appear. KDE Plasma, XFCE, and most other desktop environments support it natively.

## Usage

MPD must already be running — the script checks on startup and exits if it isn't.

```bash
./mpd-tray-icon.py
```

The tray icon's label/tooltip shows the current track (or "Stopped"/"MPD not running" as appropriate), and updates automatically whenever playback state changes (blocking on `mpc idle player` in a background thread — no polling). Left-click the icon for the menu:

- **Play/Pause**
- **Next**
- **Previous**
- **Quit**

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
