#!/usr/bin/env python3

"""
Unloves the currently playing MPD track on Last.fm, via pylast.
"""

import sys

from lastfm_common import get_current_track, get_network


def main():
    artist, title = get_current_track()
    if not artist or not title:
        print("Nothing is currently playing.", file=sys.stderr)
        sys.exit(1)

    network = get_network()
    track = network.get_track(artist, title)
    track.unlove()
    print(f"Unloved '{title}' by '{artist}'.")


if __name__ == "__main__":
    main()
