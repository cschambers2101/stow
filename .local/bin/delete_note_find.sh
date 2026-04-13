#!/bin/bash

# 1. Base notes folder
NOTES_DIR="$HOME/Documents/notes"

if [ ! -d "$NOTES_DIR" ]; then
    echo "Error: $NOTES_DIR not found."
    exit 1
fi

# 2. THE SEARCH
# We keep your logic: find files, sort by time, and pipe to fzf
SELECTED=$(find "$NOTES_DIR" -type f -printf "%T@ %P\n" | \
    sort -rn | \
    cut -d' ' -f2- | \
    fzf --layout=reverse --header "Select a note to DELETE")

# 3. THE SAFETY & DELETION
if [ -n "$SELECTED" ]; then
    FULL_PATH="$NOTES_DIR/$SELECTED"

    # Ask for confirmation
    # -p: prompt string
    # -n 1: accept a single character
    # -r: do not allow backslashes to escape characters
    echo -n "Are you sure you want to delete: $SELECTED? (y/N): "
    read -r CONFIRM

    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        rm "$FULL_PATH"
        echo "Successfully deleted: $SELECTED"
    else
        echo "Deletion cancelled."
    fi
fi
