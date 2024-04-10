# mpd-scripts - volume
## WIP: May not work currently

These scripts provide a straightforward way to control the volume of your Music Player Daemon (MPD).  They work with both the mpc command and the python-mpd library.

Simple commands allow you to adjust the volume up, down, or to a specific level.  For safety, you can enable maximum volume protection through a toggle in the configuration file. This will prevent the volume from exceeding your chosen limit.

| Name              | Description              |
| --- | --- |
| **[volume (python-mpd based)](./python-mpd/)** | Volume scripts using the python library python-mpd. |
| **[volume (mpc cli based)](./mpc/)** | Volume scripts directly using the mpc client directly. |
***
#### License: [GPLv3](../LICENSE)