#!/bin/bash

# SDDM Eucalyptus Drop Setup Script
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' 

echo -e "${BLUE}Starting SDDM Eucalyptus Drop Theme Setup...${NC}"

# 1. Root Check
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root (use sudo).${NC}"
   exit 1
fi

REAL_USER=${SUDO_USER:-$USER}

# 2. Dependency Check
echo -e "${BLUE}Ensuring dependencies are installed...${NC}"
apt update
apt install -y sddm qml6-module-qt5compat-graphicaleffects qml6-module-qtquick-controls qml6-module-qtquick-layouts git

# 3. Path Definitions
THEME_DIR="/usr/share/sddm/themes"
TARGET_DIR="$THEME_DIR/eucalyptus-drop"
TEMP_CLONE="/tmp/sddm-eucalyptus-drop"

# 4. Clone from GitLab
echo -e "${BLUE}Cloning theme from GitLab...${NC}"
[ -d "$TARGET_DIR" ] && rm -rf "$TARGET_DIR"
rm -rf "$TEMP_CLONE"

# Using a standard git clone (GitLab public repos don't usually require the CLI handshake)
sudo -u "$REAL_USER" git clone https://gitlab.com/Matt.Jolly/sddm-eucalyptus-drop.git "$TEMP_CLONE"

# Move to system directory
mv "$TEMP_CLONE" "$TARGET_DIR"

# Abort config if the clone didn't actually produce a valid theme
if [ ! -f "$TARGET_DIR/Main.qml" ]; then
    echo -e "${RED}Error: theme clone appears incomplete — Main.qml missing.${NC}"
    exit 1
fi

# 5. SDDM Configuration
# Overwrite sddm.conf directly — this is a fresh machine and /etc/sddm.conf
# has the highest config precedence, so this is the most reliable approach.
echo -e "${BLUE}Writing SDDM theme configuration...${NC}"
cat > /etc/sddm.conf <<EOF
[Theme]
Current=eucalyptus-drop
EOF

# 6. Set Permissions
chmod -R 755 "$TARGET_DIR"

echo -e "${GREEN}Success! Eucalyptus Drop is now installed.${NC}"
echo -e "You can preview it by running: ${BLUE}sddm-greeter --test-mode --theme $TARGET_DIR${NC}"
