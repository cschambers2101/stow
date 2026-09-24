#!/usr/bin/env bash
# Mount the S6C Google Drive with rclone as a user systemd service. Same as: install.sh --drive
# Usage: bash setup_rclone_for_google_drive.sh

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"
# shellcheck source=lib/rclone.sh
. "$HERE/lib/rclone.sh"

echo "--- Google Drive (rclone) setup ---"
rclone_setup_drive
echo "--- Done. Your Google Drive is mounted at $RCLONE_MOUNT_DIR ---"
