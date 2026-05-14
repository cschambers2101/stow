#!/bin/bash

# =================================================================
# UNIVERSAL DEBIAN STUDENT SETUP SCRIPT (QTILE)
# Target: Debian 12/13+ (Stable or Testing)
# Logic: Auto-detects hardware and installs relevant drivers.
# =================================================================

set -e

# -----------------------------------------------------------------
# 1. REPOSITORY & APT CONFIGURATION
# -----------------------------------------------------------------
echo "Configuring repositories for non-free hardware support..."
# Ensure contrib, non-free, and non-free-firmware are enabled
sudo sed -i 's/main$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list || true

# Force no-recommends for a lean Qtile build
sudo mkdir -p /etc/apt/apt.conf.d
echo 'APT::Install-Recommends "false";' | sudo tee /etc/apt/apt.conf.d/99no-recommends
echo 'APT::Install-Suggests "false";'   | sudo tee -a /etc/apt/apt.conf.d/99no-recommends

sudo apt update

# -----------------------------------------------------------------
# 2. BASE UTILITIES (Needed for detection)
# -----------------------------------------------------------------
sudo apt install -y build-essential dkms pciutils usbutils curl wget git software-properties-common

# -----------------------------------------------------------------
# 3. AUTO-DETECTION ENGINE: CPU & GPU
# -----------------------------------------------------------------
echo "Detecting hardware..."

# --- CPU Microcode ---
if grep -q "Intel" /proc/cpuinfo; then
    echo "Intel CPU detected. Installing microcode..."
    sudo apt install -y intel-microcode
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    echo "AMD CPU detected. Installing microcode..."
    sudo apt install -y amd64-microcode
fi

# --- GPU Drivers ---
if lspci | grep -qi nvidia; then
    echo "NVIDIA GPU detected. Installing proprietary drivers..."
    sudo apt install -y nvidia-driver nvidia-settings firmware-misc-nonfree
    # Debian default is update-initramfs
    sudo update-initramfs -u
elif lspci | grep -qi "VGA.*AMD"; then
    echo "AMD GPU detected. Installing Mesa/Vulkan drivers..."
    sudo apt install -y libgl1-mesa-dri xserver-xorg-video-amdgpu mesa-vulkan-drivers
elif lspci | grep -qi "VGA.*Intel"; then
    echo "Intel GPU detected. Installing Intel video drivers..."
    sudo apt install -y xserver-xorg-video-intel libgl1-mesa-dri
fi

# --- Wi-Fi & Bluetooth Firmware ---
echo "Installing universal firmware bundle..."
sudo apt install -y firmware-linux-nonfree firmware-iwlwifi firmware-realtek firmware-atheros firmware-libreoffice firmware-brcm80211

# -----------------------------------------------------------------
# 4. THE QTILE STACK (X11 + WM)
# -----------------------------------------------------------------
sudo apt install -y \
    xserver-xorg-core xserver-xorg-input-libinput xinit dbus-x11 libpam-systemd \
    sddm qtile python3-cairocffi python3-xcffib python3-psutil \
    rofi dunst feh polybar picom sxhkd lxappearance pcmanfm \
    xss-lock i3lock scrot flameshot alacritty xfce4-terminal \
    udisks2 gvfs udiskie

# -----------------------------------------------------------------
# 5. DEVELOPER TOOLS & HEAVY APPS
# -----------------------------------------------------------------
sudo apt install -y \
    ripgrep fzf tmux stow btop nala python3-pip python3-venv \
    apt-show-versions ssh v4l-utils libnss3-tools ffmpeg vlc \
    imagemagick fuse3 alsa-utils google-chrome-stable \
    gimp libreoffice obs-studio || echo "Some apps might need manual repo adding (Chrome/Node)."

# -----------------------------------------------------------------
# 6. NETWORKING & SYSTEM INTEGRATION
# -----------------------------------------------------------------
sudo apt install -y network-manager network-manager-gnome gnome-keyring wpasupplicant iw rfkill
sudo systemctl enable NetworkManager
sudo systemctl enable sddm

# Add user to critical groups for hardware access
sudo usermod -aG video,audio,render,netdev,plugdev $USER

# -----------------------------------------------------------------
# 7. DIRECTORY SCAFFOLDING
# -----------------------------------------------------------------
mkdir -p ~/.config/{qtile,picom,rofi,polybar} ~/.local/share/{fonts,backgrounds}

echo "-------------------------------------------------------"
echo "HARDWARE DETECTION & INSTALL COMPLETE."
echo "Students should now reboot and run 'stow .' for configs."
echo "-------------------------------------------------------"