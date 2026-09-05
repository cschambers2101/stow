#!/usr/bin/env bash

NOTES_DIR="${NOTES_DIR:-$HOME/Documents/notes}"

INITIAL_QUERY="$1"

SELECTED=$(fzf --ansi --disabled \
    --layout=reverse \
    --header "VIM TAG SEARCH | Esc to cancel" \
    --query "$INITIAL_QUERY" \
    --bind "start:reload:rg -n -H --no-heading --color=always --smart-case '^tags:.*\[[^]]*${INITIAL_QUERY}[^]]*\]' '$NOTES_DIR' || true" \
    --bind "change:reload:rg -n -H --no-heading --color=always --smart-case '^tags:.*\[[^]]*{q}[^]]*\]' '$NOTES_DIR' || true" \
    --delimiter ":" \
    --preview "batcat --color=always --style=numbers --highlight-line {2} {1} 2>/dev/null || cat {1}")

FILE=$(echo "$SELECTED" | cut -d: -f1)
LINE=$(echo "$SELECTED" | cut -d: -f2)

if [ -n "$FILE" ]; then
    vim +"$LINE" "$FILE"
fi
