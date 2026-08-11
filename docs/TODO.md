# mpd-scripts - TODO

- **Auto-bookmark-on-pause**: automatically save a bookmark when playback pauses/stops, so `mpdmark load` becomes a generic "resume where you left off." This is daemon-shaped work (listens for MPD pause/stop events, like `mpd_rewind_daemon`) rather than an on-demand CLI action, so it belongs in its own project directory (e.g. `mpd_autobookmark_daemon/`) instead of inside `mpdmark/`, sharing `mpdmark`'s JSON bookmark-sticker format so both tools can read/write the same bookmarks.
