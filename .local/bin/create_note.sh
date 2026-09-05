#!/usr/bin/env bash

BASE_DIR="${NOTES_DIR:-$HOME/Documents/notes}"
SUBJECTS_DIR="$BASE_DIR/Subjects"
EDITOR_CMD="vim"

YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
TIME=$(date +%H%M%S)
FULL_DATE=$(date +%Y-%m-%d)

TARGET_DIR="$BASE_DIR/$YEAR/$MONTH/$DAY"
FILENAME="$FULL_DATE-$TIME.md"
FILE_PATH="$TARGET_DIR/$FILENAME"

mkdir -p "$TARGET_DIR"
mkdir -p "$SUBJECTS_DIR"

TAGS_INPUT="$*"
FORMATTED_TAGS=$(echo "$TAGS_INPUT" | sed 's/ /, /g')

cat <<EOM > "$FILE_PATH"
---
title: Note for $FULL_DATE $TIME
date: $(date +'%Y-%m-%d %H:%M')
tags: [$FORMATTED_TAGS]
---

# New Note
EOM

INDEX_FILE="$BASE_DIR/00_Master_Index.md"
REL_PATH="${FILE_PATH#$BASE_DIR/}"
HEADING="### $YEAR-$MONTH"

if ! grep -q "^$HEADING" "$INDEX_FILE"; then
    echo -e "\n$HEADING" >> "$INDEX_FILE"
fi

echo "- [[$REL_PATH|Note for $FULL_DATE $TIME]] ($FULL_DATE)" >> "$INDEX_FILE"

echo "Created: $FILE_PATH"
$EDITOR_CMD "$FILE_PATH"

FINAL_TITLE=$(grep "^# " "$FILE_PATH" | head -n 1 | sed 's/^# //' | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')

if [[ "$FINAL_TITLE" == "New Note" ]] || [[ -z "$FINAL_TITLE" ]]; then
    FINAL_TITLE=$(grep "^title: " "$FILE_PATH" | head -n 1 | sed 's/^title: //' | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')
fi

if [ ! -z "$FINAL_TITLE" ]; then
    sed -i "s,\[\[$REL_PATH|.*\]\],\[\[$REL_PATH|$FINAL_TITLE\]\],g" "$INDEX_FILE"
fi

YAML_TAGS=$(grep "^tags: " "$FILE_PATH" | sed 's/tags: \[\(.*\)\]/\1/' | sed 's/, / /g')
BODY_TAGS=$(grep -oP '#[a-zA-Z0-9_]+' "$FILE_PATH" | sed 's/#//')
ALL_TAGS=$(echo "$YAML_TAGS $BODY_TAGS" | tr ' ' '\n' | sort -u)

for TAG in $ALL_TAGS; do
    if [ ! -z "$TAG" ]; then
        SUB_FILE="$SUBJECTS_DIR/${TAG}.md"
        if [ ! -f "$SUB_FILE" ]; then
            echo "# Subject: $TAG" > "$SUB_FILE"
            echo -e "\n## Notes" >> "$SUB_FILE"
        fi
        if ! grep -q "$REL_PATH" "$SUB_FILE"; then
            echo "- [[$REL_PATH|$FINAL_TITLE]] ($FULL_DATE)" >> "$SUB_FILE"
        else
            sed -i "s,\[\[$REL_PATH|.*\]\],\[\[$REL_PATH|$FINAL_TITLE\]\],g" "$SUB_FILE"
        fi
    fi
done
