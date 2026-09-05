#!/usr/bin/env bash

NOTES_DIR="${NOTES_DIR:-$HOME/Documents/notes}"

if [ ! -d "$NOTES_DIR" ]; then
    echo "Error: $NOTES_DIR not found."
    exit 1
fi

SELECTED=$(find "$NOTES_DIR" -type f -printf "%T@ %P\n" | \
    sort -rn | \
    cut -d' ' -f2- | \
    fzf --layout=reverse --header "Search (Year/Month/Day or Name)")

if [ -n "$SELECTED" ]; then
    vim "$NOTES_DIR/$SELECTED"
fi
