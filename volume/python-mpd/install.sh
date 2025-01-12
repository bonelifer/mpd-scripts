#!/usr/bin/bash

# ==============================================================================
# Script to manage MPD (Music Player Daemon) configuration and installation:
# - Prompts user to set installation user/group to 'root' or the current user.
# - Ensures mpd-extended.cfg exists, copying it if necessary.
# - Runs Python scripts to update the configuration and add MPD script sections.
# - Installs Python dependencies from requirements.txt.
# - Copies necessary Python scripts to the installation directory and sets proper permissions.
#
# ==============================================================================

# Function to check if the mpd-extended.cfg file exists; if not, it creates the directory and copies the file
check_and_copy_mpd_extended_cfg() {
    # Define path for the mpd-extended.cfg file
    MPD_EXTENDED_CFG_PATH=~/.config/mpd/mpd-extended.cfg
    # Get the directory of the configuration file
    MPD_CONFIG_DIR=$(dirname "$MPD_EXTENDED_CFG_PATH")

    # Check if the configuration file exists
    if [ ! -f "$MPD_EXTENDED_CFG_PATH" ]; then
        echo "Creating directory $MPD_CONFIG_DIR"
        mkdir -p "$MPD_CONFIG_DIR"  # Create the directory if it does not exist
        echo "Copying mpd-extended.cfg to $MPD_EXTENDED_CFG_PATH"
        cp ./mpd-extended.cfg "$MPD_EXTENDED_CFG_PATH"  # Copy the file to the target path
    else
        echo "mpd-extended.cfg already exists at $MPD_EXTENDED_CFG_PATH"
    fi
}

# Function to add MPD script section if the configuration file exists
add_mpd_script_section_if_cfg_exists() {
    # Define path for the mpd-extended.cfg file
    MPD_EXTENDED_CFG_PATH=~/.config/mpd/mpd-extended.cfg

    # Check if the configuration file exists
    if [ -f "$MPD_EXTENDED_CFG_PATH" ]; then
        # Get the path for python3 executable
        PYTHON3_PATH=$(which python3)
        if [ -x "$PYTHON3_PATH" ]; then
            # Run the Python scripts to update the configuration and add script section
            $PYTHON3_PATH ./functions/update-mpd-extended-cfg.py
            $PYTHON3_PATH ./functions/add-mpd-script-section.py
        else
            echo "Error: python3 executable not found."
        fi
    else
        echo "Error: mpd-extended.cfg not found at $MPD_EXTENDED_CFG_PATH"
    fi
}

# Function to prompt user to set user and group for installation
prompt_mpd_extended_user_group() {
    # Ask user whether to set 'root' as the user/group or current user
    read -t 10 -p "Set user and group to 'root' (y/n)? " mpd_extended_choice
    if [ "$mpd_extended_choice" = "y" ]; then
        installdir="/usr/local/sbin"  # Installation directory for 'root' choice
        mpd_extended_user="root"      # User set to root
        mpd_extended_group="root"     # Group set to root
    else
        installdir="$HOME/bin"        # Installation directory for user choice
        mpd_extended_user="$USER"     # Use current user for the installation
        mpd_extended_group="$USER"    # Use current group for the installation
        # Create a 'bin' directory in the user's home directory if it doesn't exist
        mkdir -p "$installdir"
        # Add 'bin' directory to PATH if not already present
        if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
            echo 'export PATH="$PATH:$HOME/bin"' >> ~/.bashrc  # Modify .bashrc to include bin in PATH
        fi
        # Apply changes to the current session
        source ~/.bashrc
        echo "Setup complete. 'bin' directory added to PATH."
    fi
}

# Function to install Python requirements from requirements.txt
install_python_requirements() {
    # Get the path to pip3 executable
    PIP3_PATH=$(which pip3)
    # Install required Python packages from the requirements file
    $PIP3_PATH install -r requirements.txt
}

# Call the functions in sequence
prompt_mpd_extended_user_group     # Prompt for user and group configuration
check_and_copy_mpd_extended_cfg    # Ensure the mpd-extended.cfg file is in place
add_mpd_script_section_if_cfg_exists  # Add script section to configuration if exists
install_python_requirements        # Install the required Python dependencies

# Display the installation directory to confirm path for subsequent steps
echo "Install directory: $installdir"

# Copy the Python scripts to the installation directory
cp ./mpdvoldown.py ./mpdvolup.py ./volume.py "$installdir"
# Change ownership to the selected user and group
chown "$mpd_extended_user:$mpd_extended_group" "$installdir/mpdvoldown.py" "$installdir/mpdvolup.py" "$installdir/volume.py"
# Make the Python scripts executable
chmod +x "$installdir/mpdvoldown.py" "$installdir/mpdvolup.py" "$installdir/volume.py"

