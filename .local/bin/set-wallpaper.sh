#!/bin/bash

# --- Configuration ---
WALLPAPER_DIR="$HOME/.local/share/backgrounds/"
# IMPORTANT: List the exact screen output names from your original script.
SCREEN_OUTPUTS=("DVI-I-1-1" "eDP-1")
# --- End Configuration ---

echo "Starting random wallpaper selection from: $WALLPAPER_DIR"

# 1. Find all potential wallpaper files using shell globbing (safest method)
# Enable nullglob to handle the case where no files match the pattern
shopt -s nullglob
WALLPAPERS=("$WALLPAPER_DIR"*.jpg "$WALLPAPER_DIR"*.png)
shopt -u nullglob

# Store the randomized list of files
ALL_WALLPAPERS=($(printf "%s\n" "${WALLPAPERS[@]}" | shuf))

# Check if any wallpapers were found
if [ ${#ALL_WALLPAPERS[@]} -eq 0 ]; then
    echo "Error: No wallpapers found in $WALLPAPER_DIR."
    echo "Please check if files with extensions .jpg or .png exist."
    exit 1
fi

# 2. Build the final 'feh' command string iteratively
FEH_COMMAND="feh --no-fehbg"
WALLPAPER_COUNT=${#ALL_WALLPAPERS[@]}

# Loop through each configured screen output
for i in "${!SCREEN_OUTPUTS[@]}"; do
    OUTPUT_NAME="${SCREEN_OUTPUTS[$i]}"
    
    if [ $i -lt $WALLPAPER_COUNT ]; then
        WALLPAPER_PATH="${ALL_WALLPAPERS[$i]}"
    else
        RANDOM_INDEX=$(( RANDOM % WALLPAPER_COUNT ))
        WALLPAPER_PATH="${ALL_WALLPAPERS[$RANDOM_INDEX]}"
        echo "Warning: Ran out of unique wallpapers. Reusing a random one for screen $OUTPUT_NAME."
    fi

    echo "  -> Screen $OUTPUT_NAME: Setting to $WALLPAPER_PATH"

    FEH_COMMAND+=" --output $OUTPUT_NAME --bg-scale \"$WALLPAPER_PATH\""
done

# 3. Execute the final command
echo "--- Executing feh ---"
eval "$FEH_COMMAND"

echo "Script finished."
