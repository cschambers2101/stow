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

# Kill any potentially running screen locker/screensaver
# killall xscreensaver &
#
# # Start the xscreensaver daemon (silently)
# xscreensaver -no-splash &
#
