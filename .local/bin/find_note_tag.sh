#!/bin/bash

NOTES_DIR="$HOME/Documents/notes"

# 1. Capture the initial query if provided
INITIAL_QUERY="$1"

# 2. THE SEARCH
# {q} represents what you type live
# $INITIAL_QUERY ensures that if you run 'ft ukrcca', it starts with that search
SELECTED=$(fzf --ansi --disabled \
    --layout=reverse \
    --header "VIM TAG SEARCH | Esc to cancel" \
    --query "$INITIAL_QUERY" \
    --bind "start:reload:rg -n -H --no-heading --color=always --smart-case '^tags:.*\[[^]]*$INITIAL_QUERY[^]]*\]' '$NOTES_DIR' || true" \
    --bind "change:reload:rg -n -H --no-heading --color=always --smart-case '^tags:.*\[[^]]*{q}[^]]*\]' '$NOTES_DIR' || true" \
    --delimiter ":" \
    --preview "batcat --color=always --style=numbers --highlight-line {2} {1} 2>/dev/null || cat {1}")

# 3. EXTRACTION
FILE=$(echo "$SELECTED" | cut -d: -f1)
LINE=$(echo "$SELECTED" | cut -d: -f2)

# 4. VIM OPEN
if [ -n "$FILE" ]; then
    vim +"$LINE" "$FILE"
fi
