# mpd-usb-automount

Keeps MPD's music library on a removable USB disk that's mounted only when actually needed -- a stable device name via `udev` (survives reboots/enumeration-order changes), on-demand mounting via `autofs`, and an idle spindown timer, so the disk isn't spinning 24/7 on a device like a Raspberry Pi.

> **This installer is not wired into `mpd-scripts`' top-level `install.sh`.** It needs root, writes to `/etc` (udev rules, autofs config) rather than your home directory, and needs your specific disk's hardware IDs. Run it deliberately and separately: `cd mpd-usb-automount && sudo ./install.sh ...`.

## How it works

MPD's `music_directory` in `mpd.conf` stays pointed at the boring, always-present default (`/var/lib/mpd/music`) -- never at the removable disk directly. A **symlink** inside that directory (e.g. `Music` → `/media/mpd-auto/mpd-disk/Music`) is the only thing that points at the USB disk, and `follow_outside_symlinks`/`follow_inside_symlinks` are both set to `"yes"` specifically so MPD is willing to traverse it (MPD refuses to follow symlinks by default).

Because `autofs` only mounts `/media/mpd-auto/mpd-disk` on first *access* rather than on existence check, MPD can start and browse its library structure without forcing the drive to spin up -- it only mounts, and the disk only spins up, the moment something actually reads through that symlink (an initial database scan, or later, playback). It unmounts again after 60 seconds idle.

## Requirements

- `udev` (standard on any Linux distro)
- `autofs` (the installer offers to `apt install` it if missing)
- `hdparm`
- A USB disk you can identify by vendor/product/serial ID

## Installation

```bash
cd mpd-usb-automount

# Plug in the disk, then let install.sh find its vendor/product/serial
# automatically:
sudo ./install.sh --detect /dev/sdX1

# ...or specify them directly if you already know them:
sudo ./install.sh --vendor 0951 --product 1666 --serial 60A44C4B1234ABCD
```

This installs the udev rule, the autofs map and drop-in config, and the hdparm helper script, then reloads udev and restarts autofs. It also checks whether `/etc/mpd.conf` already has the required directives and tells you if not (it won't edit `mpd.conf` itself -- see [mpd.conf.snippet](./mpd.conf.snippet)).

**Remaining manual steps** (the installer prints these at the end too):

1. Confirm the disk shows up: `ls -l /dev/mpd-disk`
2. Symlink MPD's music directory to the disk's actual music folder:
   ```bash
   cd /var/lib/mpd/music
   sudo ln -s /media/mpd-auto/mpd-disk/Music Music
   ```
   (adjust `Music` to your disk's actual top-level folder name)
3. Restart MPD and run an initial database update:
   ```bash
   sudo systemctl restart mpd
   mpc update
   ```

## Files

| File | Installed to |
| --- | --- |
| [`10-mpd-disk.rules.example`](./10-mpd-disk.rules.example) | `/etc/udev/rules.d/10-mpd-disk.rules` (with your disk's IDs substituted in) |
| [`mpd-disk.autofs`](./mpd-disk.autofs) | `/etc/auto.master.d/mpd-disk.autofs` |
| [`auto.mpd-disk`](./auto.mpd-disk) | `/etc/auto.mpd-disk` |
| [`hdparm-mpd-disk.sh`](./hdparm-mpd-disk.sh) | `/usr/local/sbin/hdparm-mpd-disk.sh` |
| [`mpd.conf.snippet`](./mpd.conf.snippet) | *(reference only -- add to `/etc/mpd.conf` by hand)* |

## Uninstallation

```bash
sudo rm /etc/udev/rules.d/10-mpd-disk.rules
sudo rm /etc/auto.master.d/mpd-disk.autofs
sudo rm /etc/auto.mpd-disk
sudo rm /usr/local/sbin/hdparm-mpd-disk.sh
sudo udevadm control --reload-rules
sudo systemctl restart autofs
```
Then remove the `follow_outside_symlinks`/`follow_inside_symlinks` lines from `/etc/mpd.conf` and the `Music` symlink under your `music_directory`, if you no longer want them.

## Acknowledgments

Based on a [gist by daks](https://gist.github.com/daks/8030543). Changes from the original:

- The original's `hdparm-mpd-disk.sh` checked power status on a hardcoded `/dev/sda` while setting the spindown timer on the stable `/dev/mpd-disk` symlink -- inconsistent, and defeats the udev rule's entire purpose (a stable name specifically because raw `/dev/sdX` naming isn't reliable) for that one check. Both commands now consistently target `/dev/mpd-disk`.
- Output is now logged via `logger` instead of silently discarded -- `udev RUN+=` scripts have no visible stdout/stderr otherwise, so a failure (missing `hdparm`, device gone) previously vanished without a trace.
- `install.sh --detect DEVICE` reads `udevadm info --query=property`'s already-resolved `ID_VENDOR_ID`/`ID_MODEL_ID`/`ID_SERIAL_SHORT` properties directly, instead of requiring you to manually walk `udevadm info -a -p` parent-device output looking for a unique attribute combination.
- The autofs map moved from a shared `/media/auto` + `auto.media` (which could collide with an unrelated existing autofs map on the same system) to a dedicated `/media/mpd-auto` + `auto.mpd-disk`, and uses the modern `/etc/auto.master.d/*.autofs` drop-in mechanism instead of requiring an edit to the shared `/etc/auto.master`.
- `hdparm-mpd-disk.sh` installs to `/usr/local/sbin` (the conventional location for locally-added system scripts) rather than `/root/bin`.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](../LICENSE) for more information.
