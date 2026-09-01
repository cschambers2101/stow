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
    # Deliberately NOT filtered to one session path.
    #
    # The obvious version resolves this session via XDG_SESSION_ID and
    # filters the match to its object path. That breaks the moment the
    # script runs from anywhere but the graphical session: over ssh,
    # XDG_SESSION_ID is the SSH session, so it watches a session that never
    # locks and the cleanup never runs. Caught in testing exactly that way.
    #
    # Watching every login1 PropertiesChanged is cheap -- they are rare --
    # and every wake is confirmed against `dms ipc call lock isLocked`
    # before acting, so a signal from another session costs one IPC call and
    # nothing else.
    if command -v dbus-monitor >/dev/null; then
        # A FIFO rather than `< <(...)` so the monitor's PID is known and it
        # can be killed explicitly. With process substitution, breaking out
        # of the read loop leaves dbus-monitor running: it only dies when it
        # next tries to write and gets SIGPIPE, and if no further signals
        # arrive it never writes. That leaked one idle process per lock --
        # caught in testing, 104 seconds after the loop had exited.
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
