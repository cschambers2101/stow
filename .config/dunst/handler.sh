#!/bin/bash

# Dunst passes variables to scripts. 
# The "Action" (like the URL) is usually the last argument.

appname=$1
summary=$2
body=$3
icon=$4
urgency=$5
action=$6

# If the action looks like a URL or a command, open it
if [ -n "$action" ]; then
    xdg-open "$action" &
fi
