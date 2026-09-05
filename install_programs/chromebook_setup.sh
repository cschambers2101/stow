#!/usr/bin/env bash
# Chromebook Penguin VM (Debian / Crostini) student setup.
# Usage: bash chromebook_setup.sh

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"
# shellcheck source=lib/oakford-ca.sh
. "$HERE/lib/oakford-ca.sh"
# shellcheck source=lib/node.sh
. "$HERE/lib/node.sh"
# shellcheck source=lib/devtools.sh
. "$HERE/lib/devtools.sh"

apt_setup() {
    sudo rm -f /etc/apt/sources.list.d/microsoft-prod.list
    # shellcheck source=/dev/null
    . /etc/os-release
    echo "deb http://deb.debian.org/debian ${VERSION_CODENAME} contrib" | write_root_file /etc/apt/sources.list.d/contrib.list
    sudo rm -f /etc/apt/apt.conf.d/99no-recommends
    apt_update
}

core_tools() {
    apt_install \
        build-essential git curl wget ripgrep fzf tmux stow btop nala \
        python3-pip python3-venv python3-full python3-psutil \
        apt-show-versions ssh v4l-utils libnss3-tools bash-completion \
        vim-gtk3 starship pandoc
}

ui_integration() {
    apt_install adwaita-icon-theme-full fonts-noto-core fonts-cascadia-code fonts-font-awesome gnome-keyring libgl1-mesa-dri mesa-utils
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | sudo debconf-set-selections
    apt_install ttf-mscorefonts-installer
    apt_install xclip xsel
    apt_install ffmpeg imagemagick fuse3 caca-utils weasyprint secure-delete
}

dotnet_sdk() {
    local tmp
    tmp="$(mktemp)"
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$tmp" || { warn ".NET install script download failed."; rm -f "$tmp"; return 0; }
    bash "$tmp" --channel 10.0 || warn ".NET SDK install failed."
    rm -f "$tmp"
}

github_cli() {
    local keyring=/usr/share/keyrings/githubcli-archive-keyring.gpg
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee "$keyring" >/dev/null
    sudo chmod go+r "$keyring"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyring] https://cli.github.com/packages stable main" \
        | write_root_file /etc/apt/sources.list.d/github-cli.list
    apt_update
    apt_install gh
}

main() {
    require_not_root
    sudo_keepalive
    section "APT";            apt_setup
    section "Core tools";     core_tools
    section "Oakford CA";     install_oakford_ca
    section "UI and fonts";   ui_integration
    section ".NET SDK";       dotnet_sdk
    section "GitHub CLI";     github_cli
    section "Node.js";        install_node_lts
    section "Claude Code";    install_claude_code
    section "yt-dlp and tpm"; install_yt_dlp; install_tpm
    mkdir -p ~/.config ~/.local/share/fonts ~/.local/bin
    echo ""
    echo "CHROMEBOOK LINUX SETUP COMPLETE."
    echo "Your apps will now appear in the ChromeOS Launcher."
    echo "Next: run 'stow .' in ~/.dotfiles to link configs."
}

main "$@"
