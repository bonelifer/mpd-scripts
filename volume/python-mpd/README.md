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

Settings live in `~/.config/mpd-scripts/volume/volume.conf`, seeded from [`volume.conf.example`](./volume.conf.example) by `install.sh` (or run `functions/update-volume-conf.py` and `functions/add-mpd-script-section.py` directly).

| Setting           | Description                                                    | Default |
| ----------------- | ---------------------------------------------------------------- | ------- |
| `volUp`           | Amount to increase by when no amount is given                    | `5`     |
| `volDown`         | Amount to decrease by when no amount is given                    | `5`     |
| `toggleMaxVolume` | When `True`, the "up" direction won't raise volume past `maxVolume`, no matter how large an amount is requested | `False` |
| `maxVolume`       | The volume cap enforced when `toggleMaxVolume` is `True`         | `80`    |

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../../LICENSE) for more information.
