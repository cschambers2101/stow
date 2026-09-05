#!/bin/bash

# Default values
REMOTE_NAME="gdrive_s6c"
MOUNT_DIR="$HOME/gdrive_s6c"
SERVICE_FILE="$HOME/.config/systemd/user/rclone-mount.service"

echo "--- Google Drive Setup for Chromebook (Linux) ---"

# 1. Install Dependencies
echo "[1/6] Installing rclone and fuse3..."
sudo apt update && sudo apt install -y rclone fuse3

# 2. Create Mount Directory
echo "[2/6] Creating mount directory at $MOUNT_DIR..."
mkdir -p "$MOUNT_DIR"

# 3. Configure Rclone
echo "[3/6] Starting Rclone configuration..."
echo "IMPORTANT: Name your remote '$REMOTE_NAME' when prompted!"
echo "SELECT ALL DEFAULTS"
sleep 2
rclone config

# 4. Create the systemd Service File
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

# 5. Enable and Start the Service
echo "[5/6] Enabling and starting the service..."
systemctl --user daemon-reload
systemctl --user enable rclone-mount.service
systemctl --user start rclone-mount.service

# 6. Keep the mount out of the way of suspend. A live FUSE mount holds tasks in
# D state, the kernel freezer gives up, and the machine never sleeps (proved on
# 18WessexUbuntu, 5 Sep 2026). setup-suspend.sh installs a system unit that
# stops this mount before sleep and starts it again after resume.
echo "[6/6] Stopping the mount around suspend/resume..."
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$HERE/setup-suspend.sh" ]; then
    bash "$HERE/setup-suspend.sh" || echo "WARNING: setup-suspend.sh failed — stop the mount by hand before suspending." >&2
fi

echo "--- Setup Complete! ---"
echo "Your Google Drive is now mounted at $MOUNT_DIR"
echo "It will automatically reconnect every time you open the Linux terminal."
