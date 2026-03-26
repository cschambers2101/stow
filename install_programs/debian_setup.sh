#!/usr/bin/env bash

# Script to setup a Debian-based system with essential packages and configurations.

# 1. Identify the real user (even if running via sudo)
if [ -n "$SUDO_USER" ]; then
    actual_user=$SUDO_USER
else
    actual_user=$(whoami)
fi

# 2. Elevation Logic: Ensure we are running as root for system tasks
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        echo "Sudo is installed. Elevating..."
        exec sudo "$0" "$@"
    else
        echo "Error: 'sudo' is not installed and you are not root."
        echo "Please enter the ROOT password to install sudo and add $actual_user to the group:"
        su -c "apt update && apt install -y sudo && usermod -aG sudo $actual_user"
        
        echo "----------------------------------------------------"
        echo "SUCCESS: Sudo installed and $actual_user added to sudo group."
        echo "IMPORTANT: You MUST log out or restart for changes to take effect."
        echo "RESTART YOUR COMPUTER NOW AND RE-RUN THIS SCRIPT."
        echo "----------------------------------------------------"
        exit 0
    fi
fi

echo "The script is being managed for: $actual_user"

# 3. System-Level Tasks (Running as ROOT)
# ---------------------------------------
# Silence setfont error if not in a real TTY
setfont /usr/share/consolefonts/Lat2-Terminus32x16.psf.gz 2>/dev/null

echo "Updating repositories and installing system packages..."
# Enable contrib repository
sed -i '/^deb .* main/ s/$/ contrib/' /etc/apt/sources.list
apt update

# Install core system software
apt install -y xorg xinit x11-xserver-utils xterm menu sddm qtile \
               python3-xcffib python3-cairocffi git stow curl

# Enable login manager
systemctl enable sddm

# 4. User-Level Tasks (Running as $actual_user)
# ---------------------------------------------
# We use a Here-Doc to run these commands in the context of the regular user
sudo -u "$actual_user" bash <<EOF
echo "Now running as: \$(whoami)"
echo "Target home directory is: \$HOME"

# Create source folder
mkdir -p \$HOME/src
cd \$HOME/src

# Clone or update dotfiles
if [ ! -d "\$HOME/.dotfiles" ]; then
    echo "Cloning dotfiles..."
    git clone https://github.com/cschambers2101/stow.git \$HOME/.dotfiles
else
    echo "Dotfiles already exist. Pulling updates..."
    cd \$HOME/.dotfiles
    git pull origin main
fi

# Prepare for Stowing
cd \$HOME/.dotfiles
echo "Removing old config files to prevent stow conflicts..."
rm -rf \$HOME/.config/qtile \$HOME/.bashrc

# Run Stow
echo "Applying dotfiles with GNU Stow..."
stow .

# Run the nested install script
if [ -f "./install_programs/install_required_programs.sh" ]; then
    cd install_programs
    chmod +x install_required_programs.sh
    echo "Starting required programs installation..."
    ./install_required_programs.sh
else
    echo "Warning: install_required_programs.sh not found."
fi

echo "Setup complete for $actual_user."
echo "You should reboot your system now."
EOF

exit 0
