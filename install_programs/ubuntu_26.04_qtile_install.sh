#!/bin/bash

# =================================================================
# MINIMAL UBUNTU SERVER + QTILE + NVIDIA SETUP SCRIPT
# This script installs ONLY essentials (no-recommends).
# =================================================================

# 1. LOCK DOWN APT (The "Minimalist" Protocol)
sudo mkdir -p /etc/apt/apt.conf.d
echo 'APT::Install-Recommends "false";' | sudo tee /etc/apt/apt.conf.d/99no-recommends
echo 'APT::Install-Suggests "false";' | sudo tee -a /etc/apt/apt.conf.d/99no-recommends

sudo apt update

# 2. INSTALL KERNEL HEADERS (Required for Nvidia build)
sudo apt install -y --no-install-recommends linux-headers-$(uname -r) build-essential dkms

# 3. INSTALL CORE X11 & INPUT DRIVERS
# Added libinput/evdev manually to ensure keyboard/mouse work.
sudo apt install -y --no-install-recommends \
    xserver-xorg-core \
    xserver-xorg-video-all \
    xserver-xorg-input-all \
    xserver-xorg-input-libinput \
    xserver-xorg-input-evdev \
    xinit \
    dbus-x11 \
    libpam-systemd

# 4. INSTALL NVIDIA DRIVERS (RTX 3060 Ti)
# Replace 550 with the version recommended by 'ubuntu-drivers devices'
sudo apt install -y --no-install-recommends \
    nvidia-driver-550 \
    libnvidia-gl-550 \
    nvidia-dkms-550 \
    nvidia-xconfig \
    libgl1-mesa-dri \
    libglx-mesa0

# 5. INSTALL SDDM & QTILE
sudo apt install -y --no-install-recommends \
    sddm \
    qtile \
    python3-cairocffi \
    python3-xcffib \
    libpangocairo-1.0-0 \
    python3-psutil

# 6. INSTALL THE "MISSING LINKS" (Fixes hollow windows & hanging apps)
sudo apt install -y --no-install-recommends \
    policykit-1-gnome \
    libgdk-pixbuf-2.0-0 \
    librsvg2-common \
    shared-mime-info \
    xdg-desktop-portal-gtk \
    xdg-user-dirs \
    xclip xsel

# 7. INSTALL INTERFACE ESSENTIALS (Terminal & Fonts)
sudo apt install -y --no-install-recommends \
    xfce4-terminal \
    alacritty \
    fonts-dejavu-core \
    fonts-cascadia-code \
    fonts-font-awesome \
    picom

# 8. POST-INSTALL CONFIGURATION
xdg-user-dirs-update
sudo nvidia-xconfig
sudo systemctl enable sddm
sudo systemctl set-default graphical.target

# 9. BLACKLIST NOUVEAU (Prevent driver conflicts)
echo -e "blacklist nouveau\noptions nouveau modeset=0" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
sudo update-initramfs -u

# 10. INSTALL WIFI DRIVERS (Common Proprietory)
## Enable proprietary sources
sudo add-apt-repository -y restricted
sudo add-apt-repository -y multiverse
sudo apt update

## Install firmware and management tools
sudo apt install -y --no-install-recommends \
    linux-firmware \
    bcmwl-kernel-source \
    network-manager \
    wpasupplicant \
    wireless-tools \
    rfkill

## Unblock wifi (sometimes it defaults to "hard blocked")
sudo rfkill unblock wifi

## Install Networking Stack
sudo apt install -y --no-install-recommends \
    network-manager \
    network-manager-gnome \
    gnome-keyring \
    wpasupplicant \
    wireless-tools \
    rfkill

# 2. Fix Netplan to use NetworkManager
# This creates a fresh config that gives control to the GUI
sudo tee /etc/netplan/01-network-manager-all.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
EOF

sudo netplan apply


echo "-------------------------------------------------------"
echo "SETUP COMPLETE."
echo "Ensure Secure Boot is DISABLED in your BIOS."
echo "Reboot now to enter your new Qtile environment."
echo "-------------------------------------------------------"


