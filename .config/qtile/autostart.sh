#!/bin/sh
nm-applet &

# background
feh --bg-scale /usr/share/backgrounds/Monument_valley_by_orbitelambda.jpg &

# compositor
picom --config ~/.config/picom/picom.conf &

# sxhkd
sxhkd -c ~/.config/qtile/sxhkd/sxhkdrc &

# Notifications
dunst &
