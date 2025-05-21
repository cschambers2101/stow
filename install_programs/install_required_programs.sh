#!/bin/bash

# Create required directories
mkdir -p ~/.config/i3 ~/.config/pcmanfm ~/.config/picom ~/.config polybar ~/.config/qtile ~/.config/rofi ~/.config/xfce4
mkdir -p ~/.local/bambu ~/.local/share/backgrounds ~/.local/share/ca-certificates ~/.local/css ~/.local/fonts ~/.local/icons ~/.local/share/qtile ~/.local/share/rofi ~/.local/share/xfce4


# Check if the package list file exists
if [ ! -f "programs_to_install.txt" ]; then
    echo "Error: programs_to_install.txt not found!"
    exit 1
fi

# Update package list first
echo "Updating package list..."
sudo apt-get update

# Read packages from the file into an array
readarray -t packages < "programs_to_install.txt"

# Filter out empty lines and comments
packages=("${packages[@]//$'\r'/}") # Remove carriage returns (CR)
packages=("${packages[@]//#[^\r]*/}") # Remove comments
packages=("${packages[@]//^[ \t]*\r?$/}") # Remove empty lines

# Check if there are any packages to install
if [ ${#packages[@]} -gt 0 ]; then
    echo "Attempting to install the following packages: ${packages[*]}"
    # Install the packages with a single apt install command
    sudo apt-get install -y -o Acquire::http::Pipeline-Depth="0" "${packages[@]}"

    if [ $? -eq 0 ]; then
        echo "Successfully installed all specified packages."
    else
        echo "Error occurred during package installation."
    fi
else
    echo "No packages to install."
fi

sudo apt autoremove -y


# Install Qtile
script_to_run="install_qtile.sh"

if [ -e "$script_to_run" ]; then
  echo "Script '$script_to_run' exists. Executing..."
  bash "$script_to_run"
  if [ $? -eq 0 ]; then
    echo "Script '$script_to_run' executed successfully."
  else
    echo "Script '$script_to_run' failed with exit code $?."
  fi
else
  echo "Error: Script '$script_to_run' does not exist. Continuing with the main script."
fi

echo "Script finished."

# Install Node
script_to_run="install_node.sh"

if [ -e "$script_to_run" ]; then
  echo "Script '$script_to_run' exists. Executing..."
  bash "$script_to_run"
  if [ $? -eq 0 ]; then
    echo "Script '$script_to_run' executed successfully."
  else
    echo "Script '$script_to_run' failed with exit code $?."
  fi
else
  echo "Error: Script '$script_to_run' does not exist. Continuing with the main script."
fi

echo "Script finished."


# Install Starship prompt
curl -sS https://starship.rs/install.sh | sh

exit 0
