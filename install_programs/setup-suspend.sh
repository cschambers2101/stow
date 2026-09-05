#!/usr/bin/env bash
# setup-suspend.sh — make suspend/resume survive the two things known to break it
#
#   1. Realtek rtw89 wifi (RTL8852BE and family) never returns from S3 while its
#      driver is bound.      -> sleep hook unloads the driver before sleep, reloads after
#   2. An rclone FUSE mount (Google Drive) holds tasks in D state and the kernel
#      freezer gives up.     -> system unit stops the mount before sleep, restarts after
#
# Each part is installed ONLY where the machine needs it, so on a plain student
# laptop this usually prints two "not needed" lines and does nothing. Safe to
# re-run: it is called from ubuntu_26.04_niri_install.sh (section 14) and again
# from setup_rclone_for_google_drive.sh once the mount exists.
#
# Reasoning, test evidence and the day-to-day story:
#     projects/linux-device-build-2026/notes/decisions-log.md      (private workspace)
#     reference/machine-rebuild.md §Suspend/resume                 (private workspace)
#
# Usage:  bash setup-suspend.sh [--force-rtw89] [--force-rclone] [--status]
#
# Never fails the build: every problem is a WARNING on stderr and the exit code is 0.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)     # never a hardcoded path
SRC="$HERE/suspend"

# systemd 259 reads ONLY /usr/lib/systemd/system-sleep. A hook in
# /etc/systemd/system-sleep is ignored silently (5 Sep 2026).
HOOK_DST=/usr/lib/systemd/system-sleep/rtw89-reload
HOOK_WRONG=/etc/systemd/system-sleep/rtw89-reload
UNIT_DST=/etc/systemd/system/rclone-sleep.service
RCLONE_UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/rclone-mount.service"

FORCE_RTW89=no; FORCE_RCLONE=no; STATUS_ONLY=no
for a in "$@"; do
    case "$a" in
        --force-rtw89)  FORCE_RTW89=yes ;;
        --force-rclone) FORCE_RCLONE=yes ;;
        --status)       STATUS_ONLY=yes ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 0 ;;
    esac
done

warn() { echo "WARNING: $*" >&2; }

# A wireless device currently driven by rtw89_*: the driver's sysfs directory
# lists bound devices by bus address (PCI "0000:03:00.0", USB "1-3:1.0").
has_rtw89() {
    local d
    for d in /sys/bus/*/drivers/rtw89_*/; do
        [ -d "$d" ] || continue
        compgen -G "${d}[0-9]*" >/dev/null 2>&1 && return 0
    done
    # Fallback for a card present but not bound (odd, but cheap to cover).
    lspci -k 2>/dev/null | grep -q 'Kernel driver in use: rtw89_' && return 0
    return 1
}

has_rclone_mount() {
    [ -f "$RCLONE_UNIT" ] && return 0
    systemctl --user list-unit-files rclone-mount.service --no-legend 2>/dev/null | grep -q rclone-mount
}

# ---------------------------------------------------------------------------
echo "--- suspend/resume: rtw89 wifi ---"
if has_rtw89 || [ "$FORCE_RTW89" = yes ]; then
    if [ "$STATUS_ONLY" = yes ]; then
        [ -x "$HOOK_DST" ] && echo "rtw89 wifi present; hook installed at $HOOK_DST" \
                           || echo "rtw89 wifi present; hook NOT installed"
    else
        if [ ! -r "$SRC/rtw89-reload" ]; then
            warn "$SRC/rtw89-reload missing — hook not installed"
        elif cmp -s "$SRC/rtw89-reload" "$HOOK_DST" 2>/dev/null; then
            echo "rtw89 wifi present; hook already current at $HOOK_DST"
        elif sudo install -D -m 755 -o root -g root "$SRC/rtw89-reload" "$HOOK_DST"; then
            echo "rtw89 wifi present; installed $HOOK_DST"
        else
            warn "could not install $HOOK_DST — wifi will not survive suspend"
        fi
        if [ -e "$HOOK_WRONG" ]; then
            sudo rm -f "$HOOK_WRONG" && echo "removed stale $HOOK_WRONG (systemd never reads that directory)"
            sudo rmdir "$(dirname "$HOOK_WRONG")" 2>/dev/null || true
        fi
    fi
else
    echo "no rtw89 wifi — hook not needed"
fi

# ---------------------------------------------------------------------------
echo "--- suspend/resume: rclone mount ---"
if has_rclone_mount || [ "$FORCE_RCLONE" = yes ]; then
    if [ "$STATUS_ONLY" = yes ]; then
        echo "rclone mount present; rclone-sleep.service is $(systemctl is-enabled rclone-sleep.service 2>/dev/null | head -1 || echo absent)"
    else
        if [ ! -r "$SRC/rclone-sleep.service" ]; then
            warn "$SRC/rclone-sleep.service missing — unit not installed"
        else
            if cmp -s "$SRC/rclone-sleep.service" "$UNIT_DST" 2>/dev/null; then
                echo "rclone mount present; unit already current at $UNIT_DST"
            elif sudo install -D -m 644 -o root -g root "$SRC/rclone-sleep.service" "$UNIT_DST"; then
                echo "rclone mount present; installed $UNIT_DST"
                sudo systemctl daemon-reload || warn "daemon-reload failed"
            else
                warn "could not install $UNIT_DST — stop the mount by hand before suspending"
            fi
            if [ "$(systemctl is-enabled rclone-sleep.service 2>/dev/null | head -1)" != enabled ]; then
                sudo systemctl enable rclone-sleep.service >/dev/null 2>&1 \
                    && echo "enabled rclone-sleep.service" \
                    || warn "could not enable rclone-sleep.service"
            fi
        fi
    fi
else
    echo "no rclone mount — unit not needed"
fi

exit 0
