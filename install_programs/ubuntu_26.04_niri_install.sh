#!/usr/bin/env bash
# Ubuntu 26.04 niri / DankMaterialShell student laptop build.
# Usage: ubuntu_26.04_niri_install.sh [--list] [--only IDS] [--skip IDS] [--from ID]
# Env:   TARGET_HOSTNAME  PAPERCUT_SERVER  PAPERCUT_STRICT_SSL  S6C_PSK  S6C_PERSONAL  ALLOW_NO_WIFI
# Rationale for every step: projects/linux-device-build-2026/notes/installer-rationale.md (private workspace).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"
# shellcheck source=lib/oakford-ca.sh
. "$HERE/lib/oakford-ca.sh"
# shellcheck source=lib/node.sh
. "$HERE/lib/node.sh"
# shellcheck source=lib/devtools.sh
. "$HERE/lib/devtools.sh"

SECTIONS=(
    "0:s00_clock:Clock and NTP"
    "1:s01_apt_sources:APT sources"
    "2:s02_kernel_build_tools:Kernel headers and build tools"
    "2a:s02a_oakford_ca:Oakford root CA"
    "3:s03_graphics:Graphics drivers"
    "3b:s03b_rtw89_quirk:Realtek rtw89 wifi quirk"
    "4:s04_desktop_base:Ubuntu desktop base"
    "5:s05_dank_stack:Dank / niri stack"
    "6:s06_packages:Packages from the list"
    "6a:s06a_file_managers:Yazi repo and Nemo defaults"
    "7:s07_chrome:Google Chrome"
    "8:s08_flatpak:Flatpak apps"
    "9:s09_networking:Networking and wifi profile"
    "10:s10_dotfiles:Dotfiles, wallpaper, greeter"
    "11:s11_node:Node.js"
    "12:s12_devtools:yt-dlp, tpm, Claude Code"
    "13:s13_identity:Keyboard, locale, timezone, hostname"
    "14:s14_post_install:zram, sleep, services"
    "15:s15_git_identity:Git identity and SSH key"
    "16:s16_papercut:PaperCut printing"
)

SECURE_BOOT=unknown
BROADCOM_BLOCKED=no
BROADCOM_PRESENT=no
BROADCOM_DRIVER=""
BROADCOM_NEEDS_WL=no
BC_SLOTS=""
OTHER_NET=no
GIT_IDENTITY_SET=yes
S6C_PSK="${S6C_PSK-$S6C_PSK_DEFAULT}"


usage() { sed -n '2,5p' "$0"; }

list_sections() {
    local s
    for s in "${SECTIONS[@]}"; do
        printf '  %-3s %s\n' "${s%%:*}" "${s##*:}"
    done
}

ONLY=""; SKIP=""; FROM=""
while [ $# -gt 0 ]; do
    case "$1" in
        --list) list_sections; exit 0 ;;
        --only) ONLY="${2:?--only needs a list of ids}"; shift ;;
        --skip) SKIP="${2:?--skip needs a list of ids}"; shift ;;
        --from) FROM="${2:?--from needs an id}"; shift ;;
        -h|--help) usage; echo; list_sections; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

in_list() { case ",$2," in *",$1,"*) return 0 ;; esac; return 1; }


secure_boot_action_block() {
    echo ""
    echo "======================================================="
    echo "  ACTION NEEDED - SECURE BOOT IS $(echo "$SECURE_BOOT" | tr '[:lower:]' '[:upper:]')"
    echo "======================================================="
    echo ""
    echo "  Reboot into firmware setup and DISABLE Secure Boot."
    echo "  On a Dell: F2 at the logo, Boot Configuration,"
    echo "  Secure Boot -> Disabled. Other makes vary."
    echo ""
    echo "  THIS DOES NOT MEAN REINSTALLING. It is a firmware setting only:"
    echo "    * the system boots exactly as it does now"
    if [ -r /etc/crypttab ] && grep -q "tpm2-device=" /etc/crypttab 2>/dev/null; then
        echo "    * !! THIS DISK IS TPM-SEALED. Changing Secure Boot alters PCR 7"
        echo "      and the automatic unlock WILL fail. HAVE YOUR RECOVERY KEY."
    else
        echo "    * your disk encryption passphrase is UNCHANGED"
    fi
    echo "    * nothing on disk is touched"
    echo ""
    echo "  Why it matters on this machine:"
    if [ "$BROADCOM_BLOCKED" = yes ]; then
        echo "    * THIS MACHINE HAS BROADCOM WIFI and its driver was SKIPPED."
        echo "      Wifi will not work until you do this and re-run the script."
    fi
    echo "    * unsigned DKMS drivers (Broadcom wifi, NVIDIA) cannot load"
    echo "    * hibernation is refused by the locked-down kernel"
    echo ""
    echo "  Then re-run this script. It is safe to run twice."
    echo "======================================================="
}

preflight_secure_boot() {
    SECURE_BOOT="$(secure_boot_state)"
    case "$SECURE_BOOT" in
        on)          log "Secure Boot: ENABLED - unsigned DKMS modules will be refused. See the end of this run." ;;
        off)         log "Secure Boot: disabled." ;;
        unsupported) log "Secure Boot: not supported by this firmware." ;;
        *)           log "Secure Boot: could not be determined - treating it as possibly on." ;;
    esac
}

preflight_network() {
    local slot d ifp n pci isbc
    if have_cmd lspci; then
        for slot in $(lspci -nn 2>/dev/null | grep -iE "network|wireless" | grep -i broadcom | cut -d' ' -f1 || true); do
            BROADCOM_PRESENT=yes
            BC_SLOTS="$BC_SLOTS $slot"
            d="$(lspci -nnks "$slot" 2>/dev/null | sed -n 's/.*Kernel driver in use: *//p' | head -1 | xargs || true)"
            [ -n "$d" ] && BROADCOM_DRIVER="$d"
        done
    fi
    if [ "$BROADCOM_PRESENT" = yes ]; then
        case "$BROADCOM_DRIVER" in
            brcmfmac|b43|brcmsmac|bcma|ssb) log "Broadcom wireless on $BROADCOM_DRIVER (in-kernel)." ;;
            wl) log "Broadcom wireless already on wl." ;;
            "") BROADCOM_NEEDS_WL=yes ;;
            *)  log "Broadcom wireless on $BROADCOM_DRIVER." ;;
        esac
    fi
    for ifp in /sys/class/net/*; do
        n="$(basename "$ifp")"
        [ "$n" = lo ] && continue
        [ "$(cat "$ifp/carrier" 2>/dev/null)" = "1" ] || continue
        pci="$(basename "$(readlink -f "$ifp/device" 2>/dev/null)" 2>/dev/null)"
        isbc=no
        for slot in $BC_SLOTS; do
            case "$pci" in *"$slot") isbc=yes ;; esac
        done
        [ "$isbc" = yes ] && continue
        OTHER_NET=yes
    done

    if [ "$BROADCOM_NEEDS_WL" = yes ] && { [ "$SECURE_BOOT" = on ] || [ "$SECURE_BOOT" = unknown ]; }; then
        BROADCOM_BLOCKED=yes
        if [ "$OTHER_NET" = no ] && [ -z "${ALLOW_NO_WIFI:-}" ]; then
            secure_boot_action_block
            echo ""
            echo "STOPPING BEFORE ANY CHANGES ARE MADE."
            echo "  This machine's only wireless is Broadcom, nothing is driving it, and"
            echo "  Secure Boot will not let the driver load. Building now would produce"
            echo "  a machine with NO network at all."
            echo "  Either disable Secure Boot as above, or attach a wired, tethered or"
            echo "  USB-dongle connection, then re-run. To build anyway:"
            echo "      ALLOW_NO_WIFI=1 $0"
            exit 1
        fi
        echo ""
        log "NOTE: Broadcom wireless here needs the unsigned wl module, which Secure Boot"
        log "      will not load. This machine will have no wifi until Secure Boot is off."
        if [ "$OTHER_NET" = yes ]; then
            log "      The build continues over the connection you are on."
        else
            log "      ALLOW_NO_WIFI is set and there is no other connection."
        fi
        secure_boot_action_block
    fi
}


s00_clock() {
    sudo timedatectl set-ntp true
    if have_cmd chronyd && [ -d /etc/chrony ]; then
        log "Letting chrony select unauthenticated sources (NTS is unreachable here)..."
        write_root_file /etc/chrony/conf.d/50-s6c-authselectmode.conf <<'CONF'
authselectmode ignore
CONF
        log "Adding plain-NTP sources (NTS needs TCP 4460, which is filtered here)..."
        write_root_file /etc/chrony/sources.d/50-s6c-plain-ntp.sources <<'CONF'
pool 0.pool.ntp.org iburst maxsources 2 prefer
pool 1.pool.ntp.org iburst maxsources 2 prefer
pool ntp.ubuntu.com iburst maxsources 2 prefer
CONF
        log "Looking for a domain controller to use as a time fallback..."
        local domains hosts d
        domains="$(resolvectl domain 2>/dev/null \
            | sed -n 's/^Link [0-9]* ([^)]*): //p' \
            | tr ' ' '\n' | sed '/^$/d;/^~/d' | sort -u || true)"
        hosts=""
        for d in $domains; do
            hosts="$hosts$(resolvectl --type=SRV query "_ldap._tcp.$d" 2>/dev/null \
                | sed -n 's/.* IN SRV [0-9]* [0-9]* [0-9]* \([^ ]*\).*/\1/p' \
                | sed 's/\.$//' | sed '/^$/d' || true)
"
        done
        hosts="$(printf '%s' "$hosts" | sed '/^$/d' | sort -u || true)"
        if [ -n "$hosts" ]; then
            printf '%s\n' "$hosts" | sed 's/^/server /; s/$/ iburst/' \
                | write_root_file /etc/chrony/sources.d/60-s6c-dc-fallback.sources
            log "   fallback: $(printf '%s' "$hosts" | tr '\n' ' ')"
        else
            log "   no domain controller found (not on a domain) - public pools only"
        fi
        sudo systemctl restart chrony 2>/dev/null || sudo systemctl restart chronyd 2>/dev/null || warn "could not restart chrony."
        if wait_for_ntp 20; then
            log "   clock synchronised, now $(date '+%H:%M:%S %Z')"
        else
            warn "clock still not synchronised - check 'chronyc sources -v'."
        fi
    else
        log "chrony not installed - relying on systemd-timesyncd for time sync."
        if wait_for_ntp 20; then
            log "   clock synchronised, now $(date '+%H:%M:%S %Z')"
        else
            warn "clock not synchronised and chrony absent - check 'timedatectl status'."
        fi
    fi
}

s01_apt_sources() {
    sudo rm -f /etc/apt/apt.conf.d/99no-recommends
    echo 'DPkg::Lock::Timeout "600";' | write_root_file /etc/apt/apt.conf.d/99lock-timeout
    sudo add-apt-repository -y restricted
    sudo add-apt-repository -y multiverse
    apt_update
}

s02_kernel_build_tools() {
    apt_install \
        linux-generic-hwe-26.04 \
        linux-headers-generic-hwe-26.04 \
        "linux-headers-$(uname -r)" \
        build-essential dkms ubuntu-drivers-common pciutils usbutils \
        software-properties-common libnss3-tools git curl wget stow
}

s02a_oakford_ca() {
    install_oakford_ca
}

s03_graphics() {
    detect_gpu
    log "Detected graphics:"
    printf '%s\n' "${GPU_INFO:-<none>}" | sed 's/^/    /'
    apt_install mesa-va-drivers mesa-vulkan-drivers libva2 vainfo vulkan-tools

    if gpu_is nvidia; then
        log "NVIDIA GPU detected - installing drivers..."
        sudo ubuntu-drivers install --include-dkms || sudo ubuntu-drivers autoinstall \
            || warn "NVIDIA driver install failed - check 'ubuntu-drivers devices'."
        write_root_file /etc/modprobe.d/blacklist-nouveau.conf <<'CONF'
blacklist nouveau
options nouveau modeset=0
CONF
        write_root_file /etc/modprobe.d/nvidia-drm-modeset.conf <<'CONF'
options nvidia_drm modeset=1
CONF
        sudo dracut -f
    fi
    if gpu_is intel; then
        log "Intel GPU detected - installing VA-API drivers..."
        apt_install intel-media-va-driver-non-free || apt_install intel-media-va-driver \
            || warn "Intel VA-API driver not installed - video decode will be CPU-bound."
    fi
    if gpu_is "amd|radeon|advanced micro devices"; then
        log "AMD GPU detected - ensuring firmware and Vulkan..."
        apt_install_soft linux-firmware libdrm-amdgpu1
    fi
}

s03b_rtw89_quirk() {
    has_realtek_rtw89_hw || return 0
    log "Realtek rtw89 wifi detected - applying the ASPM/power-save quirk..."
    write_root_file /etc/modprobe.d/rtw89-quirks.conf <<'CONF'
options rtw89_pci disable_aspm_l1=y disable_aspm_l1ss=y disable_clkreq=y
options rtw89_core disable_ps_mode=y
CONF
    sudo update-initramfs -u >/dev/null 2>&1 || warn "initramfs rebuild failed - the quirk still applies after the next reboot."
}

s04_desktop_base() {
    write_root_file /etc/apt/preferences.d/no-thunderbird.pref <<'CONF'
Package: thunderbird
Pin: release *
Pin-Priority: -1
CONF
    sudo apt-get install -y --install-recommends ubuntu-desktop

    if systemctl list-unit-files gdm3.service >/dev/null 2>&1; then
        log "Disabling gdm3 in favour of greetd..."
        sudo systemctl disable gdm3 2>/dev/null || true
    fi

    if dpkg -l update-notifier 2>/dev/null | grep -qE "^(ii|rc)"; then
        log "Replacing update-notifier with gnome-package-updater..."
        sudo apt-get purge -y update-notifier || warn "could not purge update-notifier."
    fi

    log "Masking X11-only autostart entries that fail under niri..."
    local entry src name
    mkdir -p "$HOME/.config/autostart"
    for entry in nvidia-settings-autostart blueman; do
        src="/etc/xdg/autostart/$entry.desktop"
        [ -f "$src" ] || continue
        name="$(grep -m1 '^Name=' "$src" | cut -d= -f2- || true)"
        cat > "$HOME/.config/autostart/$entry.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=${name:-$entry}
Exec=/bin/true
Hidden=true
DESKTOP
        log "  masked $entry"
    done

    log "Disabling apport crash-report upload (keeping local collection)..."
    local u
    for u in apport-autoreport.path apport-autoreport.timer whoopsie.path; do
        sudo systemctl disable --now "$u" 2>/dev/null || true
    done
    sudo systemctl reset-failed apport-autoreport.service 2>/dev/null || true
}

s05_dank_stack() {
    local attempt
    for attempt in 1 2 3; do
        if curl -fsSL "$DANKINSTALL_URL" | sh -s -- \
            --compositor niri --term alacritty --include-deps dms-greeter \
            --danksearch --dankcalendar --yes; then
            return 0
        fi
        warn "dankinstall attempt $attempt of 3 failed (Launchpad or the PPA mirror is often the cause)."
        [ "$attempt" -lt 3 ] && sleep 60
    done
    die "dankinstall failed three times - re-run this script later."
}

s06_packages() {
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | sudo debconf-set-selections
    apt_install_list "$PKG_LIST"
}

s06a_file_managers() {
    if wget -q -O - "$YAZI_KEY_URL" | sudo tee "$YAZI_KEYRING" >/dev/null && [ -s "$YAZI_KEYRING" ]; then
        echo "$YAZI_REPO_LINE" | write_root_file /etc/apt/sources.list.d/yazi.list
        apt_update
        apt_install_soft yazi
    else
        warn "could not fetch the Yazi signing key - yazi not installed."
    fi

    if pkg_installed pcmanfm; then
        sudo apt-get purge -y pcmanfm || warn "could not remove pcmanfm."
    fi
    if pkg_installed nemo; then
        xdg-mime default nemo.desktop inode/directory || warn "could not make nemo the directory handler."
        gsettings set org.cinnamon.desktop.default-applications.terminal exec alacritty 2>/dev/null \
            || warn "could not point Nemo's 'Open in Terminal' at alacritty."
        gsettings set org.nemo.desktop show-desktop-icons false 2>/dev/null \
            || warn "could not turn off Nemo desktop icons."
    else
        warn "nemo is not installed - run section 6 first."
    fi

    if pkg_installed nautilus; then
        mkdir -p "$HOME/.local/share/applications"
        cat > "$HOME/.local/share/applications/org.gnome.Nautilus.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Files
Exec=nautilus --new-window %U
NoDisplay=true
DESKTOP
    fi
}

s07_chrome() {
    if ! wget -q -O - "$CHROME_KEY_URL" | sudo gpg --dearmor --yes -o "$CHROME_KEYRING"; then
        warn "could not fetch Google's signing key - Chrome not installed."
        return 0
    fi
    echo "$CHROME_REPO_LINE" | write_root_file /etc/apt/sources.list.d/google-chrome.list
    apt_update
    apt_install_soft google-chrome-stable
}

s08_flatpak() {
    apt_install flatpak gnome-software-plugin-flatpak
    sudo flatpak remote-add --if-not-exists flathub "$FLATHUB_URL"
    local apps="io.bassi.Amberol"
    if [ -n "${S6C_PERSONAL:-}" ]; then
        log "S6C_PERSONAL set - including Craig's personal flatpaks."
        apps="$apps com.bambulab.BambuStudio org.freecad.FreeCAD"
    fi
    # shellcheck disable=SC2086
    sudo flatpak install -y flathub $apps || warn "flatpak install failed - retry after reboot."
}

s09_networking() {
    apt_install linux-firmware wpasupplicant iw rfkill

    if has_broadcom_wifi; then
        if [ "$SECURE_BOOT" = on ] || [ "$SECURE_BOOT" = unknown ]; then
            warn "Broadcom wireless found, but Secure Boot is $SECURE_BOOT. broadcom-sta-dkms is unsigned,"
            warn "would blacklist the in-kernel drivers, and cannot load. Skipped. Disable Secure Boot and re-run."
            BROADCOM_BLOCKED=yes
        else
            log "Broadcom wireless detected - installing broadcom-sta-dkms..."
            apt_install_soft broadcom-sta-dkms
        fi
    else
        log "No Broadcom wireless detected - skipping broadcom-sta-dkms."
    fi

    sudo rfkill unblock wifi
    sudo mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak 2>/dev/null || true
    write_root_file /etc/netplan/01-network-manager-all.yaml 0600 <<'CONF'
network:
  version: 2
  renderer: NetworkManager
CONF
    sudo netplan apply
    log "Waiting for the network to come back after netplan apply..."
    nm-online -q --timeout=60 || warn "network not online 60s after netplan apply; continuing anyway."

    if [ -z "$S6C_PSK" ]; then
        log "S6C_PSK empty - skipping the school wifi profile."
        return 0
    fi

    local existing uuid prio
    existing="$(nm_wifi_uuids_for_ssid "$S6C_SSID" | xargs || true)"
    if [ -n "$existing" ]; then
        for uuid in $existing; do
            log "Existing $S6C_SSID profile $uuid - setting autoconnect-priority=-10 in place."
            sudo nmcli connection modify "$uuid" connection.autoconnect yes connection.autoconnect-priority -10 \
                || warn "could not set the priority on $S6C_SSID profile $uuid."
        done
    else
        write_root_file "/etc/NetworkManager/system-connections/$S6C_SSID.nmconnection" 0600 <<CONF
[connection]
id=$S6C_SSID
type=wifi
autoconnect=true
autoconnect-priority=-10

[wifi]
mode=infrastructure
ssid=$S6C_SSID

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=$S6C_PSK

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=stable-privacy
CONF
        sudo nmcli connection reload 2>/dev/null || warn "'nmcli connection reload' failed - the $S6C_SSID profile will load on the next reboot."
        log "School wifi profile installed."
    fi

    for uuid in $(nm_wifi_uuids_for_ssid "$S6C_SSID"); do
        prio="$(nmcli -g connection.autoconnect-priority connection show "$uuid" 2>/dev/null | xargs || true)"
        case "${prio:-?}" in
            -*) ;;
            *)  warn "$S6C_SSID profile $uuid has autoconnect-priority '${prio:-unreadable}'; it may outrank the user's own network." ;;
        esac
    done
}

s10_dotfiles() {
    local d f conflicts src
    for d in niri DankMaterialShell danksearch alacritty; do
        if [ -e "$HOME/.config/$d" ] && [ ! -L "$HOME/.config/$d" ]; then
            log "Removing dankinstall's default $d config (repo version wins)..."
            rm -rf "$HOME/.config/$d"
        fi
    done

    cd "$DOTFILES_DIR"
    while IFS= read -r f; do
        if [ -f "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
            log "Moving aside default $f (repo version wins)..."
            mv "$HOME/$f" "$HOME/$f.pre-stow.bak"
        fi
    done < <(find . -maxdepth 1 -type f -name '.*' -printf '%f\n')

    conflicts="$(stow -n . 2>&1 | grep -v 'in simulation mode' || true)"
    if [ -n "$conflicts" ]; then
        warn "stow reported conflicts (dry run):"
        printf '%s\n' "$conflicts" | sed 's/^/    /' >&2
        warn "Resolve the above, then run 'stow .' from $DOTFILES_DIR manually."
    else
        stow .
        log "Dotfiles stowed."
    fi
    cd "$HERE"
    fc-cache -f

    src="$HOME/.local/share/backgrounds/0288.jpg"
    if [ -f "$src" ]; then
        if sudo install -d -m 0755 "$(dirname "$S6C_WALLPAPER")" && sudo install -m 0644 "$src" "$S6C_WALLPAPER"; then
            log "Default wallpaper installed to $S6C_WALLPAPER"
        else
            warn "could not install the default wallpaper system-wide."
        fi
        json_set_default "$HOME/.local/state/DankMaterialShell/session.json" wallpaperPath "$S6C_WALLPAPER" \
            || warn "could not seed the desktop wallpaper."
    else
        warn "$src not found after stow - skipping wallpaper setup."
    fi

    src="$HOME/.local/share/s6c/avatar-default.png"
    if [ ! -f "$HOME/.face" ] && [ ! -f "$HOME/.face.icon" ]; then
        if [ -f "$src" ]; then
            if cp "$src" "$HOME/.face" && chmod 0644 "$HOME/.face"; then
                log "Seeded default user avatar at ~/.face"
            else
                warn "could not seed the default avatar."
            fi
        else
            warn "$src not found after stow - skipping default avatar."
        fi
    else
        log "User avatar already present - left alone."
    fi

    if have_cmd dms-greeter || have_cmd dms; then
        log "Syncing settings, theme and wallpaper into the greeter..."
        local sync=(dms greeter sync)
        have_cmd dms-greeter && sync=(dms-greeter sync)
        if DMS_PRIVESC=sudo "${sync[@]}"; then
            log "Greeter synced."
            dms auth resolve-lock --quiet >/dev/null 2>&1 || warn "'dms auth resolve-lock' failed - the lock screen builds its PAM stack on first use instead."
        else
            warn "greeter sync failed - the greeter starts but with default colours and no wallpaper. Re-run '${sync[*]}' by hand."
        fi
    else
        warn "neither dms-greeter nor dms is on PATH - skipping greeter sync."
    fi
}

s11_node() {
    install_node_lts
}

s12_devtools() {
    install_yt_dlp
    install_yt_dlp_timer
    install_tpm
    install_claude_code
}

s13_identity() {
    write_root_file /etc/default/keyboard <<'CONF'
XKBMODEL="pc105"
XKBLAYOUT="gb"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
CONF
    sudo debconf-set-selections <<'CONF' || true
keyboard-configuration keyboard-configuration/modelcode string pc105
keyboard-configuration keyboard-configuration/layoutcode string gb
CONF
    sudo setupcon --save || true
    sudo systemctl try-restart systemd-localed.service || true
    sudo localectl set-locale LANG=en_GB.UTF-8
    sudo timedatectl set-timezone Europe/London

    local current
    current="$(hostname)"
    if [ -z "${TARGET_HOSTNAME:-}" ] && [ -t 0 ]; then
        read -r -p "Hostname for this machine [$current]: " TARGET_HOSTNAME
    fi
    if [ -n "${TARGET_HOSTNAME:-}" ] && [ "$TARGET_HOSTNAME" != "$current" ]; then
        if valid_hostname "$TARGET_HOSTNAME"; then
            log "Setting hostname to $TARGET_HOSTNAME ..."
            sudo hostnamectl set-hostname "$TARGET_HOSTNAME"
            sudo sed -i "s/\b${current}\b/${TARGET_HOSTNAME}/g" /etc/hosts
        else
            warn "'$TARGET_HOSTNAME' is not a valid hostname - keeping $current."
        fi
    fi
}

s14_post_install() {
    xdg-user-dirs-update

    if [ -f /etc/default/zramswap ]; then
        sudo sed -i 's/^ALGO=.*/ALGO=zstd/'   /etc/default/zramswap
        sudo sed -i 's/^PERCENT=.*/PERCENT=50/' /etc/default/zramswap
        sudo systemctl enable zramswap.service || true
        sudo systemctl restart zramswap.service || warn "zramswap did not start - check 'zramctl' after reboot."
    else
        warn "/etc/default/zramswap missing - is zram-tools installed?"
    fi

    local grub=/etc/default/grub
    if [ ! -r /sys/power/mem_sleep ]; then
        log "No /sys/power/mem_sleep - skipping deep sleep configuration."
    elif ! grep -qw deep /sys/power/mem_sleep; then
        log "Firmware advertises no S3 (mem_sleep: $(cat /sys/power/mem_sleep)) - leaving suspend at s2idle."
    elif [ ! -f "$grub" ]; then
        warn "S3 is available but $grub is missing - cannot make it the default."
    elif grep -q 'mem_sleep_default=deep' "$grub"; then
        log "Deep sleep is already the default in $grub."
    else
        log "Firmware offers S3 - making deep sleep the default."
        sudo sed -i -E 's/[[:space:]]*mem_sleep_default=[^ "]*//g' "$grub" || true
        sudo sed -i -E 's|^(GRUB_CMDLINE_LINUX_DEFAULT=")(.*)"|\1\2 mem_sleep_default=deep"|' "$grub" || true
        sudo sed -i -E 's|^(GRUB_CMDLINE_LINUX_DEFAULT=")[[:space:]]+|\1|' "$grub" || true
        if grep -q 'mem_sleep_default=deep' "$grub"; then
            sudo update-grub || warn "update-grub failed - deep sleep applies at the next successful update-grub."
        else
            warn "could not add mem_sleep_default=deep to $grub - suspend stays s2idle."
        fi
    fi

    bash "$HERE/setup-suspend.sh" || warn "setup-suspend.sh failed - check suspend/resume by hand."

    sudo systemctl enable udisks2
    sudo systemctl enable cups         || true
    sudo systemctl enable avahi-daemon || true
    sudo systemctl enable greetd
    sudo systemctl set-default graphical.target
}

s15_git_identity() {
    local old new
    if git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null | grep -q '^git@github.com:'; then
        old="$(git -C "$DOTFILES_DIR" remote get-url origin)"
        new="https://github.com/${old#git@github.com:}"
        log "Rewriting origin to HTTPS so pushes use this student's own credentials: $old -> $new"
        git -C "$DOTFILES_DIR" remote set-url origin "$new"
    fi
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        log "Generating a per-machine SSH key..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -N "" -C "$(id -un)@$(hostname)" -f "$HOME/.ssh/id_ed25519" >/dev/null
    fi
    [ -n "$(git config --global user.email 2>/dev/null || true)" ] || GIT_IDENTITY_SET=no
}

s16_papercut() {
    if [ -z "${PAPERCUT_SERVER:-}" ] && [ -t 0 ]; then
        echo ""
        echo "PaperCut Print Deploy server URL, e.g. https://print.school.example:9174"
        read -r -p "  (blank to skip printer setup): " PAPERCUT_SERVER
    fi
    if [ -z "${PAPERCUT_SERVER:-}" ]; then
        log "No PaperCut server given - skipping printer setup. Students can add printers with system-config-printer."
        return 0
    fi
    PAPERCUT_SERVER="${PAPERCUT_SERVER%/}"

    log "Installing Print Deploy prerequisites..."
    apt_install cups cups-ipp-utils libwebkit2gtk-4.1-0 avahi-daemon avahi-utils libnss-mdns
    write_root_file /etc/papercut-print-deploy-client/client.conf.toml <<CONF
ServerBaseURL = "${PAPERCUT_SERVER}"
StrictSSLCheckingEnabled = ${PAPERCUT_STRICT_SSL:-true}
HTTPProxy = ""
CONF

    local tmp deb
    tmp="$(mktemp -d)"
    if ( cd "$tmp" && curl -fL -OJ "${PAPERCUT_SERVER}/print-deploy/client/linux-debian" ); then
        deb="$(find "$tmp" -maxdepth 1 -name '*.deb' | head -1)"
        if [ -n "$deb" ]; then
            log "Installing $(basename "$deb") ..."
            sudo SKIP_DPM=true dpkg -i --force-confdef "$deb" || {
                log "dpkg reported unmet dependencies - resolving..."
                sudo apt-get -y -f install
            }
            log "Print Deploy installed. Queues appear after first login. Logs: /opt/PaperCutPrintDeployClient/data/logs/install.log"
        else
            warn "download produced no .deb - skipping Print Deploy."
        fi
    else
        warn "could not download the Print Deploy client from ${PAPERCUT_SERVER}/print-deploy/client/linux-debian"
        warn "Check the host and port (9174 vs the App Server's 9192/443), then install by hand from ${PAPERCUT_SERVER}/print-deploy/client-setup/linux.html"
    fi
    rm -rf "$tmp"
}


print_summary() {
    echo ""
    echo "-------------------------------------------------------"
    echo "SETUP COMPLETE."
    echo ""
    echo "Reboot to enter Niri. At the greeter you can also pick the GNOME session."
    echo ""
    echo "For students:"
    echo "  * Home wifi:  DMS control centre, or nm-connection-editor"
    echo "  * VPN:        create the profile in nm-connection-editor, then toggle it from the DMS bar"
    if [ -n "${PAPERCUT_SERVER:-}" ]; then
        echo "  * Printers:   school queues arrive via PaperCut Print Deploy after first login; home printers: system-config-printer"
    else
        echo "  * Printers:   system-config-printer"
    fi
    echo ""
    echo "  GITHUB - set up your OWN access. Never share a private key:"
    if [ "$GIT_IDENTITY_SET" = no ]; then
        echo "    1. git config --global user.name 'Your Name'"
        echo "       git config --global user.email 'you@example.com'"
    fi
    echo "    2. gh auth login   (GitHub.com -> HTTPS -> browser)"
    echo "       or add this machine's public key at github.com/settings/keys:"
    [ -f "$HOME/.ssh/id_ed25519.pub" ] && sed 's/^/         /' "$HOME/.ssh/id_ed25519.pub"
    echo ""
    echo "  Mod+Alt+L locks the screen (dank-lock.sh)."
    echo "  NVIDIA only: watch for the MOK enrolment screen on first boot."
    echo "-------------------------------------------------------"
    if [ "$SECURE_BOOT" = on ] || [ "$SECURE_BOOT" = unknown ]; then
        secure_boot_action_block
    fi
}


main() {
    require_not_root
    sudo_keepalive
    preflight_secure_boot
    preflight_network

    local s id fn title started=no
    [ -z "$FROM" ] && started=yes
    for s in "${SECTIONS[@]}"; do
        id="${s%%:*}"; title="${s##*:}"; fn="${s#*:}"; fn="${fn%%:*}"
        [ "$id" = "$FROM" ] && started=yes
        [ "$started" = yes ] || continue
        if [ -n "$ONLY" ] && ! in_list "$id" "$ONLY"; then continue; fi
        if [ -n "$SKIP" ] && in_list "$id" "$SKIP"; then log "Skipping $id: $title"; continue; fi
        section "$id. $title"
        "$fn"
    done
    print_summary
}

main
