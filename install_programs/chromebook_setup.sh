#!/bin/bash

# =================================================================
# CHROMEBOOK PENGUIN VM (DEBIAN) — STUDENT SETUP
# Optimized for Crostini (Linux development environment)
# =================================================================

set -e

# -----------------------------------------------------------------
# 1. APT OPTIMIZATION
# -----------------------------------------------------------------
sudo apt update
echo 'APT::Install-Recommends "false";' | sudo tee /etc/apt/apt.conf.d/99no-recommends

# -----------------------------------------------------------------
# 2. CORE DEV TOOLS (The "Heavy Lifters")
# -----------------------------------------------------------------
sudo apt install -y \
    build-essential \
    git curl wget ripgrep fzf tmux stow btop nala \
    python3-pip python3-venv python3-full \
    apt-show-versions ssh v4l-utils libnss3-tools \
    bash-completion

# -----------------------------------------------------------------
# 3. UI INTEGRATION (For GTK/Qt Apps to look good in ChromeOS)
# -----------------------------------------------------------------
sudo apt install -y \
    adwaita-icon-theme-full \
    fonts-noto-core \
    fonts-cascadia-code \
    fonts-font-awesome \
    gnome-keyring \
    libgl1-mesa-dri mesa-utils

# -----------------------------------------------------------------
# 4. TERMINAL & PRODUCTIVITY
# -----------------------------------------------------------------
sudo apt install -y alacritty xfce4-terminal xclip xsel

# -----------------------------------------------------------------
# 5. GOOGLE CHROME (Optional - for Web Dev Testing)
# Note: Students have the host browser, but some need a Linux-native
# version for Selenium or specific dev-tools extensions.
# -----------------------------------------------------------------
# [Same logic as previous script for Google's repo]

# -----------------------------------------------------------------
# 6. MEDIA & UTILITIES (No VLC usually needed, ChromeOS handles it)
# -----------------------------------------------------------------
sudo apt install -y ffmpeg imagemagick fuse3

# -----------------------------------------------------------------
# 7. CA CERTIFICATES (Oakford)
# -----------------------------------------------------------------
sudo wget -q http://oakfordhelp.co.uk/oakford.crt -O /usr/local/share/ca-certificates/oakford.crt
sudo update-ca-certificates

# -----------------------------------------------------------------
# 8. CLAUDE & GEMINI CLI
# -----------------------------------------------------------------
# Assumes Node is installed via sub-script
npm install -g @google/gemini-cli || true
curl -fsSL https://claude.ai/install.sh | bash || true

# -----------------------------------------------------------------
# 9. DIRECTORY SCAFFOLDING
# -----------------------------------------------------------------
mkdir -p ~/.config ~/.local/share/fonts ~/.local/bin

echo "-------------------------------------------------------"
echo "CHROMEBOOK LINUX SETUP COMPLETE."
echo "Your apps will now appear in the ChromeOS Launcher."
echo "Next: Run 'stow .' in your dotfiles to link configs."
echo "-------------------------------------------------------"