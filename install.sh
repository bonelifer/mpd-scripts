#!/usr/bin/bash

# One-time setup for this repo:
# 1. Migrates any existing per-script settings from the old
#    ~/.config/<script-name>/ layout into the new unified
#    ~/.config/mpd-scripts/<script-name>/ layout.
# 2. Checks whether a personal bin directory is already on PATH, and if
#    not, offers to create ~/bin and add it. Also checks/offers the same
#    for ~/bin/music, an optional separate directory for installing this
#    repo's scripts, kept apart from other personal scripts in ~/bin.
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

# Populated by migrate_config_dirs with one "old -> new" line per config
# actually migrated, so the full list can be recapped at the end of the
# script instead of only scrolling by as each one happens.
MIGRATED_ITEMS=()

# Moves each script's old ~/.config/<name>/ directory to its new home
# under $NESTED_CONFIG_ROOT, if the old one exists and hasn't already
# been migrated.
migrate_config_dirs() {
    for name in "${CONFIG_DIRS_TO_MIGRATE[@]}"; do
        local old_dir="$HOME/.config/$name"
        local new_dir="$NESTED_CONFIG_ROOT/$name"

        if [ -d "$old_dir" ] && [ ! -e "$new_dir" ]; then
            mkdir -p "$NESTED_CONFIG_ROOT"
            mv "$old_dir" "$new_dir"
            echo "Migrated $old_dir -> $new_dir"
            MIGRATED_ITEMS+=("$old_dir -> $new_dir")
        fi
    done

    # mv preserves whatever permissions a file already had, so scripts'
    # config files holding credentials (API keys, an MPD password) need
    # their permissions tightened explicitly after migrating -- being
    # freshly created via each script's own load_config() would have
    # already done this, but a moved pre-existing file might still be
    # world/group-readable from before that chmod existed.
    chmod 600 "$NESTED_CONFIG_ROOT/lastfm-love/lastfm-love.conf" 2>/dev/null || true
    chmod 600 "$NESTED_CONFIG_ROOT/lastfm-love/session_key" 2>/dev/null || true
    chmod 600 "$NESTED_CONFIG_ROOT/mpdsimilar/mpdsimilar.conf" 2>/dev/null || true
    chmod 600 "$NESTED_CONFIG_ROOT/mpd_rewind_daemon/mpd_rewind_daemon.conf" 2>/dev/null || true

    # volume/mpc and volume/python-mpd previously shared
    # ~/.config/mpd/mpd-extended.cfg (note the old name/.cfg extension).
    # Move just that file, not the whole ~/.config/mpd/ directory, which
    # also holds MPD's own mpd.conf and must be left alone.
    local old_cfg="$HOME/.config/mpd/mpd-extended.cfg"
    local new_cfg="$NESTED_CONFIG_ROOT/volume/volume.conf"
    if [ -f "$old_cfg" ] && [ ! -e "$new_cfg" ]; then
        mkdir -p "$NESTED_CONFIG_ROOT/volume"
        mv "$old_cfg" "$new_cfg"
        chmod 600 "$new_cfg"  # May contain an MPD password
        echo "Migrated $old_cfg -> $new_cfg"
        MIGRATED_ITEMS+=("$old_cfg -> $new_cfg")
    fi
}

# Recaps everything migrate_config_dirs moved, if anything. Printed at the
# very end of the script (after PATH setup too) so the full list is the
# last thing on screen instead of scrolling by earlier.
print_migration_summary() {
    if [ "${#MIGRATED_ITEMS[@]}" -eq 0 ]; then
        return
    fi

    echo
    echo "Migrated ${#MIGRATED_ITEMS[@]} existing config(s) to the new unified ~/.config/mpd-scripts/ layout:"
    for item in "${MIGRATED_ITEMS[@]}"; do
        echo "  - $item"
    done
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

    # ~/bin/music is a separate, optional directory for installing this
    # repo's scripts, kept apart from other personal scripts in ~/bin --
    # handled independently of the general-purpose CANDIDATE_DIRS check
    # above.
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
print_migration_summary
