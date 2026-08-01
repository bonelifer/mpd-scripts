# mpd-scripts - volume

These scripts provide a straightforward way to control the volume of your Music Player Daemon (MPD).  They work with both the mpc command and the python-mpd library.

Simple commands allow you to adjust the volume up, down, or to a specific level.  For safety, you can enable maximum volume protection through a toggle in the configuration file. This will prevent the volume from exceeding your chosen limit.

| Name              | Description              |
| --- | --- |
| **[volume (python-mpd based)](./python-mpd/)** | Volume scripts using the python library python-mpd. |
| **[volume (mpc cli based)](./mpc/)** | Volume scripts using the mpc client directly. |

Install only ONE of the two — both variants install the same three filenames (`mpdvolup.py`, `mpdvoldown.py`, `volume.py`), so installing both would overwrite one with the other. `./install.sh` in the repo root will prompt you to choose if you run it, but if you're picking manually:

- **mpc-based**: shells out to the `mpc` command-line tool for every call. Simpler and needs no Python library, matching most other scripts in this repo that already talk to MPD via `mpc`.
- **python-mpd2-based**: talks to MPD directly over its protocol via the `python-mpd2` library instead of spawning `mpc` each time. Effectively "free" to add if you're also installing `mpd_rewind_daemon` or `mpd-radio-tray`, since both already depend on `python-mpd2`.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.