# mpd-scripts - volume

| Script Name    | Description                                                                   |
|----------------|-------------------------------------------------------------------------------|
| [volume.py](./volume.py)    | Adjust MPD volume using python-mpd library.                                    |
| [mpdvolup.py](./mpdvolup.py)| Increase MPD volume using python-mpd library.                                  |
| [mpdvoldown.py](./mpdvoldown.py)| Decrease MPD volume using python-mpd library.  

  
### Prerequisites
python-mpd2

### Installation
```
pip install python-mpd2
```

### Configuration

Settings live in `~/.config/mpd-scripts/volume/mpd-extended.conf`, seeded from [`mpd-extended.conf.example`](./mpd-extended.conf.example) by `install.sh` (or run `functions/update-mpd-extended-cfg.py` and `functions/add-mpd-script-section.py` directly).

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../../LICENSE) for more information.
