#!/usr/bin/env bash
# shellcheck shell=bash
[ -n "${S6C_RCLONE_LOADED:-}" ] && return 0
S6C_RCLONE_LOADED=1
# shellcheck source=common.sh
[ -n "${S6C_COMMON_LOADED:-}" ] || . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

RCLONE_REMOTE="${S6C_RCLONE_REMOTE:-gdrive_s6c}"
RCLONE_MOUNT_DIR="${S6C_RCLONE_MOUNT_DIR:-$HOME/gdrive_s6c}"
RCLONE_UNIT="${S6C_RCLONE_UNIT:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/rclone-mount.service}"
RCLONE_MOUNT_FLAGS="--vfs-cache-mode full --vfs-cache-max-age 24h --vfs-cache-max-size 10G --vfs-read-chunk-size 32M --dir-cache-time 1h --poll-interval 1m"
RCLONE_MOUNT_WAIT="${S6C_RCLONE_MOUNT_WAIT:-60}"

rclone_remote_configured() {
    local remotes
    have_cmd rclone || return 1
    remotes="$(rclone listremotes 2>/dev/null || true)"
    printf '%s\n' "$remotes" | grep -qx "$RCLONE_REMOTE:"
}

rclone_unit_text() {
    cat <<UNIT
[Unit]
Description=Rclone Google Drive Mount
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount $RCLONE_REMOTE: $RCLONE_MOUNT_DIR $RCLONE_MOUNT_FLAGS
ExecStop=/usr/bin/fusermount -uz $RCLONE_MOUNT_DIR
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
UNIT
}

rclone_mounted() { mountpoint -q "$RCLONE_MOUNT_DIR" 2>/dev/null; }

rclone_wait_mounted() {
    local _i
    for _i in $(seq 1 "$RCLONE_MOUNT_WAIT"); do
        rclone_mounted && return 0
        sleep 1
    done
    return 1
}

rclone_converge_mount() {
    local want changed=no
    if ! rclone_remote_configured; then
        log "no '$RCLONE_REMOTE' rclone remote on this machine - Drive mount skipped (set one up with: install.sh --drive)"
        return 0
    fi
    mkdir -p "$RCLONE_MOUNT_DIR" "$(dirname "$RCLONE_UNIT")"
    want="$(rclone_unit_text)"
    if [ ! -f "$RCLONE_UNIT" ] || [ "$want" != "$(cat "$RCLONE_UNIT")" ]; then
        [ -f "$RCLONE_UNIT" ] && cp -a "$RCLONE_UNIT" "$RCLONE_UNIT.bak-$(date -u +%Y%m%dT%H%M%SZ)"
        printf '%s\n' "$want" > "$RCLONE_UNIT"
        changed=yes
    fi
    systemctl --user daemon-reload || warn "systemctl --user daemon-reload failed"
    systemctl --user enable rclone-mount.service >/dev/null 2>&1 || true
    if [ "$changed" = yes ]; then
        log "rclone-mount.service regenerated - restarting the mount"
    elif ! rclone_mounted; then
        log "rclone-mount.service unchanged but $RCLONE_MOUNT_DIR is not mounted - starting it"
    else
        log "rclone-mount.service current; $RCLONE_MOUNT_DIR mounted"
        return 0
    fi
    systemctl --user restart rclone-mount.service || warn "could not restart rclone-mount.service"
    if rclone_wait_mounted; then
        log "$RCLONE_MOUNT_DIR mounted"
    else
        warn "$RCLONE_MOUNT_DIR not mounted after ${RCLONE_MOUNT_WAIT}s. Check: systemctl --user status rclone-mount.service; journalctl --user -u rclone-mount.service -e"
    fi
    return 0
}

rclone_setup_drive() {
    [ -t 0 ] || die "--drive needs a terminal: rclone's Google sign-in is interactive."
    apt_update
    apt_install rclone fuse3
    mkdir -p "$RCLONE_MOUNT_DIR"
    if rclone_remote_configured; then
        log "rclone remote '$RCLONE_REMOTE' already configured"
    else
        log "Creating the rclone remote '$RCLONE_REMOTE'. A browser will open for the Google sign-in: use the account that owns the S6C Drive."
        rclone config create "$RCLONE_REMOTE" drive scope drive \
            || die "rclone could not create the '$RCLONE_REMOTE' remote - see above, then re-run with --drive."
        rclone_remote_configured || die "'$RCLONE_REMOTE' is not in 'rclone listremotes' after config create - re-run with --drive."
    fi
    rclone_converge_mount
    bash "$INSTALL_DIR/setup-suspend.sh" || warn "setup-suspend.sh failed - stop the mount by hand before suspending."
}
