#!/usr/bin/bash

# alarmpd installer chooser
#
# Prompts you to pick between install-xdg-autostart.sh and
# install-systemd.sh (see their own headers, or README.md, for full
# details), then runs the one you choose. Skip this and run either of
# those two directly if you already know which one you want.

set -e  # Exit on error

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
cd "$SCRIPT_DIR"

cat <<'EOF'
alarmpd can be installed one of two ways:

  A) XDG autostart (default) -- a plain background process started via a
     desktop autostart .desktop entry. Works on any desktop session, no
     systemd required. Pick this unless you have a specific reason to
     want B: it's simpler, and is the one to use on a minimal/embedded
     setup or any session without a working `systemd --user`. If it
     crashes, it stays down until your next login; logs go to its own
     file (~/.local/state/alarmpd/alarmpd.log).

  B) systemd --user service -- pick this if you want the daemon to
     automatically restart if it crashes, or want its logs in
     `journalctl` alongside your other services, and you're on a
     desktop Linux distro with a normal `systemd --user` session
     (true for most; not for some minimal/embedded/WSL1 setups).

EOF

read -t 30 -r -p "Install via [A]utostart or [S]ystemd? (default: A, auto-selected in 30s) " choice || true
echo

case "${choice:-A}" in
    [Ss]*) exec ./install-systemd.sh ;;
    *)     exec ./install-xdg-autostart.sh ;;
esac
