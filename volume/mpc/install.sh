!#/usr/bin/bash

check_and_copy_mpd_extended_cfg() {
    MPD_EXTENDED_CFG_PATH=~/.config/mpd/mpd-extended.cfg
    MPD_CONFIG_DIR=$(dirname "$MPD_EXTENDED_CFG_PATH")

    if [ ! -f "$MPD_EXTENDED_CFG_PATH" ]; then
        echo "Creating directory $MPD_CONFIG_DIR"
        mkdir -p "$MPD_CONFIG_DIR"
        echo "Copying mpd-extended.cfg to $MPD_EXTENDED_CFG_PATH"
        cp ./mpd-extended.cfg "$MPD_EXTENDED_CFG_PATH"
    else
        echo "mpd-extended.cfg already exists at $MPD_EXTENDED_CFG_PATH"
    fi
}

add_mpd_script_section_if_cfg_exists() {
    MPD_EXTENDED_CFG_PATH=~/.config/mpd/mpd-extended.cfg

    if [ -f "$MPD_EXTENDED_CFG_PATH" ]; then
        PYTHON3_PATH=$(which python3)
        if [ -x "$PYTHON3_PATH" ]; then
            $PYTHON3_PATH ./functions/update-mpd-extended-cfg.py
            $PYTHON3_PATH ./functions/add-mpd-script-section.py
        else
            echo "Error: python3 executable not found."
        fi
    else
        echo "Error: mpd-extended.cfg not found at $MPD_EXTENDED_CFG_PATH"
    fi
}

prompt_mpd_extended_user_group() {
    read -t 10 -p "Set user and group to 'root' (y/n)? " mpd_extended_choice
    if [ "$mpd_extended_choice" = "y" ]; then
        mpd_extended_user="root"
        mpd_extended_group="root"
    else
        mpd_extended_user="$USER"
        mpd_extended_group="$USER"
    fi
}

# Define install directory variable
installdir="/usr/local/sbin"

prompt_mpd_extended_user_group
check_and_copy_mpd_extended_cfg
add_mpd_script_section_if_cfg_exists

cp ./mpdvoldown.py ./mpdvolup.py ./volume.py "$installdir"
chown "$mpd_extended_user:$mpd_extended_group" "$installdir/mpdvoldown.py" "$installdir/mpdvolup.py" "$installdir/volume.py"
chmod +x "$installdir/mpdvoldown.py" "$installdir/mpdvolup.py" "$installdir/volume.py"


