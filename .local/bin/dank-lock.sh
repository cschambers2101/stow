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
    # otherwise we clear the path before the surface renders.
    for _ in {1..25}; do
        [[ $(dms ipc call lock isLocked) == true ]] && break
        sleep 0.2
    done

    # Then BLOCK on a D-Bus signal instead of polling.
    #
    # This used to be `while isLocked; do sleep 2; done` -- one IPC
    # connection every 2s for as long as the screen stayed locked, i.e. 1800
    # an hour. Left locked overnight on 1 Sep 2026 that reached 13,281
    # connections and quickshell crashed:
    #
    #   ERROR: Quickshell has crashed under pid 516051
    #   ERROR: Quickshell has been restarted.
    #
    # The restart came up with no surfaces attached, leaving a flat
    # wallpaper-coloured screen with a working mouse for twelve hours. The
    # crash and the broken recovery are upstream bugs; the flood was ours.
    #
    # DMS mirrors lock state onto logind's LockedHint (Lock.qml
    # notifyLockedHint, gated on SettingsData.loginctlLockIntegration, which
    # defaults true). LockedHint is a D-Bus property, so it emits
    # PropertiesChanged and we can wait on that: ZERO polls while locked,
    # and it reacts the moment the screen unlocks.
    #
    # Three implementation details, each of which cost a test to find:
    #   * dbus-monitor, NOT gdbus monitor. gdbus is a GLib program and does
    #     not use libc stdio, so `stdbuf` cannot line-buffer it and a pipe
    #     to grep blocks forever.
    #   * stdbuf -oL, or dbus-monitor block-buffers into the pipe.
    #   * a bash `read` loop rather than `grep -m1 -q`, which also buffers.
    #
    # The isLocked re-check after the loop keeps the old behaviour if the
    # signal is missed or D-Bus is unavailable: fall back to a SLOW poll
    # (30s, not 2s) rather than trusting the signal blindly.
    SESSION_PATH=$(gdbus call --system \
        --dest org.freedesktop.login1 \
        --object-path /org/freedesktop/login1 \
        --method org.freedesktop.login1.Manager.GetSession "${XDG_SESSION_ID:-}" \
        2>/dev/null | grep -o "/org/freedesktop/login1/session/[^']*")

    if [[ -n $SESSION_PATH ]] && command -v dbus-monitor >/dev/null; then
        while IFS= read -r line; do
            [[ $line == *false* ]] || continue
            [[ $(dms ipc call lock isLocked) == true ]] || break
        done < <(stdbuf -oL dbus-monitor --system \
                    "type='signal',path='$SESSION_PATH',interface='org.freedesktop.DBus.Properties'" \
                    2>/dev/null)
    else
        while [[ $(dms ipc call lock isLocked) == true ]]; do sleep 30; done
    fi

    dms ipc call settings set lockScreenWallpaperPath "" >/dev/null
    rm -f "$shot"
} &
