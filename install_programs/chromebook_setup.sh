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
sudo apt update
echo 'APT::Install-Recommends "false";' | sudo tee /etc/apt/apt.conf.d/99no-recommends

# -----------------------------------------------------------------
# 2. CORE DEV TOOLS
# vim-gtk3 provides +clipboard and +python3 (requires X11 — fine in Crostini).
# -----------------------------------------------------------------
sudo apt install -y \
    build-essential \
    git curl wget ripgrep fzf tmux stow btop nala \
    python3-pip python3-venv python3-full \
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

# -----------------------------------------------------------------
# 4. TERMINAL & PRODUCTIVITY
# -----------------------------------------------------------------
sudo apt install -y xclip xsel

# -----------------------------------------------------------------
# 5. MEDIA & UTILITIES (No VLC usually needed, ChromeOS handles it)
# -----------------------------------------------------------------
sudo apt install -y ffmpeg imagemagick fuse3

# -----------------------------------------------------------------
# 6. .NET SDK 10
# Not in Debian default repos — add the Microsoft package feed.
# -----------------------------------------------------------------
wget -q https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb \
    -O /tmp/packages-microsoft-prod.deb
sudo dpkg -i /tmp/packages-microsoft-prod.deb
rm /tmp/packages-microsoft-prod.deb
sudo apt update
sudo apt install -y dotnet-sdk-10.0

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
# 9. NODE.JS
# -----------------------------------------------------------------
if [ -f "$SCRIPT_DIR/install_node.sh" ]; then
    bash "$SCRIPT_DIR/install_node.sh"
else
    echo "WARNING: install_node.sh not found at $SCRIPT_DIR — skipping Node.js install."
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

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
