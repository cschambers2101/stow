#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
[ -n "${S6C_COMMON_LOADED:-}" ] && return 0
S6C_COMMON_LOADED=1

[ -n "${S6C_NO_STRICT:-}" ] || set -Eeuo pipefail

S6C_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(dirname "$S6C_LIB_DIR")"
DOTFILES_DIR="$(dirname "$INSTALL_DIR")"
PKG_LIST="$INSTALL_DIR/niri_programs_to_install.txt"

OAKFORD_CA_URL="https://oakfordhelp.co.uk/oakford.crt"
OAKFORD_CA_PATH="/usr/local/share/ca-certificates/oakford.crt"
OAKFORD_SHA256="70:0D:4D:BA:40:46:29:25:31:7F:9E:C3:33:D5:D7:52:D4:C6:B5:C9:A1:BD:7B:27:BA:B7:12:5C:9C:13:C5:A3"
S6C_SSID="S6C"
S6C_PSK_DEFAULT='!BY0D!S6C'
NVM_VERSION="v0.40.3"
NVM_HOME="$HOME/.nvm"
YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
TPM_REPO="https://github.com/tmux-plugins/tpm"
CLAUDE_INSTALL_URL="https://claude.ai/install.sh"
CHROME_KEY_URL="https://dl.google.com/linux/linux_signing_key.pub"
CHROME_KEYRING="/usr/share/keyrings/google-chrome-keyring.gpg"
CHROME_REPO_LINE="deb [arch=amd64 signed-by=$CHROME_KEYRING] http://dl.google.com/linux/chrome/deb/ stable main"
DANKINSTALL_URL="https://install.danklinux.com"
FLATHUB_URL="https://flathub.org/repo/flathub.flatpakrepo"
S6C_WALLPAPER="/usr/share/backgrounds/s6c/ladybird.jpg"

if [ -t 2 ]; then
    C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_B=$'\033[34m'; C_0=$'\033[0m'
else
    C_R=""; C_G=""; C_Y=""; C_B=""; C_0=""
fi

log()     { printf '%s\n' "$*"; }
section() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }
warn()    { printf '%sWARNING:%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()     { printf '%sERROR:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

on_error() {
    local rc=$?
    printf '%sERROR:%s %s:%s: "%s" exited %s\n' "$C_R" "$C_0" \
        "${BASH_SOURCE[1]:-?}" "${BASH_LINENO[0]:-?}" "$BASH_COMMAND" "$rc" >&2
}
[ -n "${S6C_NO_STRICT:-}" ] || trap on_error ERR

S6C_CLEANUP=()
add_cleanup() { S6C_CLEANUP+=("$1"); }
run_cleanup() {
    local c
    for c in ${S6C_CLEANUP[@]+"${S6C_CLEANUP[@]}"}; do eval "$c" || true; done
}
trap run_cleanup EXIT

have_cmd() { command -v "$1" >/dev/null 2>&1; }
pkg_installed() { dpkg -s "$1" 2>/dev/null | grep -q '^Status: install ok installed'; }
is_root() { [ "$(id -u)" -eq 0 ]; }
require_not_root() { is_root && die "run this as your normal user, not root."; return 0; }
require_cmds() { local c; for c in "$@"; do have_cmd "$c" || die "$c is required but not installed."; done; }

sudo_keepalive() {
    sudo true
    while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
    add_cleanup "kill $! 2>/dev/null"
}

apt_update() {
    sudo apt-get update || warn "apt update reported an error (usually a post-invoke hook, not the index) - continuing."
}
apt_install() { sudo apt-get install -y "$@"; }
apt_install_soft() { sudo apt-get install -y "$@" || warn "could not install: $*"; }

apt_install_list() {
    local list="$1"
    [ -f "$list" ] || die "$list not found."
    if ! grep -vE '^\s*(#|$)' "$list" | awk '{print $1}' | xargs -r sudo apt-get install -y; then
        warn "bulk install failed - retrying one package at a time to isolate the bad one."
        grep -vE '^\s*(#|$)' "$list" | awk '{print $1}' | xargs -r -n1 sudo apt-get install -y || true
    fi
}

write_root_file() {
    local path="$1" mode="${2:-0644}"
    sudo install -d -m 0755 "$(dirname "$path")"
    sudo tee "$path" >/dev/null
    sudo chmod "$mode" "$path"
}

json_set_default() {
    local file="$1" key="$2" value="$3"
    mkdir -p "$(dirname "$file")"
    python3 - "$file" "$key" "$value" <<'PYEOF'
import json, os, sys
path, key, value = sys.argv[1:4]
try:
    with open(path) as fh:
        data = json.load(fh)
except (FileNotFoundError, ValueError):
    data = {}
if not isinstance(data, dict):
    sys.exit(0)
if data.get(key):
    print(f"   {key} already set ({data[key]}) - left alone")
    sys.exit(0)
if value in ("true", "false"):
    value = value == "true"
data[key] = value
tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(data, fh, indent=2)
os.replace(tmp, path)
print(f"   {key} set to {value}")
PYEOF
}

detect_gpu() { GPU_INFO="$(lspci -nn 2>/dev/null | grep -iE 'vga|3d controller|display controller' || true)"; }
gpu_is() { printf '%s' "${GPU_INFO:-}" | grep -qiE "$1"; }

secure_boot_state() {
    local state=unknown
    if have_cmd mokutil; then
        case "$(mokutil --sb-state 2>&1 || true)" in
            *"SecureBoot enabled"*)  state=on ;;
            *"SecureBoot disabled"*) state=off ;;
            *"doesn't support"*|*"not supported"*) state=unsupported ;;
        esac
    fi
    if [ "$state" = unknown ] && [ -r /sys/kernel/security/lockdown ]; then
        case "$(cat /sys/kernel/security/lockdown 2>/dev/null || true)" in
            *"[none]"*)                            state=off ;;
            *"[integrity]"*|*"[confidentiality]"*) state=on ;;
        esac
    fi
    printf '%s' "$state"
}

has_broadcom_wifi() { lspci -nn 2>/dev/null | grep -iE "network|wireless" | grep -qi broadcom; }
has_realtek_rtw89_hw() { lspci -nn 2>/dev/null | grep -qiE "RTL885[0-9]|Realtek.*802\\.11|802\\.11.*Realtek"; }
has_rtw89() {
    local d
    for d in /sys/bus/*/drivers/rtw89_*/; do
        [ -d "$d" ] || continue
        compgen -G "${d}[0-9]*" >/dev/null 2>&1 && return 0
    done
    lspci -k 2>/dev/null | grep -q 'Kernel driver in use: rtw89_'
}

nm_wifi_uuids_for_ssid() {
    local ssid="$1" uuid type
    while IFS=: read -r uuid type; do
        [ "$type" = "802-11-wireless" ] || continue
        [ "$(nmcli -g 802-11-wireless.ssid connection show "$uuid" 2>/dev/null)" = "$ssid" ] || continue
        printf '%s\n' "$uuid"
    done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null || true)
}

ntp_synced() { timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q '^yes$'; }
wait_for_ntp() {
    for _ in $(seq 1 "${1:-20}"); do
        ntp_synced && return 0
        sleep 1
    done
    return 1
}

valid_hostname() { printf '%s' "$1" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'; }
