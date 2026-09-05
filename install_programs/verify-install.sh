#!/usr/bin/env bash
# Post-install verification for the niri build. Exits 1 if anything FAILED.
# Usage: bash ~/.dotfiles/install_programs/verify-install.sh

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S6C_NO_STRICT=1
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

PASS=0; FAIL=0; SKIP=0


pass() { printf "  %sPASS%s  %-32s %s\n" "$C_G" "$C_0" "$1" "$2"; PASS=$((PASS+1)); }
fail() { printf "  %sFAIL%s  %-32s %s\n" "$C_R" "$C_0" "$1" "$2"; FAIL=$((FAIL+1)); }
skip() { printf "  %sSKIP%s  %-32s %s\n" "$C_Y" "$C_0" "$1" "$2"; SKIP=$((SKIP+1)); }

ok() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$n" ""; else fail "$n" "command failed: $*"; fi; }

eq() { if [ "$2" = "$3" ]; then pass "$1" "$3"; else fail "$1" "want='$2' got='$3'"; fi; }

has() { case "$3" in *"$2"*) pass "$1" "$(printf '%s' "$3" | head -1 | cut -c1-46)";; *) fail "$1" "want~'$2' got='$(printf '%s' "$3" | head -1 | cut -c1-40)'";; esac; }

pkg() { if dpkg -s "$2" 2>/dev/null | grep -q '^Status: install ok installed'; then pass "$1" "$2"; else fail "$1" "$2 not installed"; fi; }

have_sudo() { sudo -n true 2>/dev/null; }

echo "Post-install verification — $(hostname) — $(date '+%Y-%m-%d %H:%M')"
echo

echo "--- system ---"
eq "no failed units" "0" "$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | grep -c .)"
if systemctl --user is-system-running >/dev/null 2>&1 || [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    USER_FAILED="$(systemctl --user list-units --state=failed --no-legend --plain 2>/dev/null | grep -c .)"
    if [ "${USER_FAILED:-0}" = "0" ]; then
        pass "no failed user units" ""
    else
        fail "no failed user units" "$(systemctl --user list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
    fi
else
    skip "no failed user units" "no user session to query"
fi
eq "greetd active" "active" "$(systemctl is-active greetd 2>/dev/null)"
eq "display-manager is greetd" "greetd.service" \
   "$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null)"
GDM_STATE="$(systemctl is-enabled gdm.service 2>/dev/null | head -1 | xargs)"
case "${GDM_STATE:-absent}" in
    disabled|masked|absent) pass "gdm not enabled" "${GDM_STATE:-not installed}" ;;
    *)                      fail "gdm not enabled" "gdm is '$GDM_STATE' — it will fight greetd" ;;
esac

echo "--- Qt plugins (silent bugs 7 and 8) ---"
pkg "qt6-svg-plugins" "qt6-svg-plugins"
pkg "qt6-gtk-platformtheme" "qt6-gtk-platformtheme"
if compgen -G "/usr/lib/*/qt6/plugins/imageformats/libqsvg.so" >/dev/null; then
    pass "libqsvg.so present" ""; else fail "libqsvg.so present" "not found under /usr/lib/*/qt6"; fi
if compgen -G "/usr/lib/*/qt6/plugins/platformthemes/libqgtk3.so" >/dev/null; then
    pass "libqgtk3.so present" ""; else fail "libqgtk3.so present" "not found under /usr/lib/*/qt6"; fi

echo "--- packages ---"
if [ -f "$PKG_LIST" ]; then
    MISSING=""
    while read -r p _; do
        case "$p" in ''|'#'*) continue;; esac
        dpkg -s "$p" 2>/dev/null | grep -q '^Status: install ok installed' || MISSING="$MISSING $p"
    done < "$PKG_LIST"
    if [ -z "$MISSING" ]; then pass "all list packages present" "$(grep -cvE '^\s*#|^\s*$' "$PKG_LIST") packages"
    else fail "all list packages present" "missing:$MISSING"; fi
else
    skip "all list packages present" "list not found at $PKG_LIST"
fi

echo "--- fonts ---"
has "Atkinson Next resolves" "Atkinson Hyperlegible Next" "$(fc-match 'Atkinson Hyperlegible Next' 2>/dev/null)"
has "Atkinson Mono resolves" "Atkinson Hyperlegible Mono" "$(fc-match 'Atkinson Hyperlegible Mono' 2>/dev/null)"

echo "--- machine identity (bugs 5 and 6) ---"
has "keyboard layout gb" 'XKBLAYOUT="gb"' "$(grep XKBLAYOUT /etc/default/keyboard 2>/dev/null)"
has "keyboard model pc105" 'XKBMODEL="pc105"' "$(grep XKBMODEL /etc/default/keyboard 2>/dev/null)"
ZRAM_ALGO="$(zramctl --output ALGORITHM --noheadings 2>/dev/null | head -1 | xargs)"
if [ -z "$ZRAM_ALGO" ]; then skip "zram algorithm zstd" "no zram device active"
else eq "zram algorithm zstd" "zstd" "$ZRAM_ALGO"; fi

echo "--- greeter and desktop (bugs 9 and 10) ---"
ok "wallpaper installed" test -f "$S6C_WALLPAPER"

SETTINGS="$HOME/.config/DankMaterialShell/settings.json"
if [ -f "$SETTINGS" ]; then
    has "greeter wallpaper set" "ladybird" \
        "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("greeterWallpaperPath",""))' "$SETTINGS" 2>/dev/null)"
else skip "greeter wallpaper set" "no settings.json"; fi

SESSION="$HOME/.local/state/DankMaterialShell/session.json"
if [ -f "$SESSION" ]; then
    has "desktop wallpaper seeded" "ladybird" \
        "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("wallpaperPath",""))' "$SESSION" 2>/dev/null)"
else skip "desktop wallpaper seeded" "no session.json"; fi

OVERRIDE="/var/cache/dms-greeter/greeter_wallpaper_override.jpg"
if [ -r "$OVERRIDE" ]; then pass "greeter override synced" ""
elif have_sudo && sudo test -f "$OVERRIDE"; then pass "greeter override synced" ""
elif have_sudo; then fail "greeter override synced" "missing — did 'dms greeter sync' run?"
else skip "greeter override synced" "needs sudo"; fi

if [ -f "$HOME/.face" ] || [ -f "$HOME/.face.icon" ]; then pass "avatar seeded" "$HOME/.face"
else fail "avatar seeded" "no ~/.face — greeter will show an empty circle"; fi

ok "pam dankshell created" test -f /etc/pam.d/dankshell

if dpkg -s update-notifier 2>/dev/null | grep -q '^Status: install ok installed'; then
    fail "update-notifier purged" "still installed — tray nag returns"
else pass "update-notifier purged" ""; fi

echo "--- shell stability ---"
if [ -d "$HOME/.cache/quickshell/crashes" ] && \
   [ -n "$(ls -A "$HOME/.cache/quickshell/crashes" 2>/dev/null)" ]; then
    NCRASH="$(find "$HOME/.cache/quickshell/crashes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    fail "quickshell has not crashed" "$NCRASH crash dump(s) in ~/.cache/quickshell/crashes"
else
    pass "quickshell has not crashed" ""
fi

QSLOG="$(ls -t "/run/user/$(id -u)"/quickshell/by-id/*/log.qslog 2>/dev/null | head -1)"
if [ -z "$QSLOG" ]; then
    skip "shell IPC connections sane" "no running quickshell log"
else
    NIPC="$(strings "$QSLOG" 2>/dev/null | grep -c 'New IPC connection')"
    if [ "${NIPC:-0}" -lt 2000 ]; then
        pass "shell IPC connections sane" "$NIPC this session"
    else
        fail "shell IPC connections sane" "$NIPC — something is polling the IPC socket"
    fi
fi

echo "--- file integrity ---"
if have_sudo; then
    DPKGV="$(sudo dpkg -V 2>/dev/null | awk '$2 != "c"' | wc -l)"
    if [ "$DPKGV" = "0" ]; then
        pass "installed files match their checksums" ""
    else
        fail "installed files match their checksums" \
             "$DPKGV package file(s) differ — run: sudo dpkg -V | awk '\$2 != \"c\"'"
    fi
else
    skip "installed files match their checksums" "needs sudo"
fi

echo "--- node ---"
NVM_SH=""
for d in "$HOME/.config/nvm" "$HOME/.nvm"; do
    [ -s "$d/nvm.sh" ] && { NVM_SH="$d/nvm.sh"; break; }
done
if [ -z "$NVM_SH" ]; then
    skip "node usable in a login shell" "nvm not installed"
else
    NODEV="$(bash -lic 'command -v node >/dev/null 2>&1 && node --version' 2>/dev/null | tail -1)"
    if [ -n "$NODEV" ]; then
        pass "node usable in a login shell" "$NODEV"
    else
        fail "node usable in a login shell" "nvm is at $NVM_SH but node does not resolve — check NVM_DIR in .bashrc"
    fi
fi

echo "--- apt hygiene ---"
if apt-config dump 2>/dev/null | grep -q 'DPkg::Lock::Timeout'; then
    pass "apt waits for the dpkg lock" "$(apt-config dump 2>/dev/null | awk -F'"' '/DPkg::Lock::Timeout/{print $2 "s"}')"
else
    fail "apt waits for the dpkg lock" "a background apt run can abort an install"
fi

echo "--- music ---"
if systemctl is-enabled yt-dlp-update.timer >/dev/null 2>&1; then
    pass "yt-dlp auto-update timer enabled" "$(systemctl show -p NextElapseUSecRealtime --value yt-dlp-update.timer 2>/dev/null | cut -c1-24)"
else
    fail "yt-dlp auto-update timer enabled" "yt-dlp will silently stop working when YouTube changes"
fi

if command -v yt-dlp >/dev/null 2>&1; then
    pass "yt-dlp present" "$(yt-dlp --version 2>/dev/null)"
else
    fail "yt-dlp present" "not installed"
fi

if command -v AtomicParsley >/dev/null 2>&1; then
    pass "AtomicParsley present" "cover art for m4a/aac"
else
    fail "AtomicParsley present" "cover art will not embed into m4a/aac"
fi

if flatpak info io.bassi.Amberol >/dev/null 2>&1; then
    pass "Amberol installed" "$(flatpak info io.bassi.Amberol 2>/dev/null | awk -F': *' '/^ *Version:/{print $2; exit}')"
else
    fail "Amberol installed" "no simple player; Rhythmbox still covers the library"
fi

echo "--- security: Oakford root CA (bug 11) ---"
CA="$OAKFORD_CA_PATH"
PIN="$OAKFORD_SHA256"

if [ ! -f "$CA" ]; then
    fail "CA installed" "$CA missing — internal HTTPS will not be trusted"
elif [ -z "$PIN" ]; then
    skip "CA fingerprint pinned" "OAKFORD_SHA256 is empty in lib/common.sh"
else
    pass "CA installed" ""
    GOT="$(openssl x509 -in "$CA" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)"
    if [ "$GOT" = "$PIN" ]; then pass "CA fingerprint matches pin" "${GOT:0:23}..."
    else fail "CA fingerprint matches pin" "SECURITY: got ${GOT:-<not a certificate>}"; fi
    if openssl verify -CApath /etc/ssl/certs "$CA" >/dev/null 2>&1; then
        pass "CA trusted by the system" ""
    else fail "CA trusted by the system" "not in /etc/ssl/certs — did update-ca-certificates run?"; fi
fi

S6C_UUIDS="$(nm_wifi_uuids_for_ssid "$S6C_SSID" | xargs)"
S6C_COUNT="$(printf '%s' "$S6C_UUIDS" | wc -w | xargs)"

if [ "${S6C_COUNT:-0}" -eq 0 ]; then
    fail "wifi profile present" "NetworkManager has no connection for SSID S6C"
else
    pass "wifi profile present" "$S6C_COUNT for SSID S6C"

    if [ "$S6C_COUNT" -gt 1 ]; then
        fail "one profile per SSID" "$S6C_COUNT profiles named for S6C: $S6C_UUIDS"
    else
        pass "one profile per SSID" ""
    fi

    PRIOS=""; BAD=""
    for U in $S6C_UUIDS; do
        P="$(nmcli -g connection.autoconnect-priority connection show "$U" 2>/dev/null | xargs)"
        PRIOS="$PRIOS ${P:-unreadable}"
        case "${P:-x}" in
            -[0-9]*) ;;
            *) BAD="$BAD $U(${P:-unreadable})" ;;
        esac
    done
    PRIOS="$(printf '%s' "$PRIOS" | xargs)"
    if [ -n "$BAD" ]; then
        fail "wifi priority is negative" "$PRIOS — S6C may outrank the user's own network:$BAD"
    else
        pass "wifi priority is negative" "$PRIOS"
    fi

    for U in $S6C_UUIDS; do
        NMFILE="$(nmcli -t -f UUID,FILENAME connection show 2>/dev/null | sed -n "s|^$U:||p")"
        case "$NMFILE" in
            /etc/NetworkManager/*)
                if have_sudo; then
                    eq "wifi profile is 0600" "600" "$(sudo stat -c '%a' "$NMFILE" 2>/dev/null)"
                else skip "wifi profile is 0600" "needs sudo"; fi ;;
            *)  skip "wifi profile is 0600" "netplan-owned (${NMFILE:-unknown})" ;;
        esac
    done

    if have_sudo; then
        PSK_BAD=""
        for U in $S6C_UUIDS; do
            sudo nmcli -s -g 802-11-wireless-security.psk connection show "$U" 2>/dev/null \
                | grep -q '.' || PSK_BAD="$PSK_BAD $U"
        done
        if [ -z "$PSK_BAD" ]; then
            pass "wifi PSK non-empty" ""
        else
            fail "wifi PSK non-empty" "psk is blank on:$PSK_BAD — will not authenticate"
        fi
    else
        skip "wifi PSK non-empty" "needs sudo to read the secret"
    fi
fi

echo "--- clock ---"
NTP_SYNC="$(timedatectl show --property=NTPSynchronized --value 2>/dev/null)"
case "$NTP_SYNC" in
    yes) pass "clock synchronised" "" ;;
    no)  fail "clock synchronised" "NTP service may claim active while never reaching a source" ;;
    *)   skip "clock synchronised" "timedatectl gave no answer" ;;
esac

if command -v chronyc >/dev/null 2>&1; then
    SEL="$(chronyc -n sources 2>/dev/null | grep -cE '^\^[*+]')"
    if [ "${SEL:-0}" -gt 0 ]; then
        pass "chrony has a selected source" "$SEL"
    else
        fail "chrony has a selected source" "no source reachable — TCP 4460 filtered? try plain-NTP sources"
    fi
else
    skip "chrony has a selected source" "chronyc not installed"
fi

echo "--- secure boot ---"
SB_STATE="$(secure_boot_state)"
NEEDS_DKMS=""
lspci -nn 2>/dev/null | grep -iE "network|wireless" | grep -qi broadcom && NEEDS_DKMS="$NEEDS_DKMS broadcom"
lspci -nn 2>/dev/null | grep -iE "vga|3d controller" | grep -qi nvidia   && NEEDS_DKMS="$NEEDS_DKMS nvidia"

case "$SB_STATE" in
    off)         pass "secure boot off where DKMS needed" "disabled" ;;
    unsupported) pass "secure boot off where DKMS needed" "not supported by this firmware" ;;
    on)
        if [ -z "$NEEDS_DKMS" ]; then
            pass "secure boot off where DKMS needed" "on — no DKMS hardware here; hibernate unavailable"
        else
            fail "secure boot off where DKMS needed" "ON, and this machine has:$NEEDS_DKMS — those modules cannot load"
        fi ;;
    *)           skip "secure boot off where DKMS needed" "could not read state (is mokutil installed?)" ;;
esac

if [ "$SB_STATE" = on ] && dpkg -s broadcom-sta-dkms >/dev/null 2>&1; then
    fail "no unloadable DKMS modules" "broadcom-sta-dkms is installed under Secure Boot — it blacklists the in-kernel drivers and cannot load itself"
else
    pass "no unloadable DKMS modules" ""
fi

echo "--- suspend ---"
if [ ! -r /sys/power/mem_sleep ]; then
    skip "deep sleep where available" "no /sys/power/mem_sleep"
elif ! grep -qw deep /sys/power/mem_sleep; then
    pass "deep sleep where available" "no S3 in firmware — s2idle is all there is"
elif grep -q '\[deep\]' /sys/power/mem_sleep; then
    pass "deep sleep where available" "deep"
elif grep -q 'mem_sleep_default=deep' /etc/default/grub 2>/dev/null; then
    pass "deep sleep where available" "configured — applies after reboot"
else
    fail "deep sleep where available" "S3 available but active is $(cat /sys/power/mem_sleep) — mem_sleep_default=deep not applied"
fi

RTW89_DEV=""
has_rtw89 && RTW89_DEV="rtw89"
if [ -z "$RTW89_DEV" ]; then
    pass "rtw89 sleep hook" "no rtw89 wifi — not needed"
elif [ -e /etc/systemd/system-sleep/rtw89-reload ]; then
    fail "rtw89 sleep hook" "copy in /etc/systemd/system-sleep — systemd never reads it; run setup-suspend.sh"
elif [ -x /usr/lib/systemd/system-sleep/rtw89-reload ]; then
    pass "rtw89 sleep hook" "$RTW89_DEV — hook installed"
else
    fail "rtw89 sleep hook" "$RTW89_DEV present but no /usr/lib/systemd/system-sleep/rtw89-reload — wifi will not survive suspend"
fi
if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/rclone-mount.service" ]; then
    eq "rclone stopped around sleep" "enabled" "$(systemctl is-enabled rclone-sleep.service 2>/dev/null | head -1 | xargs)"
else
    pass "rclone stopped around sleep" "no rclone mount — not needed"
fi

echo "--- graphics (real GPU, not llvmpipe) ---"

GPU_LINE="$(lspci -nnk 2>/dev/null | grep -iE 'vga compatible|3d controller' | head -1)"
if [ -z "$GPU_LINE" ]; then
    skip "gpu detected" "lspci reported no VGA/3D controller"
else
    pass "gpu detected" "$(printf '%s' "$GPU_LINE" | sed 's/.*: //' | cut -c1-46)"

    if compgen -G "/dev/dri/renderD*" >/dev/null; then
        pass "drm render node present" "$(ls -d /dev/dri/renderD* | tr '\n' ' ')"
    else
        fail "drm render node present" "no /dev/dri/renderD* — no hardware allocator"
    fi

    case "$GPU_LINE" in
    *NVIDIA*|*nVidia*)
        has "nvidia driver bound" "nvidia" \
            "$(lspci -nnk 2>/dev/null | grep -A3 -iE 'vga compatible|3d controller' | grep -i 'driver in use' | head -1 | sed 's/.*: //')"
        ok  "nvidia_drm loaded" sh -c 'lsmod | grep -q "^nvidia_drm"'
        ok  "nvidia-smi responds" sh -c 'nvidia-smi -L >/dev/null 2>&1'
        if lsmod | grep -q '^nouveau'; then
            fail "nouveau not loaded" "nouveau is loaded alongside nvidia"
        else
            pass "nouveau not loaded" ""
        fi
        SB="$(mokutil --sb-state 2>/dev/null | head -1)"
        case "$SB" in
            *disabled*)  pass "secure boot disabled" "$SB" ;;
            "")          skip "secure boot disabled" "mokutil unavailable" ;;
            *)           fail "secure boot disabled" "$SB — DKMS modules will not load" ;;
        esac
        ;;
    *AMD*|*ATI*|*Radeon*)
        ok "amdgpu loaded" sh -c 'lsmod | grep -qE "^amdgpu"'
        ;;
    *Intel*)
        ok "intel kms loaded" sh -c 'lsmod | grep -qE "^i915|^xe"'
        ;;
    *)
        skip "vendor driver check" "unrecognised vendor"
        ;;
    esac

    NIRI_LOG="$(journalctl --user -b --no-pager 2>/dev/null | grep -c -i 'llvmpipe\|software rasteriz')"
    if [ -z "$(journalctl --user -b --no-pager 2>/dev/null | head -1)" ]; then
        skip "niri not on llvmpipe" "no user journal available"
    elif [ "${NIRI_LOG:-0}" = "0" ]; then
        pass "niri not on llvmpipe" "hardware renderer"
    else
        fail "niri not on llvmpipe" "software rendering — GBM allocator missing"
    fi
fi

echo
printf "PASSED %d   FAILED %d   SKIPPED %d\n" "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
    echo
    echo "Something above is wrong. Most of these faults are SILENT -- the"
    echo "install will have reported success. See the troubleshooting table in"
    echo "projects/linux-device-build-2026/notes/rollout-runbook.md."
fi
[ "$FAIL" -eq 0 ] || exit 1
exit 0
