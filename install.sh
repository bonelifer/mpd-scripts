#!/usr/bin/bash

# One-time setup for this repo:
# 1. Migrates any existing per-script settings from the old
#    ~/.config/<script-name>/ layout into the new unified
#    ~/.config/mpd-scripts/<script-name>/ layout.
# 2. Checks whether a personal bin directory is already on PATH, and if
#    not, offers to create ~/bin and add it. Also checks/offers the same
#    for ~/bin/music, used by some scripts in this repo for music-related
#    data files.
#
# Run this once before following the Installation steps in README.md.

set -e  # Exit on error

NESTED_CONFIG_ROOT="$HOME/.config/mpd-scripts"

# Scripts that previously stored their own settings directly under
# ~/.config/<name>/, now nested under $NESTED_CONFIG_ROOT/<name>/ instead.
CONFIG_DIRS_TO_MIGRATE=(
    "lastfm-love"
    "mpd-add-random"
    "mpd-find-dup"
    "mpd-notifier"
    "mpd-queue-shuffle"
    "mpd-radio-tray"
    "mpd_rewind_daemon"
    "mpdsimilar"
    "rm-artists-playlist"
    "rm-duplicates-playlist"
)

# Moves each script's old ~/.config/<name>/ directory to its new home
# under $NESTED_CONFIG_ROOT, if the old one exists and hasn't already
# been migrated.
migrate_config_dirs() {
    local migrated_any=false

    for name in "${CONFIG_DIRS_TO_MIGRATE[@]}"; do
        local old_dir="$HOME/.config/$name"
        local new_dir="$NESTED_CONFIG_ROOT/$name"

        if [ -d "$old_dir" ] && [ ! -e "$new_dir" ]; then
            mkdir -p "$NESTED_CONFIG_ROOT"
            mv "$old_dir" "$new_dir"
            echo "Migrated $old_dir -> $new_dir"
            migrated_any=true
        fi
    done

    # volume/mpc and volume/python-mpd previously shared
    # ~/.config/mpd/mpd-extended.cfg (note the old .cfg extension). Move
    # just that file, not the whole ~/.config/mpd/ directory, which also
    # holds MPD's own mpd.conf and must be left alone.
    local old_cfg="$HOME/.config/mpd/mpd-extended.cfg"
    local new_cfg="$NESTED_CONFIG_ROOT/volume/mpd-extended.conf"
    if [ -f "$old_cfg" ] && [ ! -e "$new_cfg" ]; then
        mkdir -p "$NESTED_CONFIG_ROOT/volume"
        mv "$old_cfg" "$new_cfg"
        echo "Migrated $old_cfg -> $new_cfg"
        migrated_any=true
    fi

    if [ "$migrated_any" = true ]; then
        echo "Existing settings migrated to the new unified ~/.config/mpd-scripts/ layout."
    fi
}

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

setup_path() {
    local found_dir=""
    for dir in "${CANDIDATE_DIRS[@]}"; do
        if [ -d "$dir" ] && on_path "$dir"; then
            found_dir="$dir"
            break
        fi
    done

    if [ -n "$found_dir" ]; then
        echo "Found $found_dir already on your PATH. Copy scripts there; no changes needed."
    else
        echo "No personal bin directory (${CANDIDATE_DIRS[*]}) was found on your PATH."
        read -r -p "Create ~/bin and add it to your PATH? [y/N] " REPLY

        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            add_dir_to_path "$HOME/bin"
        else
            echo "Skipped ~/bin. Add a directory to your PATH manually, then see README.md's Installation section."
        fi
    fi

    # ~/bin/music is a separate, optional directory some scripts in this
    # repo use for music-related data files -- handled independently of
    # the general-purpose CANDIDATE_DIRS check above.
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
}

migrate_config_dirs
setup_path
