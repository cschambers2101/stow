#!/usr/bin/env bash
# Student entry point: clone the dotfiles to ~/.dotfiles and hand off to the niri installer.
# bash <(wget -qO- https://raw.githubusercontent.com/cschambers2101/stow/main/install_programs/bootstrap.sh)

set -e

REPO_HTTPS="https://github.com/cschambers2101/stow.git"
REPO_SSH="git@github.com:cschambers2101/stow.git"
DOTFILES_DIR="$HOME/.dotfiles"

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: run this as your normal user, not root."
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Installing git..."
    sudo apt update
    sudo apt install -y git
fi

if ssh -T -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | grep -q "successfully authenticated"; then
    REPO_URL="$REPO_SSH"
    echo "GitHub SSH key detected — using the SSH remote (push will work)."
else
    REPO_URL="$REPO_HTTPS"
    echo "No usable GitHub SSH key — using the HTTPS remote (clone only; push needs a key)."
fi

if [ -d "$DOTFILES_DIR/.git" ]; then
    echo "$DOTFILES_DIR already exists — pulling latest..."
    git -C "$DOTFILES_DIR" remote set-url origin "$REPO_URL" 2>/dev/null || true
    git -C "$DOTFILES_DIR" pull --ff-only || \
        echo "WARNING: pull failed; continuing with the existing checkout."
elif [ -e "$DOTFILES_DIR" ]; then
    echo "ERROR: $DOTFILES_DIR exists but is not a git checkout. Move it aside first."
    exit 1
else
    echo "Cloning dotfiles into $DOTFILES_DIR ..."
    git clone --depth 1 "$REPO_URL" "$DOTFILES_DIR"
fi

INSTALLER="$DOTFILES_DIR/install_programs/ubuntu_26.04_niri_install.sh"
if [ ! -f "$INSTALLER" ]; then
    echo "ERROR: $INSTALLER not found."
    exit 1
fi

chmod +x "$INSTALLER"

echo ""
echo "Starting the main install. This takes a while and will ask for your"
echo "password once, up front."
echo ""
exec "$INSTALLER"
