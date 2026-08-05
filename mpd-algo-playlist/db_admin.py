#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vim: ai ts=4 sw=4 sts=4 expandtab

"""Maintenance CLI for the mpd-algo-playlist LMDB database."""

import argparse
from db import env, playcount, backup_database, compact_database


def cmd_stats(args):
    with env.begin(db=playcount) as txn:
        counts = [(key.decode("utf-8", "replace"), int(value.decode())) for key, value in txn.cursor()]

    print(f"Tracked tracks: {len(counts)}")
    if not counts:
        return

    counts.sort(key=lambda item: item[1], reverse=True)
    top = min(args.top, len(counts))

    print(f"\nTop {top} most played:")
    for key, count in counts[:top]:
        print(f"  {count:>5}  {key}")

    print(f"\nTop {top} least played:")
    for key, count in reversed(counts[-top:]):
        print(f"  {count:>5}  {key}")


def main():
    ap = argparse.ArgumentParser(description="Maintenance utility for mpd-algo-playlist's LMDB database")
    sub = ap.add_subparsers(dest="command", required=True)

    p_compact = sub.add_parser("compact", help="Write a compacted copy of the database")
    p_compact.add_argument("-o", "--output", required=True, help="Path to write the compacted copy to")

    p_backup = sub.add_parser("backup", help="Back up the database to a text file")
    p_backup.add_argument("-o", "--output", required=True, help="Path to write the backup to")

    p_stats = sub.add_parser("stats", help="Show play-count statistics")
    p_stats.add_argument(
        "-n", "--top", type=int, default=10,
        help="Number of tracks to show in each list (default: %(default)s)"
    )

    args = ap.parse_args()

    if args.command == "compact":
        compact_database(args.output)
    elif args.command == "backup":
        backup_database(args.output)
    elif args.command == "stats":
        cmd_stats(args)


if __name__ == "__main__":
    main()
