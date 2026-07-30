#!/usr/bin/bash

# Checks whether a personal bin directory is already on PATH, and if not,
# offers to create ~/bin and add it. Run this once before following the
# Installation steps in README.md.

set -e  # Exit on error

# Common personal bin directories to check for, in order of preference.
CANDIDATE_DIRS=("$HOME/bin" "$HOME/.local/bin" "/usr/local/sbin" "/usr/local/bin")

FOUND_DIR=""
for dir in "${CANDIDATE_DIRS[@]}"; do
    if [ -d "$dir" ] && echo ":$PATH:" | grep -q ":$dir:"; then
        FOUND_DIR="$dir"
        break
    fi
done

if [ -n "$FOUND_DIR" ]; then
    echo "Found $FOUND_DIR already on your PATH. Copy scripts there; no changes needed."
    exit 0
fi

echo "No personal bin directory (${CANDIDATE_DIRS[*]}) was found on your PATH."
read -r -p "Create ~/bin and add it to your PATH? [y/N] " REPLY

if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Skipped. Add a directory to your PATH manually, then see README.md's Installation section."
    exit 0
fi

mkdir -p "$HOME/bin"

# Pick the shell's rc file so the PATH change survives new shells.
case "$(basename "${SHELL:-bash}")" in
    zsh)  RC_FILE="$HOME/.zshrc" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
    *)    RC_FILE="$HOME/.profile" ;;
esac

if ! grep -qs 'export PATH="\$HOME/bin:\$PATH"' "$RC_FILE" 2>/dev/null; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$RC_FILE"
    echo "Created ~/bin and added it to PATH in $RC_FILE."
else
    echo "Created ~/bin (PATH entry already present in $RC_FILE)."
fi

echo "Run 'source $RC_FILE' or open a new shell for the change to take effect."
