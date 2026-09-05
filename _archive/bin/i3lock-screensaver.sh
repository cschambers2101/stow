#!/bin/bash
# Script to capture all screens, blur them, and use as the i3lock background.

# Pause Dunst notifications
dunstctl set-paused true

# 1. Take a screenshot of the entire desktop (all monitors)
scrot /tmp/lock_screen.png

# 2. Pixelate the screenshot (or blur it) for aesthetic effect and security
#    Requires the 'imagemagick' package (convert utility)
convert /tmp/lock_screen.png -scale 10% -scale 1000% /tmp/lock_screen_pixel.png

# 3. Lock the screen using the prepared image
#    The -i flag is used here, but it points to the generated image.
i3lock -n -i /tmp/lock_screen_pixel.png

# 4. Clean up
rm /tmp/lock_screen.png /tmp/lock_screen_pixel.png

# 5. Resume Dunst notifications
dunstctl set-paused false
