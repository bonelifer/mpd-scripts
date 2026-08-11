#!/usr/bin/bash

# One-time setup for this repo:
# 1. Migrates any existing per-script settings from the old
#    ~/.config/<script-name>/ layout into the new unified
#    ~/.config/mpd-scripts/<script-name>/ layout.
# 2. Checks whether a personal bin directory is already on PATH, and if
#    not, offers to create ~/bin and add it. Also checks/offers the same
#    for ~/bin/music, an optional separate directory for installing this
#    repo's scripts, kept apart from other personal scripts in ~/bin.
# 3. Offers to install any missing apt/pip/cpan dependencies used by the
#    scripts below.
# 4. Copies every standalone script (and the companion files it needs
#    alongside it, e.g. a .conf.example template or a stations list) into
#    the directory chosen in step 2, and installs MPD Notifier via its own
#    installer.
# 5. Offers to install the optional MPD Rewind Daemon, mpd-smart-shuffle,
#    alarmpd, mpd-auto-stop, and volume control scripts, each delegating to
#    its own installer.
#
# Run this once; no manual copying into your PATH is needed afterwards.

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NESTED_CONFIG_ROOT="$HOME/.config/mpd-scripts"

# Set by setup_path() to wherever copy_simple_scripts() should install to.
INSTALL_BIN_DIR=""

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
        if [ -d "$dir" ] && [ -w "$dir" ] && on_path "$dir"; then
            found_dir="$dir"
            break
        fi
    done

    if [ -n "$found_dir" ]; then
        echo "Found $found_dir already on your PATH."
        INSTALL_BIN_DIR="$found_dir"
    else
        echo "No personal bin directory (${CANDIDATE_DIRS[*]}) was found on your PATH."
        read -r -p "Create ~/bin and add it to your PATH? [y/N] " REPLY

        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            add_dir_to_path "$HOME/bin"
            INSTALL_BIN_DIR="$HOME/bin"
        else
            echo "Skipped ~/bin. Add a directory to your PATH manually, then re-run install.sh to install the scripts there."
        fi
    fi

    # ~/bin/music is a separate, optional directory for installing this
    # repo's scripts, kept apart from other personal scripts in ~/bin --
    # handled independently of the general-purpose CANDIDATE_DIRS check
    # above. If created, it takes over from $INSTALL_BIN_DIR as the place
    # this script's scripts get copied to.
    if [ -d "$HOME/bin/music" ] && on_path "$HOME/bin/music"; then
        echo "Found $HOME/bin/music already on your PATH."
        INSTALL_BIN_DIR="$HOME/bin/music"
    else
        read -r -p "Create ~/bin/music and add it to your PATH too, and install this repo's scripts there instead? [y/N] " REPLY

        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            add_dir_to_path "$HOME/bin/music"
            INSTALL_BIN_DIR="$HOME/bin/music"
        else
            echo "Skipped ~/bin/music."
        fi
    fi

    echo "Run 'source $RC_FILE' or open a new shell for any changes to take effect."
}

# apt packages required by at least one script below (optional extras like
# ripgrep/parallel/ffmpeg/imagemagick/dunst/pulseaudio-utils are left to each
# script's own first-run prompt, since they're feature-gated rather than
# always needed).
APT_PACKAGES=(
    bc
    mpc
    curl
    jq
    python3-pyqt5
    python3-gi
    gir1.2-gtk-3.0
    gir1.2-ayatanaappindicator3-0.1
    libnotify-bin
    cpanminus
)

# "pip-package-name:python-import-name" pairs, since they differ for
# python-mpd2 (imported as "mpd").
PIP_PACKAGES=(
    "pylast:pylast"
    "python-mpd2:mpd"
)

CPAN_MODULES=(
    "StreamFinder::IHeartRadio"
    "StreamFinder::Tunein"
    "LWP::Simple"
)

# Installs whichever of APT_PACKAGES/PIP_PACKAGES/CPAN_MODULES aren't
# already present, after a single confirmation. A failed install of one
# package (e.g. a distro using a different apt package name) doesn't stop
# the rest -- each is attempted independently.
install_dependencies() {
    local missing_apt=() missing_pip=() missing_cpan=()

    for pkg in "${APT_PACKAGES[@]}"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing_apt+=("$pkg")
    done

    for entry in "${PIP_PACKAGES[@]}"; do
        local import_name="${entry##*:}"
        python3 -c "import $import_name" >/dev/null 2>&1 || missing_pip+=("${entry%%:*}")
    done

    for mod in "${CPAN_MODULES[@]}"; do
        perl -M"$mod" -e 1 >/dev/null 2>&1 || missing_cpan+=("$mod")
    done

    if [ "${#missing_apt[@]}" -eq 0 ] && [ "${#missing_pip[@]}" -eq 0 ] && [ "${#missing_cpan[@]}" -eq 0 ]; then
        echo "All script dependencies are already installed."
        return
    fi

    echo
    echo "Some scripts in this repo need dependencies that aren't installed yet:"
    [ "${#missing_apt[@]}" -gt 0 ] && echo "  apt:  ${missing_apt[*]}"
    [ "${#missing_pip[@]}" -gt 0 ] && echo "  pip:  ${missing_pip[*]}"
    [ "${#missing_cpan[@]}" -gt 0 ] && echo "  cpan: ${missing_cpan[*]}"
    read -r -p "Install missing dependencies now (apt needs sudo)? [Y/n] " REPLY

    if [[ "$REPLY" =~ ^[Nn]$ ]]; then
        echo "Skipped. Install manually later, or re-run install.sh."
        return
    fi

    if [ "${#missing_apt[@]}" -gt 0 ]; then
        sudo apt-get update
        for pkg in "${missing_apt[@]}"; do
            sudo apt-get install -y "$pkg" || echo "Warning: failed to install apt package '$pkg' (the package name may differ on your distro)." >&2
        done
    fi

    if [ "${#missing_pip[@]}" -gt 0 ]; then
        pip3 install --user "${missing_pip[@]}" || echo "Warning: pip3 install failed for one or more packages." >&2
    fi

    if [ "${#missing_cpan[@]}" -gt 0 ]; then
        if command -v cpanm >/dev/null 2>&1; then
            for mod in "${missing_cpan[@]}"; do
                sudo cpanm "$mod" || echo "Warning: failed to install Perl module '$mod'." >&2
            done
        else
            echo "Warning: cpanm not found; install cpanminus first, then: cpanm ${missing_cpan[*]}" >&2
        fi
    fi
}

# Scripts with no installer of their own: "dir|executable file(s)|companion
# file(s)". Companions travel alongside their script because each one
# resolves its own directory at runtime (dirname "$0" / FindBin::RealBin /
# __file__) to find its .conf.example template, station list, or shared
# module -- so they'd fail on first run if left behind. Directories that
# ship their own install.sh (mpd-notifier, mpd_rewind_daemon, volume/mpc,
# volume/python-mpd) are handled separately below instead.
SIMPLE_SCRIPTS=(
    "add-current-song|add-current-song.sh|add-current-song.conf.example"
    "iheart-radio|iheart.pl|iheart-stations.txt"
    "tunein-radio|tunein.pl|tunein-radio-stations.txt"
    "lastfm-love|loved.py unloved.py|lastfm_common.py lastfm-love.conf.example"
    "mpc-fade|mpc-fade.sh|mpc-fade.conf.example"
    "mpd-add-random|mpd-add-random.sh|mpd-add-random.conf.example"
    "mpd-add-random-artist|mpd-add-random-artist.sh|"
    "mpd-find-dup|mpd-remove-duplicates-queue.sh mpd-deduplicate-save-and-reload.sh|mpd-deduplicate-save-and-reload.conf.example"
    "mpd-queue-shuffle|mpd-queue-shuffle.sh|mpd-queue-shuffle.conf.example"
    "mpd-radio-tray|mpd-radio-tray.py|mpd-radio-tray.conf.example stations.txt.example"
    "mpd-random-album|mpd-random-album.sh|mpd-random-album.conf.example"
    "mpd-recent-tracks|mpd-recent-tracks.sh|mpd-recent-tracks.conf.example exclude_paths.txt.example"
    "mpdsimilar|mpdsimilar.sh|mpdsimilar.conf.example"
    "mpd-tray-icon|mpd-tray-icon.py|"
    "mpd-kb-control|mpd-kb-control.py|mpd-kb-control.conf.example"
    "mpdmark|mpdmark.py|mpdmark.conf.example"
    "music_queue_manager|music_queue_manager.sh|music_queue_manager.conf.example"
    "playpause|playpause.sh|playpause.conf.example"
    "rm-artists-playlist|rm-artists-playlist.sh|rm-artists-playlist.conf.example"
    "rm-duplicates-playlist|rm-duplicates-playlist.sh|rm-duplicates-playlist.conf.example"
    "somafm|soma_fm_playlist_fetcher.py|"
)

# Copies every script in SIMPLE_SCRIPTS (and its companion files) into
# INSTALL_BIN_DIR, marking the executables +x. This is what makes
# "no manual steps" true -- previously the README asked you to cp each
# script there by hand.
copy_simple_scripts() {
    if [ -z "$INSTALL_BIN_DIR" ]; then
        echo
        echo "No install directory was chosen above; skipping script installation. Re-run install.sh once you have one on your PATH."
        return
    fi

    echo
    echo "Installing standalone scripts to $INSTALL_BIN_DIR..."
    mkdir -p "$INSTALL_BIN_DIR"

    local count=0
    for entry in "${SIMPLE_SCRIPTS[@]}"; do
        IFS='|' read -r dir execs companions <<< "$entry"

        for f in $execs; do
            cp "$SCRIPT_DIR/$dir/$f" "$INSTALL_BIN_DIR/"
            chmod +x "$INSTALL_BIN_DIR/$f"
            count=$((count + 1))
        done

        for f in $companions; do
            cp "$SCRIPT_DIR/$dir/$f" "$INSTALL_BIN_DIR/"
        done
    done

    echo "Installed $count scripts. Check each script's own README for language-specific usage notes."
}

# Offers to install the optional MPD Rewind Daemon (not everyone using this
# repo wants a background daemon running), delegating to its own installer
# chooser if you say yes. A failure there doesn't abort the rest of this
# script -- migration and PATH setup have already succeeded by this point,
# and the daemon can always be installed later via mpd_rewind_daemon/install.sh.
offer_mpd_rewind_daemon() {
    local daemon_installer="$SCRIPT_DIR/mpd_rewind_daemon/install.sh"

    if [ ! -x "$daemon_installer" ]; then
        return
    fi

    echo
    read -r -p "Also install the optional MPD Rewind Daemon (auto-rewinds after resuming from pause)? [y/N] " REPLY

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        "$daemon_installer" || echo "mpd_rewind_daemon installation did not complete successfully; you can retry with mpd_rewind_daemon/install.sh." >&2
    else
        echo "Skipped. Run mpd_rewind_daemon/install.sh later if you change your mind."
    fi
}

# Offers to install the optional mpd-smart-shuffle tool (background play
# monitor + smarter random-queue-fill script), delegating to its own
# installer if you say yes, for the same reason as offer_mpd_rewind_daemon
# above -- it's multi-file and has its own optional systemd --user service
# to offer, both better handled by its own install.sh than the generic
# SIMPLE_SCRIPTS mechanism.
offer_mpd_smart_shuffle() {
    local smart_shuffle_installer="$SCRIPT_DIR/mpd-smart-shuffle/install.sh"

    if [ ! -x "$smart_shuffle_installer" ]; then
        return
    fi

    echo
    read -r -p "Also install the optional mpd-smart-shuffle tool (smarter random queue-fill with play history)? [y/N] " REPLY

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        "$smart_shuffle_installer" || echo "mpd-smart-shuffle installation did not complete successfully; you can retry with mpd-smart-shuffle/install.sh." >&2
    else
        echo "Skipped. Run mpd-smart-shuffle/install.sh later if you change your mind."
    fi
}

# Offers to install the optional alarmpd tool (playlist-named alarm clock
# daemon), delegating to its own installer chooser if you say yes, for the
# same reason as offer_mpd_rewind_daemon above -- it's multi-file and has
# its own optional systemd --user service to offer.
offer_alarmpd() {
    local alarmpd_installer="$SCRIPT_DIR/alarmpd/install.sh"

    if [ ! -x "$alarmpd_installer" ]; then
        return
    fi

    echo
    read -r -p "Also install the optional alarmpd tool (playlist-named alarm clock)? [y/N] " REPLY

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        "$alarmpd_installer" || echo "alarmpd installation did not complete successfully; you can retry with alarmpd/install.sh." >&2
    else
        echo "Skipped. Run alarmpd/install.sh later if you change your mind."
    fi
}

# Offers to install the optional mpd-auto-stop tool (sleep-timer daemon
# with a web UI), delegating to its own installer chooser if you say yes,
# for the same reason as offer_mpd_rewind_daemon above -- it's multi-file
# and has its own optional systemd --user service to offer.
offer_mpd_auto_stop() {
    local auto_stop_installer="$SCRIPT_DIR/mpd-auto-stop/install.sh"

    if [ ! -x "$auto_stop_installer" ]; then
        return
    fi

    echo
    read -r -p "Also install the optional mpd-auto-stop tool (sleep-timer web UI, fades out and pauses MPD)? [y/N] " REPLY

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        "$auto_stop_installer" || echo "mpd-auto-stop installation did not complete successfully; you can retry with mpd-auto-stop/install.sh." >&2
    else
        echo "Skipped. Run mpd-auto-stop/install.sh later if you change your mind."
    fi
}

# Installs MPD Notifier (desktop notification on track change) by
# delegating to its own installer, unconditionally -- unlike the rewind
# daemon or volume scripts below, there's no conflicting choice to make
# here, so it's installed the same way as everything in SIMPLE_SCRIPTS.
# Its install.sh uses paths relative to its own directory, so it's run
# from there rather than invoked directly.
install_mpd_notifier() {
    local notifier_installer="$SCRIPT_DIR/mpd-notifier/install.sh"

    if [ ! -x "$notifier_installer" ]; then
        return
    fi

    echo
    ( cd "$SCRIPT_DIR/mpd-notifier" && ./install.sh ) || echo "mpd-notifier installation did not complete successfully; you can retry with mpd-notifier/install.sh." >&2
}

# Offers to install the optional volume control scripts (mpdvolup.py /
# mpdvoldown.py / volume.py). They come in two variants that both install
# under the same three filenames, so exactly one -- not both -- can be
# installed; this asks which, with the reasoning for each, then delegates
# to that variant's own install.sh (run from its own directory, since it
# uses paths relative to itself).
offer_volume_scripts() {
    local mpc_installer="$SCRIPT_DIR/volume/mpc/install.sh"
    local pymp_installer="$SCRIPT_DIR/volume/python-mpd/install.sh"

    if [ ! -x "$mpc_installer" ] && [ ! -x "$pymp_installer" ]; then
        return
    fi

    echo
    cat <<'EOF'
Also install the optional volume control scripts (mpdvolup.py, mpdvoldown.py,
volume.py)? They come in two variants -- install only ONE, since both use the
same three filenames:

  A) mpc-based       Shells out to the mpc command-line tool for every call.
                      Simpler and needs no Python library, matching most other
                      scripts in this repo that already talk to MPD via mpc.

  B) python-mpd2-based  Talks to MPD directly over its protocol via the
                      python-mpd2 library instead of spawning mpc each time.
                      Effectively "free" to add if you're also installing
                      mpd_rewind_daemon or mpd-radio-tray, since both already
                      depend on python-mpd2.
EOF
    read -r -p "Install [A]mpc, [B]python-mpd2, or [N]either? [a/b/N] " REPLY

    case "$REPLY" in
        [Aa]*)
            ( cd "$SCRIPT_DIR/volume/mpc" && ./install.sh ) || echo "volume (mpc) installation did not complete successfully; you can retry with volume/mpc/install.sh." >&2
            ;;
        [Bb]*)
            ( cd "$SCRIPT_DIR/volume/python-mpd" && ./install.sh ) || echo "volume (python-mpd2) installation did not complete successfully; you can retry with volume/python-mpd/install.sh." >&2
            ;;
        *)
            echo "Skipped. Run volume/mpc/install.sh or volume/python-mpd/install.sh later if you change your mind."
            ;;
    esac
}

migrate_config_dirs
setup_path
install_dependencies
copy_simple_scripts
install_mpd_notifier
offer_mpd_rewind_daemon
offer_mpd_smart_shuffle
offer_alarmpd
offer_mpd_auto_stop
offer_volume_scripts
print_migration_summary
