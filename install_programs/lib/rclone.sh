#!/usr/bin/env bash
# shellcheck shell=bash
[ -n "${S6C_RCLONE_LOADED:-}" ] && return 0
S6C_RCLONE_LOADED=1
# shellcheck source=common.sh
[ -n "${S6C_COMMON_LOADED:-}" ] || . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

RCLONE_REMOTE="${S6C_RCLONE_REMOTE:-gdrive_s6c}"
RCLONE_MOUNT_DIR="${S6C_RCLONE_MOUNT_DIR:-$HOME/gdrive_s6c}"
RCLONE_UNIT="${S6C_RCLONE_UNIT:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/rclone-mount.service}"
RCLONE_UNIT_DIR="$(dirname "$RCLONE_UNIT")"
RCLONE_REWARM_INTERVAL="${S6C_RCLONE_REWARM_INTERVAL:-15min}"
RCLONE_RC_SOCKET_MIN="1.75.1"
RCLONE_WARM_DIR="${S6C_RCLONE_WARM_DIR:-claude_cowork}"
RCLONE_MOUNT_FLAGS="--vfs-cache-mode full --vfs-cache-max-age 24h --vfs-cache-max-size 10G --vfs-read-chunk-size 32M --dir-cache-time 1000h --poll-interval 1m"
RCLONE_MOUNT_WAIT="${S6C_RCLONE_MOUNT_WAIT:-60}"

rclone_remote_configured() {
    local remotes
    have_cmd rclone || return 1
    remotes="$(rclone listremotes 2>/dev/null || true)"
    printf '%s\n' "$remotes" | grep -qx "$RCLONE_REMOTE:"
}

# 1.74+ refuses unauthenticated rc calls; a socket in the 0700 runtime dir keeps --rc-no-auth
# private and out of reach of browsers. 1.60 has no socket support, so it keeps the TCP port.
rclone_rc_uses_socket() {
    local v; v="$(rclone_installed_version)"
    [ -n "$v" ] && dpkg --compare-versions "$v" ge "$RCLONE_RC_SOCKET_MIN"
}

rclone_rc_serve_flags() {
    if rclone_rc_uses_socket; then
        printf '%s' '--rc --rc-addr unix://%t/rclone-rc.sock --rc-no-auth'
    else
        printf '%s' '--rc --rc-addr 127.0.0.1:5572'
    fi
}

rclone_rc_client_flags() {
    if rclone_rc_uses_socket; then
        printf '%s' '--unix-socket %t/rclone-rc.sock'
    else
        printf '%s' '--url 127.0.0.1:5572'
    fi
}

rclone_unit_text() {
    local pre=""
    if rclone_rc_uses_socket; then
        pre="# rclone leaves its socket behind when a start fails (DNS not up at login or resume),
# and every retry then fails to bind it.
ExecStartPre=/bin/rm -f %t/rclone-rc.sock
"
    fi
    cat <<UNIT
[Unit]
Description=Rclone Google Drive Mount
After=network-online.target
# Separate units so a failed warm-up never takes the mount down.
Wants=rclone-warm.service rclone-rewarm.timer

[Service]
Type=simple
${pre}# Long dir cache is safe because --poll-interval pulls Drive changes every minute.
ExecStart=/usr/bin/rclone mount $RCLONE_REMOTE: $RCLONE_MOUNT_DIR $RCLONE_MOUNT_FLAGS $(rclone_rc_serve_flags)
ExecStop=/usr/bin/fusermount -uz $RCLONE_MOUNT_DIR
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
UNIT
}

# Listings are cached only once something walks them; warm them when the mount starts.
rclone_warm_unit_text() {
    local rc; rc="$(rclone_rc_client_flags)"
    cat <<UNIT
[Unit]
Description=Warm the rclone Google Drive directory cache
After=rclone-mount.service
PartOf=rclone-mount.service

[Service]
Type=oneshot
# The rc server answers before the VFS exists, so wait for the VFS itself.
ExecStartPre=/bin/sh -c 'for i in \$\$(seq 60); do /usr/bin/rclone rc $rc vfs/list 2>/dev/null | grep -q $RCLONE_REMOTE && exit 0; sleep 1; done; exit 1'
# Synchronous: an _async root refresh reports success but leaves the cache cold on 1.60.
# The workspace goes first so it is warm soonest, then the rest of the Drive.
ExecStart=/usr/bin/rclone rc $rc vfs/refresh dir=$RCLONE_WARM_DIR recursive=true
ExecStart=/usr/bin/rclone rc $rc vfs/refresh recursive=true
TimeoutStartSec=30min
UNIT
}

rclone_installed_version() { dpkg-query -W -f='${Version}' rclone 2>/dev/null || true; }

rclone_install_pinned() {
    local cur arch sum tmp deb
    cur="$(rclone_installed_version)"
    if [ -n "$cur" ] && ! dpkg --compare-versions "$cur" lt "$RCLONE_VERSION"; then
        return 1
    fi
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        warn "rclone ${cur:-not installed} is behind the pinned $RCLONE_VERSION, but there is no sudo to install it - re-run from a terminal."
        return 1
    fi
    arch="$(dpkg --print-architecture)"
    case "$arch" in
        amd64) sum="$RCLONE_DEB_SHA256_amd64" ;;
        arm64) sum="$RCLONE_DEB_SHA256_arm64" ;;
        *) warn "no pinned rclone .deb for $arch - staying on rclone ${cur:-from apt}"; return 1 ;;
    esac
    tmp="$(mktemp -d)"
    deb="$tmp/rclone-v$RCLONE_VERSION-linux-$arch.deb"
    if ! curl -fsSL --retry 3 --connect-timeout 20 -o "$deb" "https://downloads.rclone.org/v$RCLONE_VERSION/rclone-v$RCLONE_VERSION-linux-$arch.deb"; then
        rm -rf "$tmp"
        warn "could not download rclone $RCLONE_VERSION - staying on ${cur:-no rclone}"
        return 1
    fi
    if ! printf '%s  %s\n' "$sum" "$deb" | sha256sum -c --quiet >/dev/null 2>&1; then
        rm -rf "$tmp"
        warn "rclone $RCLONE_VERSION .deb failed its SHA256 check - NOT installed. Confirm against downloads.rclone.org/v$RCLONE_VERSION/SHA256SUMS before changing the pin in lib/common.sh."
        return 1
    fi
    chmod 755 "$tmp"
    chmod 644 "$deb"
    log "Installing rclone $RCLONE_VERSION (was ${cur:-not installed})..."
    if ! sudo apt-get install -y "$deb"; then
        rm -rf "$tmp"
        warn "rclone $RCLONE_VERSION did not install - staying on ${cur:-no rclone}"
        return 1
    fi
    rm -rf "$tmp"
    return 0
}

# Drive change polling drops the listing of every folder it reports as changed, and a busy
# workspace goes partly cold again within hours, so re-warm it on a timer.
rclone_rewarm_unit_text() {
    local rc; rc="$(rclone_rc_client_flags)"
    cat <<UNIT
[Unit]
Description=Re-warm the rclone directory cache for $RCLONE_WARM_DIR
After=rclone-mount.service
Requisite=rclone-mount.service

[Service]
Type=oneshot
ExecStart=/usr/bin/rclone rc $rc vfs/refresh dir=$RCLONE_WARM_DIR recursive=true
TimeoutStartSec=10min
UNIT
}

rclone_rewarm_timer_text() {
    cat <<UNIT
[Unit]
Description=Re-warm the rclone directory cache every $RCLONE_REWARM_INTERVAL
PartOf=rclone-mount.service

[Timer]
OnActiveSec=$RCLONE_REWARM_INTERVAL
OnUnitActiveSec=$RCLONE_REWARM_INTERVAL
UNIT
}

rclone_write_unit() {
    local path="$1" want="$2"
    [ -f "$path" ] && [ "$want" = "$(cat "$path")" ] && return 1
    [ -f "$path" ] && cp -a "$path" "$path.bak-$(date -u +%Y%m%dT%H%M%SZ)"
    printf '%s\n' "$want" > "$path"
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
    local changed=no
    if ! rclone_remote_configured; then
        log "no '$RCLONE_REMOTE' rclone remote on this machine - Drive mount skipped (set one up with: install.sh --drive)"
        return 0
    fi
    mkdir -p "$RCLONE_MOUNT_DIR" "$(dirname "$RCLONE_UNIT")"
    if rclone_install_pinned; then
        changed=yes
    fi
    rclone_write_unit "$RCLONE_UNIT" "$(rclone_unit_text)" && changed=yes
    rclone_write_unit "$RCLONE_UNIT_DIR/rclone-warm.service" "$(rclone_warm_unit_text)" && changed=yes
    rclone_write_unit "$RCLONE_UNIT_DIR/rclone-rewarm.service" "$(rclone_rewarm_unit_text)" && changed=yes
    rclone_write_unit "$RCLONE_UNIT_DIR/rclone-rewarm.timer" "$(rclone_rewarm_timer_text)" && changed=yes
    systemctl --user daemon-reload || warn "systemctl --user daemon-reload failed"
    systemctl --user enable rclone-mount.service >/dev/null 2>&1 || true
    if [ "$changed" = yes ]; then
        log "rclone or its units changed - restarting the mount"
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
    apt_install fuse3
    rclone_install_pinned || true
    have_cmd rclone || apt_install rclone
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
