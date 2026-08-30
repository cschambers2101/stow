#!/usr/bin/env bash
# Screenshot the desktop, pixelate it, hand it to the DMS lock screen.
#
# Usage: dank-lock.sh [--demo]
#   --demo   render the lock screen without locking; click anywhere to dismiss.
#
# DMS picks the lock background from SettingsData.lockScreenWallpaperPath and then
# runs it through its own MultiEffect blur + 40% black dim, so we only supply the
# pixelation here. Clear the path on unlock so a stale desktop shot can never be
# shown by a lock we didn't initiate (control centre button, lid close, loginctl).

set -euo pipefail

demo=false
[[ ${1:-} == --demo ]] && demo=true

dir="${XDG_RUNTIME_DIR:-/tmp}/danklock"
mkdir -p "$dir" && chmod 700 "$dir"
rm -f "$dir"/*.png                        # previous shot is off-screen by now

# lockScreenWallpaperPath is global, so a single capture covers every output.
out=$(niri msg --json outputs | jq -r 'keys[0]')
# Unique name each time: plainWallpaperComp is an Image{cache:true}, and Qt caches
# by URL, so a fixed path would redisplay the previous lock's screenshot.
shot="$dir/$(date +%s%N).png"

grim -o "$out" - | magick png:- -scale 10% -scale 1000% "$shot"

dms ipc call settings set lockScreenWallpaperPath "$shot" >/dev/null

if $demo; then
    exec dms ipc call lock demo
fi

dms ipc call lock lock >/dev/null

{
    # Wait for the lock to actually take hold before watching for it to end,
    # otherwise the first poll clears the path before the surface renders.
    for _ in {1..25}; do
        [[ $(dms ipc call lock isLocked) == true ]] && break
        sleep 0.2
    done
    while [[ $(dms ipc call lock isLocked) == true ]]; do sleep 2; done
    dms ipc call settings set lockScreenWallpaperPath "" >/dev/null
    rm -f "$shot"
} &
