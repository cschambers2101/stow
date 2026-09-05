#!/usr/bin/env bash
# Screenshot the desktop, pixelate it, hand it to the DMS lock screen. Usage: dank-lock.sh [--demo]

set -euo pipefail

demo=false
[[ ${1:-} == --demo ]] && demo=true

dir="${XDG_RUNTIME_DIR:-/tmp}/danklock"
mkdir -p "$dir" && chmod 700 "$dir"
rm -f "$dir"/*.png

out=$(niri msg --json outputs | jq -r 'keys[0]')
shot="$dir/$(date +%s%N).png"

grim -o "$out" - | magick png:- -scale 10% -scale 1000% "$shot"

dms ipc call settings set lockScreenWallpaperPath "$shot" >/dev/null

if $demo; then
    exec dms ipc call lock demo
fi

dms ipc call lock lock >/dev/null

{
    for _ in {1..25}; do
        [[ $(dms ipc call lock isLocked) == true ]] && break
        sleep 0.2
    done

    if command -v dbus-monitor >/dev/null; then
        fifo=$(mktemp -u)
        mkfifo -m 600 "$fifo"
        stdbuf -oL dbus-monitor --system \
            "type='signal',interface='org.freedesktop.DBus.Properties',path_namespace='/org/freedesktop/login1/session'" \
            > "$fifo" 2>/dev/null &
        mon=$!
        trap 'kill "$mon" 2>/dev/null; rm -f "$fifo"' EXIT
        while IFS= read -r line; do
            [[ $line == *false* ]] || continue
            [[ $(dms ipc call lock isLocked) == true ]] || break
        done < "$fifo"
        kill "$mon" 2>/dev/null
        rm -f "$fifo"
        trap - EXIT
    else
        while [[ $(dms ipc call lock isLocked) == true ]]; do sleep 30; done
    fi

    dms ipc call settings set lockScreenWallpaperPath "" >/dev/null
    rm -f "$shot"
} &
