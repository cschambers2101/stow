#!/bin/bash
# =================================================================
# POST-INSTALL VERIFICATION
#
# Run this ON a machine that has just been built, as the user who
# was set up:
#
#     bash ~/.dotfiles/install_programs/verify-install.sh
#
# Exits 0 if everything passed, 1 if anything FAILED. Checks that
# need root are SKIPped rather than failed when sudo is unavailable,
# so it is safe to run unprivileged -- but run it with a cached sudo
# credential to get the full set.
#
# WHY THIS EXISTS: of the bugs found during testing, most were
# SILENT. The install exited 0, printed no error, and the machine
# looked fine -- no SVG decoding, checkerboard tray icons, a greeter
# that never applied its wallpaper, a lock screen that could not
# authenticate. A green install is not evidence. Every check here
# corresponds to a bug that actually shipped; see
# projects/linux-device-build-2026/notes/vm-test-state.md.
# =================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_LIST="$SCRIPT_DIR/niri_programs_to_install.txt"
INSTALLER="$SCRIPT_DIR/ubuntu_26.04_niri_install.sh"

PASS=0; FAIL=0; SKIP=0

# Colour only on a terminal: piping this into a log should not embed
# escape codes.
if [ -t 1 ]; then C_G=$'\033[32m'; C_R=$'\033[31m'; C_Y=$'\033[33m'; C_0=$'\033[0m'
else C_G=""; C_R=""; C_Y=""; C_0=""; fi

pass() { printf "  %sPASS%s  %-32s %s\n" "$C_G" "$C_0" "$1" "$2"; PASS=$((PASS+1)); }
fail() { printf "  %sFAIL%s  %-32s %s\n" "$C_R" "$C_0" "$1" "$2"; FAIL=$((FAIL+1)); }
skip() { printf "  %sSKIP%s  %-32s %s\n" "$C_Y" "$C_0" "$1" "$2"; SKIP=$((SKIP+1)); }

# ok <name> <command...>  -- passes when the command succeeds
ok() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$n" ""; else fail "$n" "command failed: $*"; fi; }

# eq <name> <expected> <actual>
eq() { if [ "$2" = "$3" ]; then pass "$1" "$3"; else fail "$1" "want='$2' got='$3'"; fi; }

# has <name> <needle> <actual>
has() { case "$3" in *"$2"*) pass "$1" "$(printf '%s' "$3" | head -1 | cut -c1-46)";; *) fail "$1" "want~'$2' got='$(printf '%s' "$3" | head -1 | cut -c1-40)'";; esac; }

# pkg <name> <package>
pkg() { if dpkg -s "$2" 2>/dev/null | grep -q '^Status: install ok installed'; then pass "$1" "$2"; else fail "$1" "$2 not installed"; fi; }

have_sudo() { sudo -n true 2>/dev/null; }

echo "Post-install verification — $(hostname) — $(date '+%Y-%m-%d %H:%M')"
echo

# -----------------------------------------------------------------
echo "--- system ---"
eq "no failed units" "0" "$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | grep -c .)"
eq "greetd active" "active" "$(systemctl is-active greetd 2>/dev/null)"
eq "display-manager is greetd" "greetd.service" \
   "$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null)"
# `systemctl is-enabled` exits NON-ZERO when a unit is disabled, so a
# `|| echo disabled` fallback appends a second line and never matches.
# Take the first line only, and treat an absent gdm as fine.
GDM_STATE="$(systemctl is-enabled gdm.service 2>/dev/null | head -1 | xargs)"
case "${GDM_STATE:-absent}" in
    disabled|masked|absent) pass "gdm not enabled" "${GDM_STATE:-not installed}" ;;
    *)                      fail "gdm not enabled" "gdm is '$GDM_STATE' — it will fight greetd" ;;
esac

# -----------------------------------------------------------------
echo "--- Qt plugins (silent bugs 7 and 8) ---"
# Both are Recommends: of libqt6gui6, which section 1's no-recommends
# policy drops. Without the first, no Qt app can decode an SVG; without
# the second, every tray icon falls back to bare hicolor and renders as
# a transparency checkerboard.
pkg "qt6-svg-plugins" "qt6-svg-plugins"
pkg "qt6-gtk-platformtheme" "qt6-gtk-platformtheme"
# Arch-agnostic: do not hardcode x86_64-linux-gnu.
if compgen -G "/usr/lib/*/qt6/plugins/imageformats/libqsvg.so" >/dev/null; then
    pass "libqsvg.so present" ""; else fail "libqsvg.so present" "not found under /usr/lib/*/qt6"; fi
if compgen -G "/usr/lib/*/qt6/plugins/platformthemes/libqgtk3.so" >/dev/null; then
    pass "libqgtk3.so present" ""; else fail "libqgtk3.so present" "not found under /usr/lib/*/qt6"; fi

# -----------------------------------------------------------------
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

# -----------------------------------------------------------------
echo "--- fonts ---"
has "Atkinson Next resolves" "Atkinson Hyperlegible Next" "$(fc-match 'Atkinson Hyperlegible Next' 2>/dev/null)"
has "Atkinson Mono resolves" "Atkinson Hyperlegible Mono" "$(fc-match 'Atkinson Hyperlegible Mono' 2>/dev/null)"

# -----------------------------------------------------------------
echo "--- machine identity (bugs 5 and 6) ---"
# Bug 5: Ubuntu denies localed's SetX11Keyboard to every caller, root
# included, so this must come from /etc/default/keyboard.
has "keyboard layout gb" 'XKBLAYOUT="gb"' "$(grep XKBLAYOUT /etc/default/keyboard 2>/dev/null)"
has "keyboard model pc105" 'XKBMODEL="pc105"' "$(grep XKBMODEL /etc/default/keyboard 2>/dev/null)"
# Bug 6: zram-tools starts zramswap during the package sweep, so
# `enable --now` is a no-op and the ALGO edit never reaches the live
# device. Checking the config file would miss this -- check the device.
ZRAM_ALGO="$(zramctl --output ALGORITHM --noheadings 2>/dev/null | head -1 | xargs)"
if [ -z "$ZRAM_ALGO" ]; then skip "zram algorithm zstd" "no zram device active"
else eq "zram algorithm zstd" "zstd" "$ZRAM_ALGO"; fi

# -----------------------------------------------------------------
echo "--- greeter and desktop (bugs 9 and 10) ---"
WALL="/usr/share/backgrounds/s6c/ladybird.jpg"
ok "wallpaper installed" test -f "$WALL"

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

# Written by `dms greeter sync`. The greeter loads this fixed path --
# greeterWallpaperPath is only a SOURCE, so without the sync the greeter
# silently keeps its default wallpaper.
OVERRIDE="/var/cache/dms-greeter/greeter_wallpaper_override.jpg"
if [ -r "$OVERRIDE" ]; then pass "greeter override synced" ""
elif have_sudo && sudo test -f "$OVERRIDE"; then pass "greeter override synced" ""
elif have_sudo; then fail "greeter override synced" "missing — did 'dms greeter sync' run?"
else skip "greeter override synced" "needs sudo"; fi

# Upstream DMS passes fallbackIcon:"person", which no icon theme
# provides, so the avatar is an empty circle unless ~/.face exists.
if [ -f "$HOME/.face" ] || [ -f "$HOME/.face.icon" ]; then pass "avatar seeded" "$HOME/.face"
else fail "avatar seeded" "no ~/.face — greeter will show an empty circle"; fi

# Created by `dms greeter sync`. This is the PAM stack the LOCK SCREEN
# authenticates against: without it a correct password is rejected.
ok "pam dankshell created" test -f /etc/pam.d/dankshell

if dpkg -s update-notifier 2>/dev/null | grep -q '^Status: install ok installed'; then
    fail "update-notifier purged" "still installed — tray nag returns"
else pass "update-notifier purged" ""; fi

# -----------------------------------------------------------------
echo "--- security: Oakford root CA (bug 11) ---"
CA="/usr/local/share/ca-certificates/oakford.crt"
# Single source of truth: read the pin out of the installer rather than
# copying it, so the two can never drift apart.
PIN="$(grep -m1 '^OAKFORD_SHA256=' "$INSTALLER" 2>/dev/null | cut -d'"' -f2)"

if [ ! -f "$CA" ]; then
    fail "CA installed" "$CA missing — internal HTTPS will not be trusted"
elif [ -z "$PIN" ]; then
    skip "CA fingerprint pinned" "could not read OAKFORD_SHA256 from the installer"
else
    pass "CA installed" ""
    GOT="$(openssl x509 -in "$CA" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)"
    if [ "$GOT" = "$PIN" ]; then pass "CA fingerprint matches pin" "${GOT:0:23}..."
    else fail "CA fingerprint matches pin" "SECURITY: got ${GOT:-<not a certificate>}"; fi
    # Proves it reached the trust store, not just the staging directory.
    if openssl verify -CApath /etc/ssl/certs "$CA" >/dev/null 2>&1; then
        pass "CA trusted by the system" ""
    else fail "CA trusted by the system" "not in /etc/ssl/certs — did update-ca-certificates run?"; fi
fi

# The S6C profile is now written on every build (the PSK is defaulted in
# the installer), so its ABSENCE is a failure rather than a skip -- a
# student laptop that cannot reach the school network is the single most
# useful thing to catch here. Only an explicit S6C_PSK='' opts out.
NMPROFILE=/etc/NetworkManager/system-connections/S6C.nmconnection
if [ ! -f "$NMPROFILE" ]; then
    fail "wifi profile present" "no S6C profile — the laptop cannot reach school wifi"
elif have_sudo; then
    pass "wifi profile present" ""
    eq "wifi profile is 0600" "600" "$(sudo stat -c '%a' "$NMPROFILE" 2>/dev/null)"
    # The key contains '!' twice; prove it was not mangled by shell quoting.
    if sudo grep -q '^psk=.\+' "$NMPROFILE" 2>/dev/null; then
        pass "wifi PSK non-empty" ""
    else fail "wifi PSK non-empty" "psk= is blank — profile will not authenticate"; fi
else
    pass "wifi profile present" ""
    skip "wifi profile is 0600" "needs sudo"
    skip "wifi PSK non-empty" "needs sudo"
fi

# -----------------------------------------------------------------
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
