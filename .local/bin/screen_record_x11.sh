#!/bin/bash

# Configuration
RECORDING_PID_FILE="/tmp/ffmpeg_recording_pid.txt"
OUTPUT_DIR="$HOME/Videos"
# Output file format (uses date/time stamp)
OUTPUT_FILE="$OUTPUT_DIR/screencast_$(date +%Y%m%d_%H%M%S).mp4"
# Recording parameters
FPS="30"
RESOLUTION="1920x1080" # IMPORTANT: Change this to your monitor's resolution
DISPLAY_INPUT=":1"

# --- Check if recording is already running ---
if [ -f "$RECORDING_PID_FILE" ]; then
    PID=$(cat "$RECORDING_PID_FILE")
    if ps -p $PID > /dev/null; then
        # Process is running, so stop it
        kill -INT $PID
        rm "$RECORDING_PID_FILE"
        notify-send -t 3000 "Screen Recording" "Stopped recording to $(basename $OUTPUT_FILE)"
        exit 0
    else
        # Process file exists but process is dead (cleanup)
        rm "$RECORDING_PID_FILE"
    fi
fi

# --- Start a new recording ---

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Run the ffmpeg command in the background
ffmpeg -f x11grab -r "$FPS" -s "$RESOLUTION" -i "$DISPLAY_INPUT" \
  -vcodec libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p "$OUTPUT_FILE" &

# Save the PID of the background process
echo $! > "$RECORDING_PID_FILE"

# Send a notification that recording has started
notify-send -t 3000 "Screen Recording" "Started recording..."
