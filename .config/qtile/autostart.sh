#!/bin/sh

# background
#feh --bg-scale ~/.local/share/backgrounds/wallhaven-85erok_3440x1440.png &
nitrogen --restore &

# compositor
picom --config ~/.config/picom/picom.conf &

# sxhkd
sxhkd -c ~/.config/qtile/sxhkd/sxhkdrc &

# Notifications
dunst &

# Network Manager
nm-applet &

# Disable tap to click on Dell XPS Touchpad
subprocess.call(['xinput', 'set-prop', '9', 'Synaptics Tap Action', '0', '0', '0', '0', '0', '0', '0'])

