#!/bin/bash

# Ensure we're running as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run with sudo"
  exit
fi

echo "--- Initializing NVIDIA Setup for Ubuntu 26.04 (Kernel 7.0+) ---"

# 1. Install Kernel Headers and Build Essentials
# Crucial for building the NVIDIA modules against the new Kernel 7.0
apt update
apt install -y build-essential dkms "linux-headers-$(uname -r)"

# 2. Install the recommended NVIDIA driver for whatever GPU is present
# Do NOT pin a version. `ubuntu-drivers install` (no version) detects the card
# and installs the driver ubuntu-drivers marks "recommended" — the -open flavour
# on Turing/Ampere and newer (e.g. 595-open on an RTX 3060), matching NVIDIA's
# own guidance, and whatever is right on any other card. --include-dkms signs
# the module correctly for Secure Boot.
echo "Detecting GPU and installing the recommended NVIDIA driver..."
ubuntu-drivers install --include-dkms || \
    ubuntu-drivers autoinstall || \
    echo "WARNING: NVIDIA driver install failed — check 'ubuntu-drivers devices'."

# 3. Bind NVIDIA to your existing Xorg setup
# This updates /etc/X11/xorg.conf to ensure Qtile uses the NVIDIA binary
echo "Configuring Xorg..."
nvidia-xconfig

# 4. Rebuild Initramfs with Dracut
# NOTE: 26.04 replaced 'update-initramfs' with 'dracut'. 
# This ensures the NVIDIA modules load early in the boot process.
echo "Refreshing initramfs via dracut..."
dracut -f

# 5. Blacklist Nouveau (Safety Check)
echo "Blacklisting Nouveau..."
cat <<EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

echo "--- Setup Complete ---"
echo "IMPORTANT: On reboot, you will see a blue 'MOK Management' screen."
echo "1. Select 'Enroll MOK'"
echo "2. Select 'Continue' -> 'Yes'"
echo "3. Enter the password you set during the driver install"
echo "4. Reboot"
echo ""
echo "After rebooting, run 'nvidia-smi' to verify."