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
# The check above only sees SYSTEM units. The xdg-autostart generator puts
# its units in the USER manager, so a failing autostart entry is invisible
# to it -- exactly how nvidia-settings-autostart went unnoticed on
# ubuntu-craig-office until systemctl --user was checked by hand
# (2 Sep 2026). Guarded because there is no user manager to talk to when
# this script is run from a bare SSH session with no login session.
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
echo "--- shell stability ---"
# quickshell crashed on 1 Sep 2026 after dank-lock.sh opened 13,281 IPC
# connections overnight (a 2s poll while locked). It auto-restarted WITHOUT
# reattaching its surfaces, leaving a flat wallpaper-coloured screen with a
# working mouse -- indistinguishable from dead hardware. It ran that way for
# twelve hours because nothing reported it.
if [ -d "$HOME/.cache/quickshell/crashes" ] && \
   [ -n "$(ls -A "$HOME/.cache/quickshell/crashes" 2>/dev/null)" ]; then
    NCRASH="$(find "$HOME/.cache/quickshell/crashes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    fail "quickshell has not crashed" "$NCRASH crash dump(s) in ~/.cache/quickshell/crashes"
else
    pass "quickshell has not crashed" ""
fi

# The lock screen must not be polling. Anything above a few hundred
# connections in a session means something is hammering the IPC socket.
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

# -----------------------------------------------------------------
echo "--- file integrity ---"
# Catches a corrupted install. On 31 Aug 2026 Google Chrome's 141 MB binary
# was silently corrupt on a freshly built machine: same package version, but
# a different md5, and it segfaulted in the dynamic linker on every launch --
# including `--version`. Reinstalling the identical package from Google
# fixed it. apt verifies checksums on DOWNLOAD, so the damage happened
# during or after unpacking, and nothing reported it.
#
# 99% of packages ship md5sums, so this is a reliable detector; it would have
# found that in seconds instead of an afternoon.
#
# CONFFILES ARE EXCLUDED -- dpkg flags them 'c' in column 2. They are the files
# an admin is *expected* to edit, and our own installer edits two of them:
# /etc/greetd/config.toml (section 10) and /etc/default/zramswap (section 14,
# the fix for the zram bug). Counting those reported deliberate configuration
# as corruption, so this check failed on every correctly built machine -- run
# 12 flagged three files, none of them a fault. That is worse than not checking
# at all: a permanently red FAIL teaches people to ignore the report. Chrome's
# corrupted binary was package-owned, not a conffile, so nothing is lost.
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

# -----------------------------------------------------------------
echo "--- node ---"
# Silent failure, found on two machines at once: node v24 was installed and
# completely unreachable because .bashrc pinned NVM_DIR to ~/.config/nvm
# while the niri installer uses nvm's default ~/.nvm. The `[ -s ... ] &&`
# guard failed quietly, so `node --version` said "command not found" on a
# machine that had it. Check a LOGIN shell, which is what a user gets.
NVM_SH=""
for d in "$HOME/.config/nvm" "$HOME/.nvm"; do
    [ -s "$d/nvm.sh" ] && { NVM_SH="$d/nvm.sh"; break; }
done
if [ -z "$NVM_SH" ]; then
    skip "node usable in a login shell" "nvm not installed"
else
    # -lic, not -lc: .bashrc returns early for NON-interactive shells, so a
    # plain `bash -lc` never loads nvm and would fail a working machine.
    NODEV="$(bash -lic 'command -v node >/dev/null 2>&1 && node --version' 2>/dev/null | tail -1)"
    if [ -n "$NODEV" ]; then
        pass "node usable in a login shell" "$NODEV"
    else
        fail "node usable in a login shell" "nvm is at $NVM_SH but node does not resolve — check NVM_DIR in .bashrc"
    fi
fi

# -----------------------------------------------------------------
echo "--- apt hygiene ---"
# A background unattended-upgrades run held the dpkg lock during run 14 and
# killed a post-install hook. Harmless that time; the next race can hit an
# `apt install` instead, and `set -e` then ends the build -- intermittently,
# on some machines only, which is the worst kind to diagnose.
if apt-config dump 2>/dev/null | grep -q 'DPkg::Lock::Timeout'; then
    pass "apt waits for the dpkg lock" "$(apt-config dump 2>/dev/null | awk -F'"' '/DPkg::Lock::Timeout/{print $2 "s"}')"
else
    fail "apt waits for the dpkg lock" "a background apt run can abort an install"
fi

# -----------------------------------------------------------------
echo "--- music ---"
# yt-dlp's failure mode is external: when YouTube changes, every existing copy
# stops working. The build fetches the latest release, but that only pins the
# problem to the build date -- hence the timer. A machine whose timer is not
# running WILL break, silently, some weeks after it was imaged.
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

# Cover art embedding: ffmpeg covers mp3 and opus, AtomicParsley covers m4a/aac.
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

# ASK NETWORKMANAGER, NOT THE FILESYSTEM.
#
# The first version of this checked for
# /etc/NetworkManager/system-connections/S6C.nmconnection. That passes
# straight after an install and then silently becomes false: on real
# hardware (18WessexUbuntu, 31 Aug 2026) the connection was migrated into
# /etc/netplan/90-NM-<uuid>.yaml and regenerated under /run, leaving that
# directory empty while the connection itself worked perfectly. The check
# would have reported FAIL on a healthy machine. nmcli reports the
# connection wherever it is stored.
if nmcli -t -f NAME connection show 2>/dev/null | grep -qx 'S6C'; then
    pass "wifi profile present" "known to NetworkManager"

    # Effective priority, not the value we wrote. The installer sets -10 so
    # a student's OWN network always wins when both are in range; on the
    # machine above it had become 100, equal to the home network, which
    # leaves NetworkManager to choose arbitrarily between them. Checking
    # the file would never have caught that.
    PRIO="$(nmcli -g connection.autoconnect-priority connection show S6C 2>/dev/null | xargs)"
    if [ -z "$PRIO" ]; then
        skip "wifi priority is negative" "could not read autoconnect-priority"
    elif [ "$PRIO" -lt 0 ] 2>/dev/null; then
        pass "wifi priority is negative" "$PRIO"
    else
        fail "wifi priority is negative" "$PRIO — S6C may outrank the user's own network"
    fi

    NMFILE="$(nmcli -g NAME,FILENAME connection show 2>/dev/null | awk -F: '$1=="S6C"{print $2}')"
    case "$NMFILE" in
        /etc/NetworkManager/*)
            if have_sudo; then
                eq "wifi profile is 0600" "600" "$(sudo stat -c '%a' "$NMFILE" 2>/dev/null)"
            else skip "wifi profile is 0600" "needs sudo"; fi ;;
        *)  # netplan-owned: /run copies are root-only and regenerated, so
            # file mode there is not ours to assert.
            skip "wifi profile is 0600" "netplan-owned (${NMFILE:-unknown})" ;;
    esac

    # The key contains '!' twice; prove it was not mangled by shell quoting.
    # `nmcli -s` only reveals a secret to root -- as a normal user it
    # returns empty, which an earlier version of this check read as a blank
    # PSK and failed a perfectly good machine.
    if have_sudo; then
        if sudo nmcli -s -g 802-11-wireless-security.psk connection show S6C 2>/dev/null | grep -q '.'; then
            pass "wifi PSK non-empty" ""
        else
            fail "wifi PSK non-empty" "psk is blank — profile will not authenticate"
        fi
    else
        skip "wifi PSK non-empty" "needs sudo to read the secret"
    fi
else
    fail "wifi profile present" "NetworkManager has no S6C connection"
fi

# -----------------------------------------------------------------
# The clock. `timedatectl set-ntp true` succeeds and reports "NTP service:
# active" even when chrony can never reach a source, so nothing in the install
# output reveals a free-running clock. ubuntu-craig-office had drifted 2m12s
# fast before anyone noticed, and only because Craig compared it to his phone.
#
# 26.04's chrony defaults to NTS sources, which need a key exchange on TCP
# 4460; that port is filtered here, so every source sat at `^?` / Stratum 0.
# See section 13 of the installer.
echo "--- clock ---"
NTP_SYNC="$(timedatectl show --property=NTPSynchronized --value 2>/dev/null)"
case "$NTP_SYNC" in
    yes) pass "clock synchronised" "" ;;
    no)  fail "clock synchronised" "NTP service may claim active while never reaching a source" ;;
    *)   skip "clock synchronised" "timedatectl gave no answer" ;;
esac

# A selected source is the stronger claim: '*' marks the one in use, '+' a
# combined one. `NTPSynchronized` can lag, and this says WHY when it is no.
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

# -----------------------------------------------------------------
# The project's longest-standing red risk was that no real GPU driver had
# ever been exercised -- every run before 2 Sep 2026 was a VM on virgl +
# llvmpipe, which proves the software stack and nothing else. These checks
# assert real hardware acceleration, so the risk cannot silently reopen.
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
        # nouveau and the proprietary driver cannot both drive the card.
        if lsmod | grep -q '^nouveau'; then
            fail "nouveau not loaded" "nouveau is loaded alongside nvidia"
        else
            pass "nouveau not loaded" ""
        fi
        # The NVIDIA modules are DKMS-built and unsigned, so a machine that
        # boots with Secure Boot on will not load them at all.
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

    # The decisive one. niri logs the renderer it settled on; if it could
    # not get a GBM allocator it falls back to software and llvmpipe
    # appears here. That is precisely what happened in every VM run.
    NIRI_LOG="$(journalctl --user -b --no-pager 2>/dev/null | grep -c -i 'llvmpipe\|software rasteriz')"
    if [ -z "$(journalctl --user -b --no-pager 2>/dev/null | head -1)" ]; then
        skip "niri not on llvmpipe" "no user journal available"
    elif [ "${NIRI_LOG:-0}" = "0" ]; then
        pass "niri not on llvmpipe" "hardware renderer"
    else
        fail "niri not on llvmpipe" "software rendering — GBM allocator missing"
    fi
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
