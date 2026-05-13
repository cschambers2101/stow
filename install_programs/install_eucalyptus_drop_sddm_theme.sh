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
mkdir -p "$THEME_DIR"
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

# 6. Random background: pick one on every SDDM launch via a systemd drop-in.
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
BACKGROUNDS_SRC="$REAL_HOME/.local/share/backgrounds"
BG_SCRIPT="/usr/local/bin/sddm-random-background.sh"

echo -e "${BLUE}Installing random background picker...${NC}"
cat > "$BG_SCRIPT" <<BGSCRIPT
#!/bin/bash
BACKGROUNDS_DIR="$BACKGROUNDS_SRC"
THEME_CONF="$TARGET_DIR/theme.conf"
DEST_DIR="$TARGET_DIR/Backgrounds"
DEST="\$DEST_DIR/random-login-bg"

# User backgrounds first, then Ubuntu system wallpapers as fallback.
mapfile -t files < <(
    find "\$BACKGROUNDS_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) 2>/dev/null
    find /usr/share/backgrounds -maxdepth 2 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) 2>/dev/null
)
[ \${#files[@]} -eq 0 ] && exit 0

chosen="\${files[RANDOM % \${#files[@]}]}"
ext="\${chosen##*.}"

mkdir -p "\$DEST_DIR"
rm -f "\${DEST}".* 2>/dev/null || true
cp "\$chosen" "\${DEST}.\${ext}"

if grep -qi "^background=" "\$THEME_CONF" 2>/dev/null; then
    sed -i "s|^[Bb]ackground=.*|background=Backgrounds/random-login-bg.\${ext}|" "\$THEME_CONF"
elif grep -q "^\[General\]" "\$THEME_CONF" 2>/dev/null; then
    # Insert after [General] so the key is inside the correct section.
    sed -i "/^\[General\]/a background=Backgrounds/random-login-bg.\${ext}" "\$THEME_CONF"
else
    printf '[General]\nbackground=Backgrounds/random-login-bg.\${ext}\n' >> "\$THEME_CONF"
fi
BGSCRIPT
chmod +x "$BG_SCRIPT"

# Systemd drop-in so the script runs before SDDM starts on every boot.
mkdir -p /etc/systemd/system/sddm.service.d/
cat > /etc/systemd/system/sddm.service.d/random-background.conf <<EOF
[Service]
ExecStartPre=$BG_SCRIPT
EOF
systemctl daemon-reload

# Run once now so the theme has a background immediately.
bash "$BG_SCRIPT"

# 7. Set Permissions
chmod -R 755 "$TARGET_DIR"

echo -e "${GREEN}Success! Eucalyptus Drop is now installed.${NC}"
echo -e "A random background from ${BLUE}$BACKGROUNDS_SRC${NC} will be applied on every login screen."
echo -e "You can preview it by running: ${BLUE}sddm-greeter --test-mode --theme $TARGET_DIR${NC}"
