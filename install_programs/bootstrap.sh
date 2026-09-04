#!/bin/bash

# =================================================================
# BOOTSTRAP — NIRI / DANK STUDENT LAPTOP
#
# The single command a student runs on a fresh Ubuntu 26.04 Desktop
# install. NO GitHub key, account or login is required to get here:
# the clone is over anonymous HTTPS.
#
#   bash <(wget -qO- https://raw.githubusercontent.com/cschambers2101/stow/main/install_programs/bootstrap.sh)
#
# wget, NOT curl. Ubuntu 26.04.1 Desktop ships wget but NOT curl, so the
# curl form of this line fails on a stock manual install before it starts.
# (The autoinstall route installs curl itself, and the main installer
# apt-installs both in section 2 -- it is only this first fetch that is
# exposed.) If a machine somehow has curl but not wget:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/cschambers2101/stow/main/install_programs/bootstrap.sh)
#
# Requires: Ubuntu 26.04 Desktop, Secure Boot DISABLED, network up.
# =================================================================

set -e

REPO_HTTPS="https://github.com/cschambers2101/stow.git"
REPO_SSH="git@github.com:cschambers2101/stow.git"
DOTFILES_DIR="$HOME/.dotfiles"

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: run this as your normal user, not root."
    exit 1
fi

# git is not on the Ubuntu Desktop iso.
if ! command -v git >/dev/null 2>&1; then
    echo "Installing git..."
    sudo apt update
    sudo apt install -y git
fi

# Prefer SSH when a GitHub-authorised key is present, so `git push` works
# without a stored HTTPS credential. The repo is public, so HTTPS can still
# CLONE (but not push) on a fresh machine whose key is not enrolled yet.
# GitHub's SSH endpoint always exits non-zero (it grants no shell), so match the
# success banner rather than the exit code; BatchMode + ConnectTimeout keep a
# filtered port 22 from hanging the build, and accept-new trusts github.com's
# host key on first contact without an interactive prompt.
if ssh -T -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | grep -q "successfully authenticated"; then
    REPO_URL="$REPO_SSH"
    echo "GitHub SSH key detected — using the SSH remote (push will work)."
else
    REPO_URL="$REPO_HTTPS"
    echo "No usable GitHub SSH key — using the HTTPS remote (clone only; push needs a key)."
fi

# The repo is named "stow" on GitHub but MUST land in ~/.dotfiles:
# ubuntu_26.04_niri_install.sh derives the stow target from its own
# location, so a clone into ~/stow would stow from the wrong path.
if [ -d "$DOTFILES_DIR/.git" ]; then
    echo "$DOTFILES_DIR already exists — pulling latest..."
    # Re-point an existing checkout at the chosen URL, so once a key is enrolled
    # the remote flips from HTTPS to SSH and pushes stop needing a credential.
    git -C "$DOTFILES_DIR" remote set-url origin "$REPO_URL" 2>/dev/null || true
    git -C "$DOTFILES_DIR" pull --ff-only || \
        echo "WARNING: pull failed; continuing with the existing checkout."
elif [ -e "$DOTFILES_DIR" ]; then
    echo "ERROR: $DOTFILES_DIR exists but is not a git checkout. Move it aside first."
    exit 1
else
    echo "Cloning dotfiles into $DOTFILES_DIR ..."
    # --depth 1: the repo's history still contains ~380 MB of wallpapers that
    # were removed from the working tree in Aug 2026. A full clone downloads
    # all of it; a shallow one fetches only the current tree, which is ~13 MB.
    # Nothing in the build reads git history, so there is nothing to lose.
    git clone --depth 1 "$REPO_URL" "$DOTFILES_DIR"
fi

INSTALLER="$DOTFILES_DIR/install_programs/ubuntu_26.04_niri_install.sh"
if [ ! -f "$INSTALLER" ]; then
    echo "ERROR: $INSTALLER not found."
    exit 1
fi

# Belt and braces: a clone from a repo where the executable bit was lost
# would otherwise fail with "Permission denied".
chmod +x "$INSTALLER"

echo ""
echo "Starting the main install. This takes a while and will ask for your"
echo "password once, up front."
echo ""
exec "$INSTALLER"
