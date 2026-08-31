#!/bin/bash

# =================================================================
# UBUNTU 26.04 LTS — NIRI / DANK STUDENT LAPTOP SETUP
# Run this script from install_programs/ after cloning the dotfiles repo.
# Requires: vanilla Ubuntu 26.04, Secure Boot DISABLED, network up.
#
# Do NOT run as root — dankinstall refuses to run as uid 0.
# =================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
PKG_LIST="$SCRIPT_DIR/niri_programs_to_install.txt"

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: run this as your normal user, not root. dankinstall refuses uid 0."
    exit 1
fi

# Cache sudo credentials up front: dankinstall's headless mode requires it,
# and it keeps the rest of the run unattended.
#
# `sudo true`, NOT `sudo -v`. Ubuntu 26.04 ships sudo-rs, whose -v always
# demands interactive authentication even when policy grants NOPASSWD --
# so `sudo -v` can never be satisfied in an unattended run. `sudo true`
# caches the timestamp identically and works in both cases: it prompts
# once for a human, and passes silently under NOPASSWD.
sudo true
# Keep the sudo timestamp alive for the whole run.
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT

# -----------------------------------------------------------------
# 1. LOCK DOWN APT (no recommended/suggested packages)
#    NOTE: section 4 deliberately overrides this for ubuntu-desktop.
# -----------------------------------------------------------------
sudo mkdir -p /etc/apt/apt.conf.d
echo 'APT::Install-Recommends "false";' | sudo tee /etc/apt/apt.conf.d/99no-recommends
echo 'APT::Install-Suggests "false";'   | sudo tee -a /etc/apt/apt.conf.d/99no-recommends

sudo add-apt-repository -y restricted
sudo add-apt-repository -y multiverse
sudo apt update

# -----------------------------------------------------------------
# 2. KERNEL HEADERS, BUILD TOOLS & DRIVER UTILITIES
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends \
    "linux-headers-$(uname -r)" \
    build-essential \
    dkms \
    ubuntu-drivers-common \
    pciutils \
    usbutils \
    software-properties-common \
    libnss3-tools \
    git \
    curl \
    wget \
    stow

# -----------------------------------------------------------------
# 3. GRAPHICS DRIVERS & HARDWARE VIDEO ACCELERATION
#    Detects the GPU vendor rather than assuming NVIDIA. Students'
#    laptops will mostly be Intel or AMD integrated graphics.
#
#    If they ticked "Install third-party drivers" in the Ubuntu Desktop
#    installer, the NVIDIA branch is effectively a no-op.
# -----------------------------------------------------------------
GPU_INFO="$(lspci -nn | grep -iE 'vga|3d controller|display controller')"
echo "Detected graphics:"
echo "$GPU_INFO" | sed 's/^/    /'

# --- Mesa + VA-API core (needed by every vendor) ---
sudo apt install -y --no-install-recommends \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    libva2 \
    vainfo \
    vulkan-tools

if echo "$GPU_INFO" | grep -qi nvidia; then
    echo "NVIDIA GPU detected — installing drivers..."
    # autoinstall picks the current recommended branch. Do NOT pin a
    # version here: the old qtile script pinned nvidia:595, but 26.04
    # already ships nvidia-driver-610.
    sudo ubuntu-drivers install --include-dkms || \
        sudo ubuntu-drivers autoinstall || \
        echo "WARNING: NVIDIA driver install failed — check 'ubuntu-drivers devices'."

    sudo tee /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

    # REQUIRED for Wayland. niri will not start correctly on the
    # proprietary driver without DRM kernel mode setting. Recent
    # drivers default it on, but the old X11 qtile script never needed
    # this and it is cheap to be explicit.
    sudo tee /etc/modprobe.d/nvidia-drm-modeset.conf <<'EOF'
options nvidia_drm modeset=1
EOF

    # 26.04 uses dracut, not update-initramfs
    sudo dracut -f
fi

if echo "$GPU_INFO" | grep -qi intel; then
    echo "Intel GPU detected — installing VA-API drivers..."
    # non-free variant covers H.264/HEVC decode on Gen9+; the plain
    # driver is the fallback for older parts.
    sudo apt install -y --no-install-recommends intel-media-va-driver-non-free || \
        sudo apt install -y --no-install-recommends intel-media-va-driver || \
        echo "WARNING: Intel VA-API driver not installed — video decode will be CPU-bound."
fi

if echo "$GPU_INFO" | grep -qiE "amd|radeon|advanced micro devices"; then
    echo "AMD GPU detected — amdgpu is in-kernel; ensuring firmware and Vulkan..."
    # linux-firmware is also installed in section 9; harmless if already present.
    sudo apt install -y --no-install-recommends linux-firmware libdrm-amdgpu1 || true
fi

# -----------------------------------------------------------------
# 4. UBUNTU DESKTOP BASE
#    Provides pipewire/wireplumber (audio), cups + avahi (printing —
#    DNS-SD browsing moved into cupsd itself in CUPS 2.2.4, so the legacy
#    cups-browsed is NOT needed), bluez (bluetooth), the xdg portals, and
#    a GNOME session
#    as a fallback if niri ever fails to start — worth having on a
#    student machine.
#
#    Installing from the Ubuntu 26.04 DESKTOP iso: this is already
#    present and the command is a no-op. Kept so the script also works
#    on a Server base.
#
#    --install-recommends is REQUIRED here: ubuntu-desktop pulls most of
#    the actual desktop in via Recommends, so under the global
#    no-recommends policy from section 1 you would get a hollow install.
# -----------------------------------------------------------------
sudo apt install -y --install-recommends ubuntu-desktop

# The Desktop iso installs and enables gdm3. dankinstall (section 5)
# installs greetd and repoints display-manager.service, but leaving gdm3
# enabled invites a race over the seat on boot. Disabling is safe: the
# GNOME *session* stays selectable from the dms-greeter session picker,
# which is what actually provides the fallback.
if systemctl list-unit-files gdm3.service >/dev/null 2>&1; then
    echo "Disabling gdm3 in favour of greetd..."
    sudo systemctl disable gdm3 2>/dev/null || true
fi

# ubuntu-desktop drags in update-notifier. Swap it for the harmless
# alternative, so nothing nags the student from the tray.
#
#   Why not just remove it: ubuntu-desktop, ubuntu-desktop-minimal and
#   update-manager all declare the ALTERNATIVE dependency
#   `update-notifier | gnome-package-updater`. One of the two must be
#   installed. `apt-get remove update-notifier` therefore does not leave
#   a gap -- apt pulls in gnome-package-updater to satisfy the
#   alternative, and that is exactly what we want, because:
#
#     * gnome-package-updater ships NO /etc/xdg/autostart entry. It is
#       just /usr/bin/gpk-update-viewer, launched on demand. Nothing
#       appears in the tray.
#     * update-notifier ships TWO autostart entries that do --
#       update-notifier.desktop and, despite the package name,
#       ubuntu-advantage-notification.desktop (the Ubuntu Pro/livepatch
#       nag).
#
#   Do NOT then remove gnome-package-updater: apt would satisfy the
#   alternative by reinstalling update-notifier, undoing this.
#
#   Nothing is lost. DMS ships its own system updater and on Ubuntu
#   reports backends "System, Flatpak" -- it covers apt directly, so a
#   student still has an update path. Verified on dell-ubuntu
#   30 Aug 2026. Fleet updates belong to whoever runs the fleet anyway.
#
#   update-notifier-common is a SEPARATE package and is deliberately
#   left alone: it provides /usr/lib/update-notifier/apt-check, and both
#   ubuntu-server and ttf-mscorefonts-installer depend on it.
#   PURGE, not remove. The two autostart entries are dpkg CONFFILES, so
#   `apt-get remove` leaves them in /etc/xdg/autostart pointing at a
#   binary that no longer exists. Verified on dell-ubuntu 30 Aug 2026:
#   after `remove` the package went to state `rc` and both .desktop
#   files were still there; `purge` cleared them.
if dpkg -l update-notifier 2>/dev/null | grep -qE "^(ii|rc)"; then
    echo "Replacing update-notifier with gnome-package-updater (no tray nag)..."
    sudo apt-get purge -y update-notifier || \
        echo "WARNING: could not purge update-notifier."
fi

# -----------------------------------------------------------------
# 5. DANK / NIRI STACK
#    Installs from ppa:avengemedia/danklinux + ppa:avengemedia/dms and
#    configures greetd + dms-greeter as the display manager.
#
#    Headless (unattended) mode is activated by passing --compositor and
#    --term together. The flags below reproduce this dotfiles setup:
#      niri compositor, alacritty terminal, dms-greeter greeter,
#      danksearch (with its user indexing service) and dankcalendar.
#
#    NOTE: dankinstall deploys its own default configs into
#    ~/.config/niri and ~/.config/DankMaterialShell. Section 10 removes
#    them before stow so our tracked versions win.
# -----------------------------------------------------------------
curl -fsSL https://install.danklinux.com | sh -s -- \
    --compositor niri \
    --term alacritty \
    --include-deps dms-greeter \
    --danksearch \
    --dankcalendar \
    --yes

# -----------------------------------------------------------------
# 6. BULK PACKAGES FROM THE LIST
#    One apt transaction for speed; if it fails, retry per-package so a
#    single bad or renamed package cannot abort the whole install.
# -----------------------------------------------------------------
if [ ! -f "$PKG_LIST" ]; then
    echo "ERROR: $PKG_LIST not found."
    exit 1
fi

# Pre-accept the Microsoft fonts EULA (avoids an interactive prompt)
echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
    | sudo debconf-set-selections

if ! grep -vE '^\s*(#|$)' "$PKG_LIST" \
        | xargs -r sudo apt install -y --no-install-recommends; then
    echo "Bulk install failed — retrying individually to isolate the bad package(s)..."
    grep -vE '^\s*(#|$)' "$PKG_LIST" \
        | xargs -r -n1 sudo apt install -y --no-install-recommends || true
fi

# Top up Qt's recommends, the way section 4 does for ubuntu-desktop.
#
#   Section 1 sets APT::Install-Recommends "false" fleet-wide. That is
#   right for the bulk list, but it silently broke two separate things,
#   BOTH of which are `Recommends:` of libqt6gui6:
#
#     qt6-svg-plugins       -- without it no Qt6 app can decode an SVG.
#                              quickshell logged "Unsupported image
#                              format" for its own greeter logo.
#     qt6-gtk-platformtheme -- the session sets QT_QPA_PLATFORMTHEME=gtk3
#                              and this supplies that plugin. Without it
#                              Qt loads no platform theme, never learns
#                              the icon theme name, and every
#                              QIcon::fromTheme() drops to bare hicolor,
#                              so app tray icons render as checkerboards
#                              whatever their format.
#
#   Both are listed explicitly in the package list as well. This line
#   exists so the NEXT one we have not thought of is caught too: it fixes
#   the class rather than the instances. Neither failure announced
#   itself -- a fleet would have shipped with broken icons and nobody
#   would have known.
#
#   libqt6gui6 is already installed by this point (the DMS stack in
#   section 5 pulls it in); asking again with --install-recommends only
#   adds the recommends.
echo "Topping up Qt6 recommends (icon theme + SVG plugins)..."
sudo apt install -y --install-recommends libqt6gui6 || \
    echo "WARNING: could not install libqt6gui6 recommends — expect missing tray icons."

# -----------------------------------------------------------------
# 7. GOOGLE CHROME
# -----------------------------------------------------------------
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub \
    | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
    | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt update
sudo apt install -y --no-install-recommends google-chrome-stable

# -----------------------------------------------------------------
# 8. FLATPAK APPS
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends flatpak gnome-software-plugin-flatpak
sudo flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo
sudo flatpak install -y flathub com.bambulab.BambuStudio org.freecad.FreeCAD || \
    echo "WARNING: flatpak install failed — retry after reboot."

# -----------------------------------------------------------------
# 9. NETWORKING, CERTIFICATE & WIFI PROFILES
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends \
    linux-firmware \
    wpasupplicant \
    iw \
    rfkill

# broadcom-sta-dkms only for machines that actually need it. It blacklists
# b43/brcmsmac/bcma/ssb, so installing it unconditionally across a fleet of
# mixed student laptops can break wifi on Broadcom parts that brcmfmac
# already handles.
if lspci -nn | grep -iE "network|wireless" | grep -qi broadcom; then
    echo "Broadcom wireless detected — installing broadcom-sta-dkms..."
    sudo apt install -y --no-install-recommends broadcom-sta-dkms || \
        echo "WARNING: broadcom-sta-dkms failed — check wifi after reboot."
else
    echo "No Broadcom wireless detected — skipping broadcom-sta-dkms."
fi

sudo rfkill unblock wifi

# Disable the installer's netplan config to prevent renderer conflicts
sudo mv /etc/netplan/00-installer-config.yaml \
    /etc/netplan/00-installer-config.yaml.bak 2>/dev/null || true

# Hand full network control to NetworkManager. This is what lets students
# add their own home wifi and VPN profiles from the desktop.
sudo tee /etc/netplan/01-network-manager-all.yaml <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
sudo chmod 600 /etc/netplan/01-network-manager-all.yaml
sudo netplan apply

# `netplan apply` tears down and rebuilds the network stack, and on a fresh
# desktop it also hard-restarts systemd-networkd (which is not running yet,
# so its dbus reload fails and it says so loudly -- that noise is expected
# and netplan still exits 0). The next command downloads a certificate, and
# without this wait it races the restart and dies with wget's exit 4,
# "network failure", taking the whole script with it under `set -e`.
#
# This is timing-dependent, so it does not fail every time. It killed the
# first full VM run at this exact line.
echo "Waiting for the network to come back after netplan apply..."
if ! nm-online -q --timeout=60; then
    echo "WARNING: network not online 60s after netplan apply; continuing anyway." >&2
fi

# Download and trust the Oakford CA certificate system-wide.
#
# This installs a ROOT CA (CN=Oakford Internet Services CA, CA:TRUE, valid
# 16 Aug 2024 - 14 Aug 2034). Anything able to substitute this file can
# transparently intercept every TLS connection the machine makes, with no
# browser warning, so it gets two independent protections:
#
#   1. https://, not http://. The plain http:// URL 301-redirects here and
#      wget follows redirects, so the right file did arrive -- but the
#      request STARTED in cleartext, which means an active attacker on the
#      path (school wifi included) could answer with their own CA instead
#      of the redirect and have it trusted fleet-wide. Demanding TLS closes
#      that: the stock Ubuntu trust store validates oakfordhelp.co.uk
#      before a single byte of the certificate is read.
#
#   2. A SHA-256 pin. Fails CLOSED -- on any mismatch the certificate is
#      not installed at all. This also catches a legitimate re-issue, which
#      is deliberate: a new CA should be a conscious decision, not a silent
#      one. When Oakford re-issue, verify the new fingerprint out of band
#      and update the line below. Do not delete the check.
#
# Verified 30 Aug 2026 against both the live host and the copy already
# trusted on dell-ubuntu; the two matched.
OAKFORD_SHA256="70:0D:4D:BA:40:46:29:25:31:7F:9E:C3:33:D5:D7:52:D4:C6:B5:C9:A1:BD:7B:27:BA:B7:12:5C:9C:13:C5:A3"

# Retries as well as the wait above: this is the first network access after
# the stack was rebuilt, so it is the most likely thing in the script to hit
# a half-ready connection.
#
# Downloaded as the normal user, not root: only the install needs privilege.
# No EXIT trap here: this script already owns EXIT for the sudo keepalive
# set up at the top, and re-arming it would silently discard that, leaving a
# stray keepalive loop running after the install finished.
OAKFORD_TMP="$(mktemp)"

if wget -q --tries=3 --retry-connrefused --waitretry=5 --timeout=20 \
        https://oakfordhelp.co.uk/oakford.crt -O "$OAKFORD_TMP"; then
    OAKFORD_GOT="$(openssl x509 -in "$OAKFORD_TMP" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)"
    if [ "$OAKFORD_GOT" = "$OAKFORD_SHA256" ]; then
        sudo install -m 0644 -o root -g root "$OAKFORD_TMP" \
            /usr/local/share/ca-certificates/oakford.crt
        sudo update-ca-certificates

        # Add to Chrome/Chromium NSS store so Chrome trusts internal
        # services. Only reached when the fingerprint matched.
        mkdir -p "$HOME/.pki/nssdb"
        certutil -d sql:"$HOME/.pki/nssdb" -N -f /dev/null 2>/dev/null || true
        certutil -d sql:"$HOME/.pki/nssdb" -A -t "CT,," -n "Oakford CA" \
            -f /dev/null -i /usr/local/share/ca-certificates/oakford.crt || true
    else
        echo "ERROR: Oakford CA fingerprint did NOT match. Certificate NOT installed." >&2
        echo "  expected: $OAKFORD_SHA256" >&2
        echo "  received: ${OAKFORD_GOT:-<not a certificate>}" >&2
        echo "  Internal HTTPS services will not be trusted. Do not work around" >&2
        echo "  this by installing it manually until the new fingerprint is" >&2
        echo "  confirmed with Oakford." >&2
    fi
else
    echo "WARNING: could not download the Oakford CA certificate." >&2
fi

rm -f "$OAKFORD_TMP"

# School wifi profile.
#
# The PSK is committed here deliberately. It is the BYOD network key,
# already known to every current and former student, so treating it as a
# secret bought nothing and cost a great deal: without it the profile was
# skipped, and an unattended build produced a student laptop that could
# not reach the school network -- the one thing it most needs to do.
# Craig's call, 31 Aug 2026.
#
# Override for a different network or after a key change:
#
#     S6C_PSK='...' ./ubuntu_26.04_niri_install.sh
#
# NOTE the SINGLE quotes. This key contains two '!' characters, which an
# interactive bash will treat as history expansion inside double quotes
# ("bash: !BY0D: event not found"). Inside this script it is safe: the
# heredoc below is expanded by the script, not by an interactive shell.
#
# autoconnect-priority is negative so a student's own home network wins
# whenever both are in range; NetworkManager would otherwise pick
# arbitrarily between two autoconnect profiles.
# NOTE ${VAR-default}, with NO colon: that substitutes only when the
# variable is UNSET. The colon form also substitutes when it is set but
# EMPTY, which would have made the documented S6C_PSK='' opt-out
# silently install the profile anyway.
S6C_PSK="${S6C_PSK-!BY0D!S6C}"

if [ -n "${S6C_PSK:-}" ]; then
    sudo mkdir -p /etc/NetworkManager/system-connections
    sudo tee /etc/NetworkManager/system-connections/S6C.nmconnection > /dev/null <<EOF
[connection]
id=S6C
type=wifi
autoconnect=true
autoconnect-priority=-10

[wifi]
mode=infrastructure
ssid=S6C

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=${S6C_PSK}

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=stable-privacy
EOF
    sudo chmod 600 /etc/NetworkManager/system-connections/S6C.nmconnection
    echo "School wifi profile installed."
else
    # Only reachable if someone explicitly passes S6C_PSK='' to opt out.
    echo "S6C_PSK empty — skipping the school wifi profile."
fi

# -----------------------------------------------------------------
# 10. DOTFILES — DE-CONFLICT, THEN STOW
#
#     dankinstall (section 5) deployed its own configs into
#     ~/.config/niri and ~/.config/DankMaterialShell. They must be
#     removed before stow, for two reasons:
#
#       1. stow cannot fold a directory that already exists, so it would
#          create per-FILE symlinks inside a real directory.
#       2. DMS writes settings.json atomically (temp file + rename),
#          which REPLACES a symlinked file with a regular one. The config
#          would silently detach from the repo on the first settings
#          change.
#
#     Directory-level symlinks survive that; per-file ones do not.
#     Never use `stow --adopt` here — it would pull dankinstall's
#     freshly-deployed defaults INTO the repo, overwriting yours.
# -----------------------------------------------------------------
for d in niri DankMaterialShell danksearch; do
    if [ -e "$HOME/.config/$d" ] && [ ! -L "$HOME/.config/$d" ]; then
        echo "Removing dankinstall's default $d config (repo version wins)..."
        rm -rf "$HOME/.config/$d"
    fi
done

# A fresh Ubuntu install seeds $HOME from /etc/skel — ~/.bashrc and
# ~/.profile among them. stow refuses to overwrite a real file and aborts
# the WHOLE deployment, so move aside any top-level dotfile that the repo
# also provides. Symlinks are left alone, making this safe to re-run.
cd "$DOTFILES_DIR"
while IFS= read -r f; do
    if [ -f "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
        echo "Moving aside default $f (repo version wins)..."
        mv "$HOME/$f" "$HOME/$f.pre-stow.bak"
    fi
done < <(find . -maxdepth 1 -type f -name '.*' -printf '%f\n')

# Do NOT mkdir anything stow provides — see the note above.
#
# NOTE: `stow -n` always writes "WARNING: in simulation mode..." to
# stderr, so that line must be filtered out before testing for conflicts.
# Without the filter the check always trips and stow never runs.
STOW_CONFLICTS="$(stow -n . 2>&1 | grep -v 'in simulation mode' || true)"
if [ -n "$STOW_CONFLICTS" ]; then
    echo "WARNING: stow reported conflicts (dry run):"
    echo "$STOW_CONFLICTS" | sed 's/^/    /'
    echo "Resolve the above, then run 'stow .' from $DOTFILES_DIR manually."
else
    stow .
    echo "Dotfiles stowed."
fi

fc-cache -f

# --- Default wallpaper ---------------------------------------------
#
#     The image itself ships in the repo and stow puts it at
#     ~/.local/share/backgrounds/0288.jpg. Two things still have to be
#     pointed AT it, and stow covers neither:
#
#       1. The greeter runs as user `greeter`, not as the logged-in
#          user, and greeterWallpaperPath lives in the repo's
#          settings.json -- ONE file shared by every machine. An
#          absolute path under /home/<someone> is therefore wrong on
#          any machine with a different username, and would also lean
#          on the greeter ACL over that home directory. So the image is
#          installed to a system-wide, world-readable path instead and
#          the setting points there.
#
#       2. The desktop wallpaper is `wallpaperPath` in
#          ~/.local/state/DankMaterialShell/session.json. That is
#          runtime STATE, deliberately not stowed, so on a new machine
#          it starts empty and the desktop comes up on DMS's default
#          dark gradient. Seed it here -- but only if the user has not
#          already chosen something, so re-running never overwrites a
#          preference.
#
#     Not fatal: a machine with no wallpaper still boots to a usable
#     desktop, so every step below is guarded under `set -e`.
S6C_WALLPAPER_SRC="$HOME/.local/share/backgrounds/0288.jpg"
S6C_WALLPAPER="/usr/share/backgrounds/s6c/ladybird.jpg"

if [ -f "$S6C_WALLPAPER_SRC" ]; then
    if sudo install -d -m 0755 /usr/share/backgrounds/s6c &&
       sudo install -m 0644 "$S6C_WALLPAPER_SRC" "$S6C_WALLPAPER"; then
        echo "Default wallpaper installed to $S6C_WALLPAPER"
    else
        echo "WARNING: could not install the default wallpaper system-wide."
    fi

    S6C_SESSION_JSON="$HOME/.local/state/DankMaterialShell/session.json"
    mkdir -p "$(dirname "$S6C_SESSION_JSON")"
    python3 - "$S6C_SESSION_JSON" "$S6C_WALLPAPER" <<'PYEOF' ||         echo "WARNING: could not seed the desktop wallpaper."
import json, os, sys

path, wallpaper = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        data = json.load(fh)
except (FileNotFoundError, ValueError):
    data = {}

if data.get("wallpaperPath"):
    print("Desktop wallpaper already set (%s) -- left alone." % data["wallpaperPath"])
else:
    data["wallpaperPath"] = wallpaper
    # DMS itself writes this file atomically; match that so a running
    # shell never reads a half-written file.
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2)
    os.replace(tmp, path)
    print("Desktop wallpaper seeded to %s" % wallpaper)
PYEOF
else
    echo "WARNING: $S6C_WALLPAPER_SRC not found after stow -- skipping wallpaper setup."
fi

# --- Default user avatar --------------------------------------------
#
#     Without this the greeter shows an empty circle where the user's
#     face should be. That is an upstream DMS bug, not a missing file:
#     GreeterContent.qml passes `fallbackIcon: "person"` to
#     DankCircularImage, and AppIconRenderer dispatches on a PREFIX --
#     "material:" for a Material Symbols glyph, "svg:"/"image:" for a
#     path, and anything unprefixed goes to a freedesktop icon-theme
#     lookup. "person" is unprefixed, and no installed theme has an icon
#     by that name (Material Symbols does, but it would have to be
#     "material:person"), so the fallback silently draws nothing.
#
#     Patching the shipped QML is not an option on a fleet -- the next
#     package update would revert it. Instead give the greeter a real
#     image to find. Its lookup order is:
#
#       <cache>/profile.{jpg,jpeg,png,webp}
#       /var/lib/AccountsService/icons/<user>
#       ~/.face
#       ~/.face.icon
#
#     ~/.face is the friendliest of those: owned by the user, so they can
#     replace it without root, and the greeter's own avatar picker will
#     override it.
#
#     The image is ours, stowed from the repo, rather than Yaru's
#     avatar-default.png -- Yaru's icons are CC-BY-SA and this repo is
#     public. It is navy #022B3A on cream #FAF7F0 to match brand.md
#     (13.93:1, AAA) instead of Yaru's bright blue, which clashes badly
#     with a warm wallpaper. See .local/share/s6c/README.md.
#
#     Only seeds when absent, so re-running never overwrites a user's
#     own picture.
S6C_AVATAR_SRC="$HOME/.local/share/s6c/avatar-default.png"
if [ ! -f "$HOME/.face" ] && [ ! -f "$HOME/.face.icon" ]; then
    if [ -f "$S6C_AVATAR_SRC" ]; then
        cp "$S6C_AVATAR_SRC" "$HOME/.face" && chmod 0644 "$HOME/.face" && \
            echo "Seeded default user avatar at ~/.face" || \
            echo "WARNING: could not seed the default avatar."
    else
        echo "WARNING: $S6C_AVATAR_SRC not found after stow -- skipping default avatar."
    fi
else
    echo "User avatar already present -- left alone."
fi

# --- Push settings and theme into the greeter -----------------------
#
#     dankinstall (section 5) sets greetd up, but it does NOT reconcile
#     the greeter with THIS user's settings, and nothing else here did
#     either -- so before this line the build shipped a greeter that was
#     missing four separate things. `dms greeter status` on a machine
#     built by the old script reports them:
#
#       * The greeter wallpaper never appears. greeterWallpaperPath is
#         only a SOURCE path; the greeter actually loads a fixed file,
#         <cache>/greeter_wallpaper_override.jpg, and only the sync
#         copies it there. Setting the path alone does nothing at all,
#         silently -- verified in the test VM 30 Aug 2026.
#       * Greeter colours are never generated from the wallpaper, and
#         the dms-colors.json symlink points at the wrong file.
#       * /etc/pam.d/dankshell is not created -- that is the PAM stack
#         the LOCK SCREEN authenticates against.
#       * The DMS AppArmor profile is not installed. `dms greeter status`
#         flags this itself: "Run 'dms greeter sync' to install it and
#         prevent potential TTY fallback".
#
#     Must run AFTER stow (so it reads the repo's settings.json, not
#     dankinstall's) and AFTER the wallpaper is in place above.
#
#     Not fatal: a failed sync leaves a plain but working greeter.
#     DMS_PRIVESC pins the privilege-escalation tool. Without it, `dms
#     greeter sync` detects both sudo and run0 and STOPS to ask:
#
#         Multiple privilege escalation tools detected:
#           [1] sudo  [2] run0
#         Choose one [1-2] (default 1, ...):
#
#     It only asks when stdin is a terminal -- which is exactly the
#     documented student route, `bash <(wget ...)` typed at a prompt. Every
#     VM run before this one drove the install over ssh with no pty, so the
#     prompt never appeared and three "clean" runs missed it. A student
#     would have been left staring at an unexplained question two thirds of
#     the way through, and an automated run with a pty hangs on it outright.
if command -v dms >/dev/null 2>&1; then
    echo "Syncing settings, theme and wallpaper into the greeter..."
    if DMS_PRIVESC=sudo dms greeter sync; then
        echo "Greeter synced."
    else
        echo "WARNING: 'dms greeter sync' failed. The greeter will still start,"
        echo "         but it will show default colours and no wallpaper, and the"
        echo "         lock screen PAM file may be missing. Re-run it by hand."
    fi
else
    echo "WARNING: 'dms' not on PATH -- skipping greeter sync."
fi

# -----------------------------------------------------------------
# 11. NODE.JS
# -----------------------------------------------------------------
if [ -f "$SCRIPT_DIR/install_node.sh" ]; then
    # install_node.sh git-clones node_install into the CURRENT directory, and
    # section 10 left us in $DOTFILES_DIR. Run it from install_programs/ so the
    # clone lands where .gitignore expects it, not in the repo root.
    ( cd "$SCRIPT_DIR" && bash ./install_node.sh )
else
    echo "WARNING: install_node.sh not found at $SCRIPT_DIR — skipping Node.js install."
fi

export NVM_DIR="$HOME/.nvm"
# NOT `[ -s ... ] && . ...` : under `set -e` a false test makes the whole
# AND-list return non-zero and aborts the script silently.
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
else
    echo "WARNING: nvm not found — skipping the npm-based installs below."
fi

# -----------------------------------------------------------------
# 12. YT-DLP, TPM, CLAUDE CODE, ANTIGRAVITY CLI
# -----------------------------------------------------------------
sudo wget -q https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -O /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi

curl -fsSL https://claude.ai/install.sh | bash || \
    echo "WARNING: Claude Code install failed — install manually after reboot."

# Antigravity CLI, NOT Gemini CLI.
#
# Google deprecated Gemini CLI on 2026-06-18: it stopped serving requests
# for the free tier and for Google AI Pro/Ultra, which is what students
# would be on. Only Gemini Code Assist Standard/Enterprise licences keep
# working. `npm install -g @google/gemini-cli` therefore installs a tool
# that authenticates and then fails.
#
# The replacement is a Go binary installed by shell script — no npm and no
# Node dependency — landing at ~/.local/bin/agy. Students run `agy` once to
# sign in through the browser.
#   https://antigravity.google/docs/cli/install
curl -fsSL https://antigravity.google/cli/install.sh | bash || \
    echo "WARNING: Antigravity CLI install failed — see https://antigravity.google/docs/cli/install"

# -----------------------------------------------------------------
# 13. MACHINE IDENTITY: KEYBOARD, LOCALE, TIMEZONE, HOSTNAME
#     config.kdl leaves niri's xkb block empty on purpose, so niri reads
#     the layout from org.freedesktop.locale1. Without this, a fresh
#     install gives students a US keyboard.
# -----------------------------------------------------------------
# NOT `localectl set-x11-keymap`. Ubuntu ships
#     /usr/share/dbus-1/system.d/org.freedesktop.locale1.read-only.conf
# which denies SetX11Keyboard and SetVConsoleKeyboard on the system bus to
# *every* caller, root included:
#     Rejected send message, 5 matched rules; ... uid=0 ...
#     member="SetX11Keyboard" ... error-name=...DBus.Error.AccessDenied
# Keyboard config on Ubuntu belongs to console-setup, so localed may only
# read it, never write it. Under `set -e` that one line aborted the whole
# script, taking sections 13-16 with it.
#
# localed still *reports* the layout over locale1, which is what niri
# consumes, so writing the file gets us exactly the property we need --
# verified: setting XKBLAYOUT=de made `localectl status` report de.
sudo tee /etc/default/keyboard >/dev/null <<'KBD'
# Managed by ubuntu_26.04_niri_install.sh
XKBMODEL="pc105"
XKBLAYOUT="gb"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
KBD

# Seed debconf too, so a later `dpkg-reconfigure keyboard-configuration`
# agrees with the file instead of reverting it.
sudo debconf-set-selections <<'DEBCONF' || true
keyboard-configuration keyboard-configuration/modelcode string pc105
keyboard-configuration keyboard-configuration/layoutcode string gb
DEBCONF

# Applies to the virtual consoles. Exits 0 with a note when run off-console
# (e.g. over ssh), so it is safe under set -e either way.
sudo setupcon --save || true
sudo systemctl try-restart systemd-localed.service || true

# SetLocale is *not* in that deny list, so this one still works over D-Bus.
sudo localectl set-locale LANG=en_GB.UTF-8

# The Desktop installer asks for a timezone, but an unattended/preseeded
# install can land on UTC, which silently skews every timestamp students see.
sudo timedatectl set-timezone Europe/London
sudo timedatectl set-ntp true

# Hostname. A fleet of machines all called "ubuntu" is miserable to
# manage - you cannot tell them apart in DHCP leases, print queues or
# ssh known_hosts. Supply it either way round:
#
#     TARGET_HOSTNAME=s6c-laptop-07 ./ubuntu_26.04_niri_install.sh
#     ./ubuntu_26.04_niri_install.sh        (prompts, blank = keep current)
CURRENT_HOSTNAME="$(hostname)"
if [ -z "${TARGET_HOSTNAME:-}" ] && [ -t 0 ]; then
    read -r -p "Hostname for this machine [$CURRENT_HOSTNAME]: " TARGET_HOSTNAME
fi

if [ -n "${TARGET_HOSTNAME:-}" ] && [ "$TARGET_HOSTNAME" != "$CURRENT_HOSTNAME" ]; then
    # RFC 1123: letters, digits and hyphens only, not starting or ending
    # with a hyphen. An invalid hostname breaks sudo's reverse lookup.
    if printf '%s' "$TARGET_HOSTNAME" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'; then
        echo "Setting hostname to $TARGET_HOSTNAME ..."
        sudo hostnamectl set-hostname "$TARGET_HOSTNAME"
        # /etc/hosts still maps 127.0.1.1 to the OLD name. Leaving it stale
        # makes every sudo call wait on a failed name lookup first.
        sudo sed -i "s/\b${CURRENT_HOSTNAME}\b/${TARGET_HOSTNAME}/g" /etc/hosts
    else
        echo "WARNING: '$TARGET_HOSTNAME' is not a valid hostname — keeping $CURRENT_HOSTNAME."
    fi
fi

# -----------------------------------------------------------------
# 14. POST-INSTALL CONFIGURATION
#     greetd is enabled LAST so that a failure earlier in this script
#     leaves a working TTY rather than a broken graphical boot.
# -----------------------------------------------------------------
xdg-user-dirs-update

# zram compressed swap. zram-tools installs /etc/default/zramswap but does
# not necessarily enable the unit, and its default ALGO is lz4. zstd
# compresses substantially better, which matters more than raw speed on
# the 4-8GB laptops this targets.
if [ -f /etc/default/zramswap ]; then
    sudo sed -i 's/^ALGO=.*/ALGO=zstd/'   /etc/default/zramswap
    sudo sed -i 's/^PERCENT=.*/PERCENT=50/' /etc/default/zramswap
    # `enable --now` is NOT enough. zram-tools' postinst already started
    # zramswap when the package was installed back in the package sweep, and
    # `--now` is a no-op on a unit that is already running -- so the ALGO edit
    # above never reached the running device and every machine silently kept
    # the default lz4. Verified on dell-ubuntu 30 Aug 2026: zramctl reported
    # lz4 with ALGO=zstd sitting in the config file; a restart produced zstd.
    sudo systemctl enable zramswap.service || true
    sudo systemctl restart zramswap.service || \
        echo "WARNING: zramswap did not start — check 'zramctl' after reboot."
else
    echo "WARNING: /etc/default/zramswap missing — is zram-tools installed?"
fi

sudo systemctl enable udisks2
sudo systemctl enable cups          || true
sudo systemctl enable avahi-daemon  || true
sudo systemctl enable greetd
sudo systemctl set-default graphical.target

# -----------------------------------------------------------------
# 15. PER-STUDENT GIT IDENTITY & GITHUB ACCESS
#
#     IMPORTANT: nothing in this script uses the maintainer's GitHub key,
#     and it must stay that way. A shared private key across a fleet of
#     student laptops is a shared credential: it cannot be attributed to
#     anyone, any one lost laptop exposes it, and revoking it breaks every
#     machine at once.
#
#     bootstrap.sh therefore clones this repo over HTTPS, so no key at all
#     is needed to INSTALL. A credential is only needed to PUSH, and each
#     student sets up their own below.
# -----------------------------------------------------------------

# Make sure the clone is on an HTTPS remote. If someone cloned with SSH
# using a borrowed key, rewrite it so pushes prompt for the student's own
# GitHub credentials instead of silently using that key.
if git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null | grep -q '^git@github.com:'; then
    OLD_URL="$(git -C "$DOTFILES_DIR" remote get-url origin)"
    NEW_URL="https://github.com/${OLD_URL#git@github.com:}"
    echo "Rewriting origin to HTTPS so pushes use this student's own credentials:"
    echo "    $OLD_URL  ->  $NEW_URL"
    git -C "$DOTFILES_DIR" remote set-url origin "$NEW_URL"
fi

# Generate a per-machine SSH key if there isn't one. No passphrase: under
# niri there is no graphical ssh-askpass in the default session, so a
# passphrased key would prompt into a void. Students who want one can add
# it later with `ssh-keygen -p -f ~/.ssh/id_ed25519`.
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "Generating a per-machine SSH key..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -N "" -C "$(whoami)@$(hostname)" \
        -f "$HOME/.ssh/id_ed25519" >/dev/null
fi

GIT_IDENTITY_SET=yes
if [ -z "$(git config --global user.email 2>/dev/null || true)" ]; then
    GIT_IDENTITY_SET=no
fi

# -----------------------------------------------------------------
# 16. PAPERCUT PRINTING
#
#     School printers are PaperCut. The finding that shapes this whole
#     section: MOBILITY PRINT HAS NO LINUX CLIENT. PaperCut support
#     Windows, macOS, Chrome, iOS and Android only, and say so plainly:
#     "Linux devices are not supported because there is no dedicated
#     Mobility Print client." Print Deploy is the only supported route
#     onto Linux — and it can itself import Mobility Print queues.
#       https://www.papercut.com/help/manuals/mobility-print/overview/what-product-to-use-when/
#
#     Do NOT be tempted to hand-roll an lpadmin queue against
#     ipps://user:pass@host:9164/printers/<queue>. That form comes from a
#     2018 third-party blog post, PaperCut separately state they do not
#     support IPP Everywhere, and it bakes ONE user's credentials into
#     the queue — exactly wrong for a shared student image. Print Deploy
#     runs a localhost IPP proxy (port 9177) that injects whoever is
#     actually logged in.
#
#     Supply the server either way round:
#       PAPERCUT_SERVER=https://print.school.example:9174 ./ubuntu_26.04_niri_install.sh
#       ./ubuntu_26.04_niri_install.sh    (prompts; blank skips printing)
#
#     ⚠️ Two things to check against YOUR server before trusting this:
#       1. The download endpoint /print-deploy/client/linux-debian is
#          confirmed from a live PaperCut-generated client-setup page,
#          NOT from PaperCut's manual.
#       2. The port. 9174 is the Print Deploy server's runtime port, but
#          the client-setup page is served by the Application Server
#          (9191/9192, or 443 behind a proxy). If the download 404s, try
#          the Application Server URL instead.
#
#     Wayland note: the Print Deploy client GUI is GTK/WebKitGTK, so it
#     runs natively under niri — no XWayland needed. The older Java Swing
#     pc-client (the balance/account popup) is a different matter: AWT has
#     no GA Wayland toolkit, so it would need xwayland-satellite running
#     and DISPLAY exported, and its XEmbed tray icon will not appear on a
#     Wayland bar. It is deliberately NOT installed here.
# -----------------------------------------------------------------
if [ -z "${PAPERCUT_SERVER:-}" ] && [ -t 0 ]; then
    echo ""
    echo "PaperCut Print Deploy server URL, e.g. https://print.school.example:9174"
    read -r -p "  (blank to skip printer setup): " PAPERCUT_SERVER
fi

if [ -n "${PAPERCUT_SERVER:-}" ]; then
    # Strip any trailing slash so the URL join below cannot double up.
    PAPERCUT_SERVER="${PAPERCUT_SERVER%/}"

    # CUPS must already be installed: the .deb's postinst aborts with
    # "Unable to find cupsd - is CUPS installed?" and dpkg then errors out.
    # libwebkit2gtk-4.1-0 is a hard dependency of the client GUI.
    # avahi-daemon + libnss-mdns are needed for mDNS-discovered queues.
    echo "Installing Print Deploy prerequisites..."
    sudo apt install -y --no-install-recommends \
        cups \
        cups-ipp-utils \
        libwebkit2gtk-4.1-0 \
        avahi-daemon \
        avahi-utils \
        libnss-mdns

    # Pre-seed the config so the downloaded filename does not have to carry
    # the server name. Written BEFORE the package is installed, which is
    # what --force-confdef below protects.
    #
    # StrictSSLCheckingEnabled defaults to true here. Set
    # PAPERCUT_STRICT_SSL=false only if your PaperCut server presents a
    # self-signed certificate that is not in the system CA store — section
    # 9 already installs the Oakford CA, so try true first.
    sudo mkdir -p /etc/papercut-print-deploy-client
    sudo tee /etc/papercut-print-deploy-client/client.conf.toml > /dev/null <<EOF
ServerBaseURL = "${PAPERCUT_SERVER}"
StrictSSLCheckingEnabled = ${PAPERCUT_STRICT_SSL:-true}
HTTPProxy = ""
EOF

    PC_TMP="$(mktemp -d)"
    # -OJ: the filename arrives via Content-Disposition and encodes the
    # server address; PaperCut are explicit that it must not be renamed.
    if ( cd "$PC_TMP" && curl -fL -OJ "${PAPERCUT_SERVER}/print-deploy/client/linux-debian" ); then
        PC_DEB="$(find "$PC_TMP" -maxdepth 1 -name '*.deb' | head -1)"
        if [ -n "$PC_DEB" ]; then
            echo "Installing $(basename "$PC_DEB") ..."
            # SKIP_DPM must be passed as an ENVIRONMENT VARIABLE — it is not
            # read from the TOML. It skips the Direct Print Monitor, which a
            # student laptop does not need.
            # --force-confdef or dpkg prompts interactively and overwrites
            # the conffile written above.
            sudo SKIP_DPM=true dpkg -i --force-confdef "$PC_DEB" || {
                echo "dpkg reported unmet dependencies — resolving..."
                sudo apt-get -y -f install
            }
            echo "Print Deploy installed. Queues appear after first login."
            echo "  Logs: /opt/PaperCutPrintDeployClient/data/logs/install.log"
        else
            echo "WARNING: download produced no .deb — skipping Print Deploy."
        fi
    else
        echo "WARNING: could not download the Print Deploy client from"
        echo "         ${PAPERCUT_SERVER}/print-deploy/client/linux-debian"
        echo "         Check the host and port (9174 vs the App Server's"
        echo "         9192/443), then install by hand from:"
        echo "         ${PAPERCUT_SERVER}/print-deploy/client-setup/linux.html"
    fi
    rm -rf "$PC_TMP"

    # Note: the Linux Print Deploy client does NOT auto-update. Reinstall
    # over the top when the server is upgraded, re-passing SKIP_DPM=true.
else
    echo "No PaperCut server given — skipping printer setup."
    echo "Students can still add printers with system-config-printer."
fi

# -----------------------------------------------------------------
echo ""
echo "-------------------------------------------------------"
echo "SETUP COMPLETE."
echo ""
echo "Reboot to enter Niri. At the greeter you can also pick the"
echo "GNOME session if Niri ever fails to start."
echo ""
echo "For students:"
echo "  * Home wifi:  DMS control centre, or nm-connection-editor"
echo "  * VPN:        create the profile in nm-connection-editor, then"
echo "                toggle it from the DMS bar VPN widget"
if [ -n "${PAPERCUT_SERVER:-}" ]; then
    echo "  * Printers:   school queues arrive via PaperCut Print Deploy"
    echo "                shortly after your first login. Home printers:"
    echo "                system-config-printer"
else
    echo "  * Printers:   system-config-printer"
fi
echo ""
echo "  GITHUB — set up your OWN access. Never share a private key:"
if [ "$GIT_IDENTITY_SET" = no ]; then
    echo "    1. Tell git who you are:"
    echo "         git config --global user.name  'Your Name'"
    echo "         git config --global user.email 'you@example.com'"
fi
echo "    2. Authenticate. Easiest, no SSH key needed:"
echo "         gh auth login      (choose GitHub.com -> HTTPS -> browser)"
echo "       Or add this machine's public key at github.com/settings/keys:"
if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    sed 's/^/         /' "$HOME/.ssh/id_ed25519.pub"
fi
echo ""
echo "  Mod+Alt+L locks the screen using dank-lock.sh (pixelated"
echo "  screenshot background)."
echo ""
echo "  NVIDIA only: watch for the MOK enrollment screen on first"
echo "  boot and enroll the key."
echo "-------------------------------------------------------"
