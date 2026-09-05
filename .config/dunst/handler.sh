#!/usr/bin/env bash
# dunst action handler: the action (a URL or command) arrives as the sixth argument.
action="${6:-}"
[ -n "$action" ] && xdg-open "$action" &
