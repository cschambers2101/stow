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
sudo -v
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
    linux-headers-$(uname -r) \
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
#    Provides pipewire/wireplumber (audio), cups + avahi + cups-browsed
#    (printing), bluez (bluetooth), the xdg portals, and a GNOME session
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

# Download and trust the Oakford CA certificate system-wide
sudo wget -q http://oakfordhelp.co.uk/oakford.crt \
    -O /usr/local/share/ca-certificates/oakford.crt
sudo update-ca-certificates

# Add to Chrome/Chromium NSS store so Chrome trusts internal services
mkdir -p "$HOME/.pki/nssdb"
certutil -d sql:"$HOME/.pki/nssdb" -N -f /dev/null 2>/dev/null || true
certutil -d sql:"$HOME/.pki/nssdb" -A -t "CT,," -n "Oakford CA" \
    -f /dev/null -i /usr/local/share/ca-certificates/oakford.crt || true

# School wifi profile. autoconnect-priority is negative so a student's own
# home network wins whenever both are in range; NetworkManager would
# otherwise pick arbitrarily between two autoconnect profiles.
sudo mkdir -p /etc/NetworkManager/system-connections
sudo tee /etc/NetworkManager/system-connections/S6C.nmconnection > /dev/null <<'EOF'
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
psk=BY0DS6C

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=stable-privacy
EOF
sudo chmod 600 /etc/NetworkManager/system-connections/S6C.nmconnection

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
# 12. YT-DLP, TPM, CLAUDE CODE, GEMINI CLI
# -----------------------------------------------------------------
sudo wget -q https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -O /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi

curl -fsSL https://claude.ai/install.sh | bash || \
    echo "WARNING: Claude Code install failed — install manually after reboot."

npm install -g @google/gemini-cli || \
    echo "WARNING: Gemini CLI install failed — run 'npm install -g @google/gemini-cli' after reboot."

# -----------------------------------------------------------------
# 13. KEYBOARD LAYOUT & LOCALE
#     config.kdl leaves niri's xkb block empty on purpose, so niri reads
#     the layout from org.freedesktop.locale1. Without this, a fresh
#     install gives students a US keyboard.
# -----------------------------------------------------------------
sudo localectl set-x11-keymap gb pc105
sudo localectl set-locale LANG=en_GB.UTF-8

# The Desktop installer asks for a timezone, but an unattended/preseeded
# install can land on UTC, which silently skews every timestamp students see.
sudo timedatectl set-timezone Europe/London
sudo timedatectl set-ntp true

# -----------------------------------------------------------------
# 14. POST-INSTALL CONFIGURATION
#     greetd is enabled LAST so that a failure earlier in this script
#     leaves a working TTY rather than a broken graphical boot.
# -----------------------------------------------------------------
xdg-user-dirs-update
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
echo "  * Printers:   system-config-printer"
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
