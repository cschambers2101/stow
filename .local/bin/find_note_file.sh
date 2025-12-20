#!/bin/bash

# 1. Update this to your ACTUAL base notes folder
NOTES_DIR="$HOME/Documents/notes"

if [ ! -d "$NOTES_DIR" ]; then
    echo "Error: $NOTES_DIR not found."
    exit 1
fi

# 2. THE SEARCH
# -type f: find files only
# -printf: get the path relative to NOTES_DIR and the mod time
# fzf: searches the paths (so '12' will match the '/12/' folder)
SELECTED=$(find "$NOTES_DIR" -type f -printf "%T@ %P\n" | \
    sort -rn | \
    cut -d' ' -f2- | \
    fzf --layout=reverse --header "Search (Year/Month/Day or Name)")

# 3. OPEN THE FILE
if [ -n "$SELECTED" ]; then
    # Open using the full absolute path
    vim "$NOTES_DIR/$SELECTED"
fi
