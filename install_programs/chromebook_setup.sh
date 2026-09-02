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
# No-recommends lockdown REMOVED 31 Aug 2026 -- see section 1 of
# ubuntu_26.04_niri_install.sh. Actively removed so a re-run undoes it.
sudo rm -f /etc/apt/apt.conf.d/99no-recommends
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
# 2A. NETWORK TRUST: THE OAKFORD ROOT CA
#
#    Lettered, not renumbered, so the later section numbers keep matching
#    the ones quoted elsewhere. Section 7 is now empty and gone.
#
#    THE POSITION IS THE POINT. The site firewall intercepts TLS, so
#    anything fetched from outside the Debian archives fails certificate
#    validation until this CA is trusted. This used to be section 7,
#    AFTER section 6 pulls the .NET installer from dot.net -- so on the
#    school network the build died there. Same defect as the niri and
#    qtile installers, fixed the same way, 2 Sep 2026.
#
#    It sits after section 2 because that is what installs `wget`, which
#    Crostini's Debian base does not ship. Sections 1-2 reach only the
#    Debian archives, whose traffic bypasses the firewall, as does
#    oakfordhelp.co.uk itself -- which is what lets the download below
#    succeed before its own certificate is trusted.
#
#    Keep every third-party download BELOW this line: 6 (.NET), 8 (gh),
#    9 (nvm), 10 (Claude, Antigravity), 11 (yt-dlp), 12 (tpm).
# -----------------------------------------------------------------
# Download and trust the Oakford CA certificate system-wide.
#
# This installs a ROOT CA, so anything able to substitute the file can
# intercept every TLS connection this machine makes. https:// (not the
# http:// URL, which only 301-redirects and so starts in cleartext) plus a
# SHA-256 pin that fails CLOSED. See the long note in
# ubuntu_26.04_niri_install.sh. Verified 30 Aug 2026.
OAKFORD_SHA256="70:0D:4D:BA:40:46:29:25:31:7F:9E:C3:33:D5:D7:52:D4:C6:B5:C9:A1:BD:7B:27:BA:B7:12:5C:9C:13:C5:A3"
OAKFORD_TMP="$(mktemp)"
trap 'rm -f "$OAKFORD_TMP"' EXIT

if wget -q --tries=3 --retry-connrefused --waitretry=5 --timeout=20 \
        https://oakfordhelp.co.uk/oakford.crt -O "$OAKFORD_TMP" &&
   [ "$(openssl x509 -in "$OAKFORD_TMP" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)" = "$OAKFORD_SHA256" ]; then
    sudo install -m 0644 -o root -g root "$OAKFORD_TMP" \
        /usr/local/share/ca-certificates/oakford.crt
    sudo update-ca-certificates
else
    echo "ERROR: Oakford CA not installed - download failed or fingerprint mismatch." >&2
    echo "  Internal HTTPS services will not be trusted. Confirm the new" >&2
    echo "  fingerprint with Oakford before changing OAKFORD_SHA256." >&2
fi

rm -f "$OAKFORD_TMP"
trap - EXIT

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
# Pre-create the target directory so the nvm installer doesn't exit
# on "NVM_DIR set but doesn't exist" when the var is inherited from
# the parent login shell.
# -----------------------------------------------------------------
export NVM_DIR="$HOME/.config/nvm"
if [ ! -f "$NVM_DIR/nvm.sh" ]; then
    mkdir -p "$NVM_DIR"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts

# -----------------------------------------------------------------
# 10. CLAUDE & ANTIGRAVITY CLI
# -----------------------------------------------------------------
# Gemini CLI was deprecated on 2026-06-18 and stopped serving free-tier
# and AI Pro/Ultra accounts. Antigravity CLI replaces it: a Go binary,
# Antigravity CLI removed 31 Aug 2026 — see ubuntu_26.04_niri_install.sh
# section 12 for why (199 MB binary into the stow tree, plus a redundant
# hardcoded PATH export appended to two tracked files).
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
