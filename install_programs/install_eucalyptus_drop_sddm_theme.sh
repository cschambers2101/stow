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
apt install -y sddm qml-module-qtgraphicaleffects qml-module-qtquick-controls2 qml-module-qtquick-layouts git

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

# 5. SDDM Configuration
CONF_FILE="/etc/sddm.conf"
echo -e "${BLUE}Updating SDDM configuration...${NC}"

[ -f "$CONF_FILE" ] && cp "$CONF_FILE" "${CONF_FILE}.bak"

# Create the file if it doesn't exist
if [ ! -f "$CONF_FILE" ]; then
    touch "$CONF_FILE"
fi

# Modern Section-Aware Editing
if ! grep -q "^\[Theme\]" "$CONF_FILE" 2>/dev/null; then
    echo -e "\n[Theme]\nCurrent=eucalyptus-drop" >> "$CONF_FILE"
else
    # Delete everything inside existing [Theme] section and reset it
    sed -i '/^\[Theme\]/,/^\[/ { /^\[Theme\]/! { /^\[/! d } }' "$CONF_FILE"
    sed -i '/^\[Theme\]/a Current=eucalyptus-drop' "$CONF_FILE"
fi

# 6. Set Permissions
chmod -R 755 "$TARGET_DIR"

echo -e "${GREEN}Success! Eucalyptus Drop is now installed.${NC}"
echo -e "You can preview it by running: ${BLUE}sddm-greeter --test-mode --theme $TARGET_DIR${NC}"
