#!/bin/bash

# =================================================================
# CHROMEBOOK PENGUIN VM (DEBIAN) — STUDENT SETUP
# Optimized for Crostini (Linux development environment)
# =================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------
# 1. APT OPTIMIZATION
# -----------------------------------------------------------------
# Remove the Microsoft apt source if it was left behind by a previous run —
# its SHA1-bound key is rejected by Debian's sqv verifier since 2026-02-01.
sudo rm -f /etc/apt/sources.list.d/microsoft-prod.list

# Enable contrib before the first apt update — ttf-mscorefonts-installer lives there.
# Source /etc/os-release for VERSION_CODENAME; lsb_release is not present in Crostini.
. /etc/os-release
echo "deb http://deb.debian.org/debian ${VERSION_CODENAME} contrib" \
    | sudo tee /etc/apt/sources.list.d/contrib.list
echo 'APT::Install-Recommends "false";' | sudo tee /etc/apt/apt.conf.d/99no-recommends
sudo apt update

# -----------------------------------------------------------------
# 2. CORE DEV TOOLS
# vim-gtk3 provides +clipboard and +python3 (requires X11 — fine in Crostini).
# -----------------------------------------------------------------
sudo apt install -y \
    build-essential \
    git curl wget ripgrep fzf tmux stow btop nala \
    python3-pip python3-venv python3-full python3-psutil \
    apt-show-versions ssh v4l-utils libnss3-tools \
    bash-completion \
    vim-gtk3 \
    starship \
    pandoc

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

# Pre-accept the Microsoft fonts EULA (avoids interactive prompt)
echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
    | sudo debconf-set-selections
sudo apt install -y ttf-mscorefonts-installer

# -----------------------------------------------------------------
# 4. TERMINAL & PRODUCTIVITY
# -----------------------------------------------------------------
sudo apt install -y xclip xsel

# -----------------------------------------------------------------
# 5. MEDIA & UTILITIES (No VLC usually needed, ChromeOS handles it)
# -----------------------------------------------------------------
sudo apt install -y ffmpeg imagemagick fuse3 caca-utils weasyprint

# -----------------------------------------------------------------
# 6. .NET SDK 10
# Microsoft's apt repo signing key uses SHA1 binding, rejected by
# Debian's sqv verifier since 2026-02-01. Use the install script instead.
# Installs to ~/.dotnet; shell config (via stow) should export DOTNET_ROOT.
# -----------------------------------------------------------------
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh
/tmp/dotnet-install.sh --channel 10.0
rm /tmp/dotnet-install.sh
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$PATH:$DOTNET_ROOT"

# -----------------------------------------------------------------
# 7. CA CERTIFICATES (Oakford)
# -----------------------------------------------------------------
sudo wget -q http://oakfordhelp.co.uk/oakford.crt \
    -O /usr/local/share/ca-certificates/oakford.crt
sudo update-ca-certificates

# -----------------------------------------------------------------
# 8. GITHUB CLI (gh)
# Not in Debian default repos — add GitHub's signed apt source.
# -----------------------------------------------------------------
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install -y gh

# -----------------------------------------------------------------
# 9. NODE.JS (via nvm)
# Install nvm directly — no external repo dependency, and ensures
# nvm.sh is present before the Claude installer tries to use nvm.
# -----------------------------------------------------------------
export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts

# -----------------------------------------------------------------
# 10. CLAUDE & GEMINI CLI
# -----------------------------------------------------------------
npm install -g @google/gemini-cli || \
    echo "WARNING: Gemini CLI install failed — run 'npm install -g @google/gemini-cli' after reboot."
curl -fsSL https://claude.ai/install.sh | bash || \
    echo "WARNING: Claude Code install failed — install manually after reboot."

# -----------------------------------------------------------------
# 11. YT-DLP
# -----------------------------------------------------------------
sudo wget -q https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -O /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp

# -----------------------------------------------------------------
# 12. TMUX PLUGIN MANAGER (tpm)
# -----------------------------------------------------------------
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi

# -----------------------------------------------------------------
# 13. DIRECTORY SCAFFOLDING
# -----------------------------------------------------------------
mkdir -p ~/.config ~/.local/share/fonts ~/.local/bin

echo "-------------------------------------------------------"
echo "CHROMEBOOK LINUX SETUP COMPLETE."
echo "Your apps will now appear in the ChromeOS Launcher."
echo "Next: Run 'stow .' in your dotfiles to link configs."
echo "-------------------------------------------------------"
