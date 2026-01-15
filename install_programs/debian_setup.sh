#!/usr/bin/env bash

# Script to setup a Debian-based system with essential packages and configurations.

# Set font size for TTY
setfont /usr/share/consolefonts/Lat2-Terminus32x16.psf.gz

# This logic handles both: regular run AND sudo run
if [ -n "$SUDO_USER" ]; then
    actual_user=$SUDO_USER
else
    actual_user=$(whoami)
fi

echo "The script is being managed for: $actual_user"

#!/bin/bash

# 1. Check if the user is already root
if [ "$(id -u)" -eq 0 ]; then
    echo "Running as root..."
else
    # 2. Check if sudo is installed
    if command -v sudo >/dev/null 2>&1; then
        echo "Sudo is installed. Elevating..."
        exec sudo "$0" "$@"
    else
        # 3. Sudo is missing. Ask the user to install it via 'su'
        echo "Error: 'sudo' is not installed and you are not root."
        echo "I need to install 'sudo' and add you to the sudo group."
        echo "Please enter the ROOT password when prompted below:"
        
        # This command switches to root just to run the install and setup
        su -c "apt update && apt install -y sudo && usermod -aG sudo $USER"
        
        echo "----------------------------------------------------"
        echo "SUCCESS: Sudo installed and $USER added to sudo group."
        echo "IMPORTANT: You must LOG OUT and LOG BACK IN for changes to take effect."
        echo "RESTART YOUR COMPUTER NOW AND RE RUN THIS SCRIPT
        echo "----------------------------------------------------"
        exit 0
    fi
fi

# switch to logged in user context for next operations 
# sudo -u "$actual_user" bash <<EOF

echo "Now running as: \$(whoami)"
echo "My home directory is: \$HOME"

# Add user to sudo group
sudo usermod -aG sudo $actual_user
# enable contrib repository
sudo sed -i '/^deb .* main/ s/$/ contrib/' /etc/apt/sources.list && sudo apt update
# Install Xorg with qtile and sddm
sudo apt install xorg xinit x11-xserver-utils xterm menu sddm qtile python3-xcffib python3-cairocffi -y
# enable sddm
sudo systemctl enable sddm
# create source folder in home directory
mkdir -p \$HOME/src
cd \$HOME/src
# clone dotfiles repository
if [ ! -d "\$HOME/src/dotfiles" ]; then
    git clone https://github.com/cschambers2101/stow.git $HOME/.dotfiles
else
    git pull origin main
fi
cd $HOME/.dotfiles
# Install stow if not present
if ! command -v stow >/dev/null 2>&1; then
    sudo apt install stow -y
fi
# rm existing config files
rm -rf \$HOME/.config/qtile \$HOME/.bashrc
# stow dotfiles
stow .
# reload the bashrc
source \$HOME/.bashrc
# Install required programs
cd \$HOME/.dotfiles/install_programs
echo "Installing required programs..."
echo 
echo "This will take a while. Please be patient. When asked to install Starship, press 'y' to confirm."
echo
./install_required_programs.sh

echo "Setup complete for $actual_user."
echo
echo "You will need to reboot now. type 'sudo reboot' to restart your system."
# EOF

# Explicitly exit the script so no root commands accidentally run below
exit 0
