#!/bin/bash

# =================================================================
# UBUNTU 26.04 LTS — QTILE DEV LAPTOP SETUP
# Run this script from the dotfiles repo root after cloning.
# Requires: vanilla Ubuntu Server 26.04, Secure Boot DISABLED.
# =================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------
# 1. LOCK DOWN APT (no recommended/suggested packages)
# -----------------------------------------------------------------
sudo mkdir -p /etc/apt/apt.conf.d
echo 'APT::Install-Recommends "false";' | sudo tee /etc/apt/apt.conf.d/99no-recommends
echo 'APT::Install-Suggests "false";'   | sudo tee -a /etc/apt/apt.conf.d/99no-recommends

sudo apt update

# -----------------------------------------------------------------
# 2. KERNEL HEADERS, BUILD TOOLS & DRIVER UTILITIES
# ubuntu-drivers-common is not pre-installed on Ubuntu Server.
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends \
    linux-headers-$(uname -r) \
    build-essential \
    dkms \
    ubuntu-drivers-common \
    pciutils

# -----------------------------------------------------------------
# 3. NVIDIA DRIVERS (skipped automatically if no NVIDIA GPU)
#    On reboot you will see a blue MOK Management screen — enroll the key.
# -----------------------------------------------------------------
if lspci | grep -qi nvidia; then
    echo "NVIDIA GPU detected — installing drivers..."
    sudo ubuntu-drivers install --include-dkms nvidia:595
    sudo tee /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF
    # 26.04 uses dracut, not update-initramfs
    sudo dracut -f
else
    echo "No NVIDIA GPU detected — skipping driver install."
fi

# -----------------------------------------------------------------
# 4. X11 & INPUT STACK
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends \
    xserver-xorg-core \
    xserver-xorg-input-all \
    xserver-xorg-input-libinput \
    xserver-xorg-input-evdev \
    xinit \
    dbus-x11 \
    libpam-systemd

# -----------------------------------------------------------------
# 5. CORE DEVELOPER TOOLS
# libnss3-tools provides certutil for Chrome certificate trust.
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends \
    git \
    curl \
    wget \
    vim-gtk3 \
    python3-pip \
    python3-venv \
    ripgrep \
    fzf \
    tmux \
    stow \
    btop \
    nala \
    starship \
    pandoc \
    apt-show-versions \
    dotnet-sdk-10.0 \
    ssh \
    v4l-utils \
    libnss3-tools

# -----------------------------------------------------------------
# 6. WINDOW MANAGER & DESKTOP STACK
# udisks2 + gvfs + udiskie enable USB automounting in PCManFM.
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends \
    sddm \
    qtile \
    python3-cairocffi \
    python3-xcffib \
    python3-psutil \
    rofi \
    dunst \
    feh \
    polybar \
    picom \
    sxhkd \
    lxappearance \
    pcmanfm \
    xss-lock \
    i3lock \
    scrot \
    flameshot \
    alacritty \
    xfce4-terminal \
    udisks2 \
    gvfs \
    udiskie

# -----------------------------------------------------------------
# 7. POLICY KIT & DESKTOP INTEGRATION
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends \
    policykit-1-gnome \
    libgdk-pixbuf-2.0-0 \
    librsvg2-common \
    shared-mime-info \
    xdg-desktop-portal-gtk \
    xdg-user-dirs \
    xclip \
    xsel

# -----------------------------------------------------------------
# 8. QT6 QML MODULES (required by SDDM — 26.04 SDDM is Qt6-only)
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends \
    libqt6svg6 \
    qml6-module-qt5compat-graphicaleffects \
    qml6-module-qtquick-layouts \
    qml6-module-qtquick-controls \
    qml6-module-qtquick-templates

# -----------------------------------------------------------------
# 9. FONTS
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends \
    fonts-dejavu-core \
    fonts-cascadia-code \
    fonts-font-awesome \
    fonts-noto-core

# Pre-accept the Microsoft fonts EULA (avoids interactive prompt)
echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
    | sudo debconf-set-selections
sudo apt install -y --no-install-recommends ttf-mscorefonts-installer

# -----------------------------------------------------------------
# 10. MEDIA & UTILITIES
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends \
    ffmpeg \
    vlc \
    imagemagick \
    fuse \
    caca-utils

# -----------------------------------------------------------------
# 11. GOOGLE CHROME
# Not in Ubuntu repos — add Google's signing key and repo first.
# -----------------------------------------------------------------
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub \
    | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
    | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt update
sudo apt install -y --no-install-recommends google-chrome-stable

# -----------------------------------------------------------------
# 12. HEAVY APPS
# -----------------------------------------------------------------
sudo apt install -y --no-install-recommends \
    gimp \
    libreoffice \
    obs-studio

# -----------------------------------------------------------------
# 13. WIFI & NETWORKING
# -----------------------------------------------------------------
sudo add-apt-repository -y restricted
sudo add-apt-repository -y multiverse
sudo apt update

sudo apt install -y --no-install-recommends \
    linux-firmware \
    broadcom-sta-dkms \
    network-manager \
    network-manager-gnome \
    gnome-keyring \
    wpasupplicant \
    iw \
    rfkill

sudo rfkill unblock wifi

# Disable Ubuntu Server's default netplan config to prevent renderer conflicts
sudo mv /etc/netplan/00-installer-config.yaml \
    /etc/netplan/00-installer-config.yaml.bak 2>/dev/null || true

# Hand full network control to NetworkManager
sudo tee /etc/netplan/01-network-manager-all.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
EOF
sudo chmod 600 /etc/netplan/01-network-manager-all.yaml
sudo netplan apply

# -----------------------------------------------------------------
# 14. OAKFORD CERTIFICATE & S6C WIFI PROFILE
# -----------------------------------------------------------------

# Download and trust the Oakford CA certificate system-wide
sudo wget -q http://oakfordhelp.co.uk/oakford.crt \
    -O /usr/local/share/ca-certificates/oakford.crt
sudo update-ca-certificates

# Add to Chrome/Chromium NSS store so Chrome trusts internal services
mkdir -p "$HOME/.pki/nssdb"
certutil -d sql:"$HOME/.pki/nssdb" -N -f /dev/null 2>/dev/null || true
certutil -d sql:"$HOME/.pki/nssdb" -A -t "CT,," -n "Oakford CA" \
    -f /dev/null -i /usr/local/share/ca-certificates/oakford.crt || true

# Drop S6C connection profile — NetworkManager picks it up on first start
sudo mkdir -p /etc/NetworkManager/system-connections
sudo tee /etc/NetworkManager/system-connections/S6C.nmconnection > /dev/null <<EOF
[connection]
id=S6C
type=wifi
autoconnect=true

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
# 15. NODE.JS
# -----------------------------------------------------------------
if [ -f "$SCRIPT_DIR/install_node.sh" ]; then
    bash "$SCRIPT_DIR/install_node.sh"
else
    echo "WARNING: install_node.sh not found at $SCRIPT_DIR — skipping Node.js install."
fi

# Source nvm into current shell so npm is available for subsequent steps
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# -----------------------------------------------------------------
# 16. YT-DLP
# -----------------------------------------------------------------
sudo wget -q https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -O /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp

# -----------------------------------------------------------------
# 17. TMUX PLUGIN MANAGER (tpm)
# -----------------------------------------------------------------
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi

# -----------------------------------------------------------------
# 18. CLAUDE CODE CLI
# -----------------------------------------------------------------
curl -fsSL https://claude.ai/install.sh | bash || \
    echo "WARNING: Claude Code install failed — install manually after reboot."

# -----------------------------------------------------------------
# 19. GEMINI CLI (requires Node from step 15)
# -----------------------------------------------------------------
npm install -g @google/gemini-cli || \
    echo "WARNING: Gemini CLI install failed — run 'npm install -g @google/gemini-cli' after reboot."

# -----------------------------------------------------------------
# 20. SDDM EUCALYPTUS DROP THEME
# -----------------------------------------------------------------
if [ -f "$SCRIPT_DIR/install_eucalyptus_drop_sddm_theme.sh" ]; then
    sudo bash "$SCRIPT_DIR/install_eucalyptus_drop_sddm_theme.sh" || \
        echo "WARNING: SDDM theme install failed — continuing."
else
    echo "WARNING: install_eucalyptus_drop_sddm_theme.sh not found — skipping."
fi

# -----------------------------------------------------------------
# 21. DIRECTORY SCAFFOLDING
# -----------------------------------------------------------------
mkdir -p \
    ~/.config/qtile \
    ~/.config/picom \
    ~/.config/rofi \
    ~/.config/polybar \
    ~/.config/xfce4 \
    ~/.local/share/backgrounds \
    ~/.local/share/fonts \
    ~/.local/share/qtile \
    ~/.local/share/rofi \
    ~/.local/bin

# -----------------------------------------------------------------
# 22. POST-INSTALL CONFIGURATION
# -----------------------------------------------------------------
xdg-user-dirs-update
sudo systemctl enable sddm
sudo systemctl enable udisks2
sudo systemctl set-default graphical.target

# -----------------------------------------------------------------
echo ""
echo "-------------------------------------------------------"
echo "SETUP COMPLETE."
echo ""
echo "Next steps:"
echo "  1. cd into your dotfiles repo and run: stow ."
echo "     (this deploys your Qtile config, autostart, etc.)"
echo "  2. Reboot to enter your Qtile environment."
echo "  3. NVIDIA only: watch for the MOK enrollment screen"
echo "     on first boot and enroll the key."
echo "  NOTE: udiskie runs via autostart.sh — USB drives will"
echo "        auto-mount and appear in PCManFM after first login."
echo "-------------------------------------------------------"
