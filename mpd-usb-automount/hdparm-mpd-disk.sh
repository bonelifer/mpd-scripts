#!/usr/bin/bash

#
# hdparm-mpd-disk.sh
#
# Installed to /usr/local/sbin/hdparm-mpd-disk.sh and run by udev
# (10-mpd-disk.rules) whenever the MPD disk's stable /dev/mpd-disk symlink
# appears.
#
# Always targets /dev/mpd-disk, the stable symlink the udev rule creates
# -- never a raw /dev/sdX name. The whole point of that rule is that the
# raw device name isn't reliable across boots or enumeration order, so
# using it here would defeat it.
#
# Output goes to the system log via logger, since udev RUN+= scripts have
# nowhere else visible to send stdout/stderr -- otherwise a failure here
# (e.g. hdparm not installed, or the device gone by the time this runs)
# would be silently swallowed.
#

DEVICE=/dev/mpd-disk

# Report current power status (see the -C section of `man hdparm`).
/sbin/hdparm -C "$DEVICE" 2>&1 | logger -t hdparm-mpd-disk

# Set the idle spindown timer to 2 minutes. -S takes a value 1-240 meaning
# multiples of 5 seconds (see the -S section of `man hdparm` for the full
# encoding table); 24 * 5s = 120s.
/sbin/hdparm -S 24 "$DEVICE" 2>&1 | logger -t hdparm-mpd-disk
