#!/usr/bin/env python

import pylast
import os

"""
This script interacts with Last.fm's API through pylast to love a currently playing track and 
add tags to it using MPC (Music Player Command Line).
"""


# You have to have your own unique two values for API_KEY and API_SECRET
# Obtain yours from https://www.last.fm/api/account/create for Last.fm
API_KEY = "XXXreplacethisXXX"  # this is a sample key
API_SECRET = "XXXreplacethisXXX"

# In order to perform a write operation you need to authenticate yourself
username = "yourusername"
password_hash = pylast.md5("yourMD5edpasswordhash")

SESSION_KEY_FILE = os.path.join(os.path.expanduser("~"), ".session_key")
network = pylast.LastFMNetwork(API_KEY, API_SECRET)
if not os.path.exists(SESSION_KEY_FILE):
    skg = pylast.SessionKeyGenerator(network)
    url = skg.get_web_auth_url()

    print(f"Please authorize this script to access your account: {url}\n")
    import time
    import webbrowser

    webbrowser.open(url)

    while True:
        try:
            session_key = skg.get_web_auth_session_key(url)
            with open(SESSION_KEY_FILE, "w") as f:
                f.write(session_key)
            break
        except pylast.WSError:
            time.sleep(1)
else:
    session_key = open(SESSION_KEY_FILE).read()

network.session_key = session_key



artist = os.popen("/usr/bin/mpc -f %albumartist%").read()
artist = artist.split('\n')[0]

title = os.popen("/usr/bin/mpc -f %title%").read()
title = title.split('\n')[0]

# Now you can use that object everywhere
track = network.get_track(artist, title)
track.love()
track.add_tags(("awesome", "favorite"))

# Type help(pylast.LastFMNetwork) or help(pylast) in a Python interpreter
# to get more help about anything and see examples of how it works
