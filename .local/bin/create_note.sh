#!/bin/bash

# 1. Configuration - Change these as needed
BASE_DIR="$HOME/Documents/notes"
EDITOR_CMD="vim" # Or "code", "nano", "open"

# 2. Generate Date/Time variables
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
TIME=$(date +%H%M%S)
FULL_DATE=$(date +%Y-%m-%d)

# 3. Build Path and Filename
TARGET_DIR="$BASE_DIR/$YEAR/$MONTH/$DAY"
FILENAME="$FULL_DATE-$TIME.md"
FILE_PATH="$TARGET_DIR/$FILENAME"

# 4. Create directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# 5. Handle Tags (Passed as arguments)
# This converts: script tag1 tag2 to [tag1, tag2]
TAGS_INPUT=$@
FORMATTED_TAGS=$(echo "$TAGS_INPUT" | sed 's/ /, /g')

# 6. Create the file with YAML Frontmatter
cat <<EOF > "$FILE_PATH"
---
title: Note for $FULL_DATE $TIME
date: $(date +'%Y-%m-%d %H:%M')
tags: [$FORMATTED_TAGS]
---

# New Note
EOF

# 7. Success message and open the file
echo "Created: $FILE_PATH"
$EDITOR_CMD "$FILE_PATH"
