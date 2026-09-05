#!/bin/bash
# last updated July 4, 2023... “We will not go quietly into the night..."

# Install core dependencies
sudo apt-get install -y python3-cffi libpangocairo-1.0-0 --reinstall

# Install Qtile
# pip3 install qtile==0.22.1 --force-reinstall
pip install git+https://github.com/qtile/qtile --break-system-packages --force-reinstall
pip install psutil --break-system-packages --force-reinstall


# Create a desktop entry for Qtile
echo "[Desktop Entry]
Name=Qtile
Comment=Qtile Session
Exec=qtile start
Type=Application
Keywords=wm;tiling" | sudo tee /usr/share/xsessions/qtile.desktop

echo "Qtile installation completed successfully. You can select Qtile from your session manager."
