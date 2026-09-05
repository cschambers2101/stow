#!/bin/bash

# Define the path to the screen layout script
# Uses ~ to represent the user's home directory for portability
SCREENLAYOUT_SCRIPT=~/.screenlayout/default_screen_layout.sh

# Check if the screen layout script exists and is executable
if [ -f "$SCREENLAYOUT_SCRIPT" ]; then
  echo "Found screen layout script: $SCREENLAYOUT_SCRIPT"
  echo "Attempting to execute..."
  # Execute the script
  sh "$SCREENLAYOUT_SCRIPT"
  echo "Script execution finished."
else
  # If the script does not exist, print a message
  echo "Screen layout script not found: $SCREENLAYOUT_SCRIPT"
  echo "Skipping execution."
fi

