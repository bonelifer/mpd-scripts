#!/usr/bin/bash

# Checks whether a personal bin directory is already on PATH, and if not,
# offers to create ~/bin and add it. Also checks/offers the same for
# ~/bin/music, used by some scripts in this repo for music-related data
# files. Run this once before following the Installation steps in
# README.md.

set -e  # Exit on error

# Common personal bin directories to check for, in order of preference.
CANDIDATE_DIRS=("$HOME/bin" "$HOME/.local/bin" "/usr/local/sbin" "/usr/local/bin")

# Pick the shell's rc file so PATH changes survive new shells.
case "$(basename "${SHELL:-bash}")" in
    zsh)  RC_FILE="$HOME/.zshrc" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
    *)    RC_FILE="$HOME/.profile" ;;
esac

# Returns success if $1 is already on PATH.
on_path() {
    echo ":$PATH:" | grep -q ":$1:"
}

# Creates $1 if needed and appends a PATH export for it to RC_FILE, unless
# one's already there.
add_dir_to_path() {
    local dir="$1"
    mkdir -p "$dir"

    local export_line="export PATH=\"$dir:\$PATH\""
    if ! grep -qsF "$export_line" "$RC_FILE" 2>/dev/null; then
        echo "$export_line" >> "$RC_FILE"
        echo "Created $dir and added it to PATH in $RC_FILE."
    else
        echo "Created $dir (PATH entry already present in $RC_FILE)."
    fi
}

FOUND_DIR=""
for dir in "${CANDIDATE_DIRS[@]}"; do
    if [ -d "$dir" ] && on_path "$dir"; then
        FOUND_DIR="$dir"
        break
    fi
done

if [ -n "$FOUND_DIR" ]; then
    echo "Found $FOUND_DIR already on your PATH. Copy scripts there; no changes needed."
else
    echo "No personal bin directory (${CANDIDATE_DIRS[*]}) was found on your PATH."
    read -r -p "Create ~/bin and add it to your PATH? [y/N] " REPLY

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        add_dir_to_path "$HOME/bin"
    else
        echo "Skipped ~/bin. Add a directory to your PATH manually, then see README.md's Installation section."
    fi
fi

# ~/bin/music is a separate, optional directory some scripts in this repo
# use for music-related data files -- handled independently of the
# general-purpose CANDIDATE_DIRS check above.
if [ -d "$HOME/bin/music" ] && on_path "$HOME/bin/music"; then
    echo "Found $HOME/bin/music already on your PATH. No changes needed there."
else
    read -r -p "Create ~/bin/music and add it to your PATH too? [y/N] " REPLY

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        add_dir_to_path "$HOME/bin/music"
    else
        echo "Skipped ~/bin/music."
    fi
fi

echo "Run 'source $RC_FILE' or open a new shell for any changes to take effect."
