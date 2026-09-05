#!/usr/bin/env bash
# Mount a Google Drive remote with rclone as a user systemd service, then wire it into setup-suspend.sh.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

REMOTE_NAME="gdrive_s6c"
MOUNT_DIR="$HOME/gdrive_s6c"
SERVICE_FILE="$HOME/.config/systemd/user/rclone-mount.service"

echo "--- Google Drive (rclone) setup ---"

echo "[1/6] Installing rclone and fuse3..."
apt_update
apt_install rclone fuse3

echo "[2/6] Creating mount directory at $MOUNT_DIR..."
mkdir -p "$MOUNT_DIR"

echo "[3/6] Starting Rclone configuration..."
echo "IMPORTANT: Name your remote '$REMOTE_NAME' when prompted!"
echo "SELECT ALL DEFAULTS"
sleep 2
rclone config

echo "[4/6] Creating background service..."
mkdir -p "$(dirname "$SERVICE_FILE")"

cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Rclone Google Drive Mount
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount $REMOTE_NAME: $MOUNT_DIR --vfs-cache-mode writes --vfs-cache-max-age 24h --vfs-cache-max-size 10G --vfs-read-chunk-size 32M
ExecStop=/usr/bin/fusermount -uz $MOUNT_DIR
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

echo "[5/6] Enabling and starting the service..."
systemctl --user daemon-reload
systemctl --user enable rclone-mount.service
systemctl --user start rclone-mount.service

echo "[6/6] Stopping the mount around suspend/resume..."
bash "$HERE/setup-suspend.sh" || warn "setup-suspend.sh failed - stop the mount by hand before suspending."

echo "--- Setup Complete! ---"
echo "Your Google Drive is now mounted at $MOUNT_DIR"
echo "It will automatically reconnect every time you open the Linux terminal."
