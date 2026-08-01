# mpd-scripts - volume


| Script Name    | Description                                                                   |
|----------------|-------------------------------------------------------------------------------|
| [volume.py](./volume.py)           | Adjust MPD volume using mpc command-line tool.                                 |
| [mpdvolup.py](./mpdvolup.py)       | Increase MPD volume using mpc command-line tool.                               |
| [mpdvoldown.py](./mpdvoldown.py)   | Decrease MPD volume using mpc command-line tool.    
  
### Prerequisites
mpc

### Installation
```
apt install mpc
```
If you aren't using a Debian/Ubuntu based system consult your distrobution for package name and install method.

### Configuration

Settings live in `~/.config/mpd-scripts/volume/volume.conf`, seeded from [`volume.conf.example`](./volume.conf.example) by `install.sh` (or run `functions/update-mpd-extended-cfg.py` and `functions/add-mpd-script-section.py` directly).

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../../LICENSE) for more information.
