#!/bin/bash
# last updated July 4, 2023... “We will not go quietly into the night..."

# Update system
sudo apt-get update

# Install core dependencies
sudo apt-get install -y python3-cffi libpangocairo-1.0-0 --reinstall

# Install xcffib with pip
# pinning to this version since newer versions don't have ffi_build (I think renamed to just ffi):
#   https://github.com/tych0/xcffib/tree/v0.12.1/module
#   pip3 install xcffib==0.12.1

# Install cairocffi with pip
# The order of xcffib and cairocffi is important and the flags are important:
#   https://github.com/qtile/qtile/issues/994#issuecomment-497984551
# pip3 install --no-cache-dir --no-build-isolation cairocffi==1.4.0

# Install Qtile
# pip3 install qtile==0.22.1 --force-reinstall
pip install git+https://github.com/qtile/qtile --break-system-packages --force-reinstall



# Create a desktop entry for Qtile
echo "[Desktop Entry]
Name=Qtile
Comment=Qtile Session
Exec=qtile start
Type=Application
Keywords=wm;tiling" | sudo tee /usr/share/xsessions/qtile.desktop

echo "Qtile installation completed successfully. You can select Qtile from your session manager."
