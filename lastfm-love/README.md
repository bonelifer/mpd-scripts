# mpd-scripts - lastfm-love
#### Based on the [PyLast](https://github.com/pylast/pylast) ([readme](https://github.com/pylast/pylast/blob/main/README.md)) example with changes to automate submitting via info from mpc
  * loved.py    - when called will query mpc for the current artist and title and love the track on lastfm
  * unloved.py  - when called will query mpc for the current aritst and title and unlove the track on lastfm

Need to update these keys in the [love.py](love.py) **·** [unloved.py](unloved.py) files  
API_KEY  
API_SECRET  
username  
password_hash (with an md5 hash of your password)  

***
#### License: [GPLv3](../LICENSE)