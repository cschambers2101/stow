#!/usr/bin/env bash

NOTES_DIR="${NOTES_DIR:-$HOME/Documents/notes}"

if [ ! -d "$NOTES_DIR" ]; then
    echo "Error: $NOTES_DIR not found."
    exit 1
fi

SELECTED=$(find "$NOTES_DIR" -type f -printf "%T@ %P\n" | \
    sort -rn | \
    cut -d' ' -f2- | \
    fzf --layout=reverse --header "Select a note to DELETE")

if [ -n "$SELECTED" ]; then
    FULL_PATH="$NOTES_DIR/$SELECTED"

    echo -n "Are you sure you want to delete: $SELECTED? (y/N): "
    read -r CONFIRM

    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        rm "$FULL_PATH"
        echo "Successfully deleted: $SELECTED"
    else
        echo "Deletion cancelled."
    fi
fi
