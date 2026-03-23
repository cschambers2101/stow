#!/bin/sh

# background
#feh --bg-scale ~/.local/share/backgrounds/wallhaven-85erok_3440x1440.png &
#feh --no-fehbg \
#    --output DVI-I-1-1 --bg-scale ~/.local/share/backgrounds/wallhaven-85erok_3440x1440.png \
#    --output eDP-1 --bg-scale ~/.local/share/backgrounds/wallhaven-85erok_3440x1440.png
~/.local/bin/set-wallpaper.sh &


# nitrogen --restore &

# compositor
picom --config ~/.config/picom/picom.conf &

# Notifications
dunst &

# Network Manager
nm-applet &

# Set keymap
setxkbmap -layout gb

# 1. Kill any existing instances to avoid duplicates
pkill xss-lock

# 2. Set the idle timeout to 600 seconds (10 mins)
# We also disable 'blanking' so your script handles the visuals immediately
xset s 180 180
xset s noblank
xset dpms 180 180 180

# 3. Start the listener with the correct filename
xss-lock --transfer-sleep-lock -- /bin/bash /home/craigchambers/.local/bin/i3lock-screensaver.sh &

if [ -f ~/.screenlayout/screens.sh ]; then
    . ~/.screenlayout/screens.sh
fi
