#!/usr/bin/bash

#
# mpd-usb-automount installer
#
# Sets up a removable USB disk as MPD's music library: a stable /dev
# name via udev (survives reboots/enumeration-order changes), on-demand
# mounting via autofs (the disk isn't spun up until something actually
# reads from it), and an idle spindown timer.
#
# This installer is deliberately NOT wired into mpd-scripts' top-level
# install.sh. It needs root, it writes to /etc (udev rules, autofs
# config) rather than your home directory, and it needs your specific
# disk's hardware IDs -- this should be a conscious, one-time, manual
# step, not something a general "install everything" run does for you.
#
# See README.md before running this.
#
# Usage:
#   sudo ./install.sh --detect /dev/sdX1
#   sudo ./install.sh --vendor ID_VENDOR --product ID_PRODUCT --serial ID_SERIAL
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UDEV_RULE_DEST=/etc/udev/rules.d/10-mpd-disk.rules
AUTOFS_DROPIN_DEST=/etc/auto.master.d/mpd-disk.autofs
AUTOFS_MAP_DEST=/etc/auto.mpd-disk
HDPARM_SCRIPT_DEST=/usr/local/sbin/hdparm-mpd-disk.sh
MPD_CONF=/etc/mpd.conf

ID_VENDOR=""
ID_PRODUCT=""
ID_SERIAL=""
DETECT_DEVICE=""

usage() {
    cat <<'EOF'
Usage:
  sudo ./install.sh --detect /dev/sdX1
  sudo ./install.sh --vendor ID_VENDOR --product ID_PRODUCT --serial ID_SERIAL

Options:
  --detect DEVICE      Auto-detect idVendor/idProduct/serial from an
                        already-plugged-in device (e.g. /dev/sda1) via
                        udevadm, instead of specifying them manually.
  --vendor ID_VENDOR    Set idVendor directly.
  --product ID_PRODUCT  Set idProduct directly.
  --serial ID_SERIAL    Set serial directly.
  -h, --help            Show this help.

Either --detect DEVICE, or all three of --vendor/--product/--serial, are
required.
EOF
}

#
# Fills ID_VENDOR/ID_PRODUCT/ID_SERIAL from udevadm's already-resolved
# properties for $1, instead of requiring you to manually walk
# `udevadm info -a -p ...` parent-device output looking for a unique
# combination.
#
detect_device_ids() {
    local device="$1"
    local props

    if ! command -v udevadm >/dev/null 2>&1; then
        echo "Error: udevadm not found." >&2
        exit 1
    fi

    if [[ ! -e "$device" ]]; then
        echo "Error: $device does not exist. Plug in the disk first." >&2
        exit 1
    fi

    if ! props="$(udevadm info --query=property --name="$device" 2>/dev/null)"; then
        echo "Error: udevadm could not query $device." >&2
        exit 1
    fi

    ID_VENDOR="$(grep -m1 '^ID_VENDOR_ID=' <<< "$props" | cut -d= -f2-)"
    ID_PRODUCT="$(grep -m1 '^ID_MODEL_ID=' <<< "$props" | cut -d= -f2-)"
    ID_SERIAL="$(grep -m1 '^ID_SERIAL_SHORT=' <<< "$props" | cut -d= -f2-)"

    if [[ -z "$ID_VENDOR" || -z "$ID_PRODUCT" || -z "$ID_SERIAL" ]]; then
        echo "Error: could not determine idVendor/idProduct/serial for $device." >&2
        echo "Raw udevadm properties for reference:" >&2
        echo "$props" >&2
        echo "You may need to set --vendor/--product/--serial manually instead." >&2
        exit 1
    fi

    echo "Detected: idVendor=$ID_VENDOR idProduct=$ID_PRODUCT serial=$ID_SERIAL"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --detect)
            DETECT_DEVICE="${2:?--detect requires a device path}"
            shift 2
            ;;
        --vendor)
            ID_VENDOR="${2:?--vendor requires a value}"
            shift 2
            ;;
        --product)
            ID_PRODUCT="${2:?--product requires a value}"
            shift 2
            ;;
        --serial)
            ID_SERIAL="${2:?--serial requires a value}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -n "$DETECT_DEVICE" ]]; then
    detect_device_ids "$DETECT_DEVICE"
fi

if [[ -z "$ID_VENDOR" || -z "$ID_PRODUCT" || -z "$ID_SERIAL" ]]; then
    echo "Error: idVendor/idProduct/serial not set." >&2
    usage >&2
    exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: this installer must be run as root (it writes to /etc and /usr/local/sbin)." >&2
    echo "Try: sudo $0 [options]" >&2
    exit 1
fi

echo "Installing udev rule to $UDEV_RULE_DEST..."
sed \
    -e "s/__ID_VENDOR__/$ID_VENDOR/" \
    -e "s/__ID_PRODUCT__/$ID_PRODUCT/" \
    -e "s/__ID_SERIAL__/$ID_SERIAL/" \
    "$SCRIPT_DIR/10-mpd-disk.rules.example" > "$UDEV_RULE_DEST"
chmod 644 "$UDEV_RULE_DEST"

echo "Installing hdparm script to $HDPARM_SCRIPT_DEST..."
cp "$SCRIPT_DIR/hdparm-mpd-disk.sh" "$HDPARM_SCRIPT_DEST"
chmod 755 "$HDPARM_SCRIPT_DEST"

echo "Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger

if ! dpkg -s autofs >/dev/null 2>&1; then
    echo "autofs does not appear to be installed."
    read -r -p "Install it now via apt? [Y/n] " REPLY
    if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
        apt-get update
        apt-get install -y autofs
    else
        echo "Skipped. Install it manually before continuing: sudo apt-get install autofs"
    fi
fi

echo "Installing autofs map to $AUTOFS_MAP_DEST..."
cp "$SCRIPT_DIR/auto.mpd-disk" "$AUTOFS_MAP_DEST"
chmod 644 "$AUTOFS_MAP_DEST"

echo "Installing autofs drop-in to $AUTOFS_DROPIN_DEST..."
mkdir -p /etc/auto.master.d
cp "$SCRIPT_DIR/mpd-disk.autofs" "$AUTOFS_DROPIN_DEST"
chmod 644 "$AUTOFS_DROPIN_DEST"

if command -v systemctl >/dev/null 2>&1; then
    echo "Restarting autofs..."
    systemctl restart autofs
    systemctl enable autofs >/dev/null 2>&1 || true
else
    echo "systemctl not found; restart the autofs service manually, e.g.: service autofs restart"
fi

echo
echo "Checking $MPD_CONF for the required directives..."
if [[ -f "$MPD_CONF" ]]; then
    missing=()
    grep -Eq '^[[:space:]]*follow_outside_symlinks[[:space:]]+"yes"' "$MPD_CONF" ||
        missing+=('follow_outside_symlinks "yes"')
    grep -Eq '^[[:space:]]*follow_inside_symlinks[[:space:]]+"yes"' "$MPD_CONF" ||
        missing+=('follow_inside_symlinks "yes"')

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "The following directives are missing from $MPD_CONF and must be added manually:"
        for line in "${missing[@]}"; do
            echo "  $line"
        done
        echo "See mpd.conf.snippet in this directory for the full reference."
    else
        echo "Required mpd.conf directives are already present."
    fi
else
    echo "Warning: $MPD_CONF not found; add the directives from mpd.conf.snippet once MPD is installed."
fi

echo
echo "Installation complete. Remaining manual steps:"
echo "  1. Plug in the disk (if not already) and confirm it appears at /dev/mpd-disk:"
echo "       ls -l /dev/mpd-disk"
echo "  2. Symlink MPD's music_directory to the disk's actual music folder, e.g.:"
echo "       cd /var/lib/mpd/music && sudo ln -s /media/mpd-auto/mpd-disk/Music Music"
echo "     (adjust \"Music\" to match your disk's actual top-level folder name)"
echo "  3. Restart MPD and run an initial database update:"
echo "       sudo systemctl restart mpd"
echo "       mpc update"
