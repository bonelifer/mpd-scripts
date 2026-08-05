#!/usr/bin/env python
# vim: ai ts=4 sw=4 sts=4 expandtab fileencoding=utf-8

import lmdb
import logging
from pathlib import Path
from paths import load_config, STATE_DIR, ensure_state_dir

log = logging.getLogger(__name__)

config = load_config()
ensure_state_dir()

# Database Configuration
# Relative db_file paths resolve against STATE_DIR, not the caller's cwd, so
# monitor.py/randomtrack.py find the same db regardless of how (cron,
# systemd, shell) they're launched.
_db_file = Path(config['paths']['db_file']).expanduser()
if not _db_file.is_absolute():
    _db_file = STATE_DIR / _db_file
DB_PATH = str(_db_file)
# map_size is reserved virtual address space, not disk usage - LMDB backs it
# with a sparse file, so oversizing costs nothing at rest. 1GiB comfortably
# covers a 200k+ track library (two databases, ~small key/value pairs each)
# with room to grow.
DB_SIZE = 1 * 1024 * 1024 * 1024  # 1GiB

# Initialize LMDB environment
env = lmdb.open(
    DB_PATH,
    max_dbs=5,  # lastqueued, lastplayed, skipcount, playcount, + 1 spare
    map_size=DB_SIZE,
    meminit=False,
    lock=True
)

# Open databases
lastqueued = env.open_db(b'lastqueued')
lastplayed = env.open_db(b'lastplayed')
skipcount = env.open_db(b'skipcount')
playcount = env.open_db(b'playcount')

_NAMED_DBS = {
    "lastqueued": lastqueued,
    "lastplayed": lastplayed,
    "skipcount": skipcount,
    "playcount": playcount,
}

def keyof(artist, title):
    """Generate a consistent key from artist and title"""
    return f"{artist}\t{title}".encode('utf-8').replace(b'\t', b'\\t').replace(b'\n', b'\\n')

# Optional maintenance functions
def compact_database(output_path):
    """Write a compacted copy of the database to output_path.

    Does not touch the live, currently-open database - swap the compacted
    copy in manually (with all readers/writers stopped) if you want to
    replace it.
    """
    env.copy(output_path, compact=True)
    log.info(f"Compacted copy written to {output_path}")

def backup_database(backup_path):
    """Create a text backup of all named sub-databases"""
    with open(backup_path, 'wb') as f:
        for name, db in _NAMED_DBS.items():
            with env.begin(db=db, write=False) as txn:
                for key, value in txn.cursor():
                    f.write(name.encode('utf-8') + b':::' + key + b':::' + value + b'\n')
    log.info(f"Database backup created at {backup_path}")
