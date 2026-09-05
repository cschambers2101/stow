#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

install_yt_dlp() {
    sudo wget -q "$YTDLP_URL" -O /usr/local/bin/yt-dlp || { warn "yt-dlp download failed."; return 0; }
    sudo chmod a+rx /usr/local/bin/yt-dlp
}

install_yt_dlp_timer() {
    write_root_file /etc/systemd/system/yt-dlp-update.service <<'UNIT'
[Unit]
Description=Update yt-dlp to the latest release
Documentation=https://github.com/yt-dlp/yt-dlp
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/yt-dlp -U
SuccessExitStatus=0 1
UNIT
    write_root_file /etc/systemd/system/yt-dlp-update.timer <<'UNIT'
[Unit]
Description=Daily yt-dlp update

[Timer]
OnCalendar=daily
RandomizedDelaySec=2h
Persistent=true

[Install]
WantedBy=timers.target
UNIT
    sudo systemctl daemon-reload
    sudo systemctl enable yt-dlp-update.timer
    sudo systemctl restart yt-dlp-update.timer
}

install_tpm() {
    [ -d "$HOME/.tmux/plugins/tpm" ] || git clone "$TPM_REPO" "$HOME/.tmux/plugins/tpm"
}

install_claude_code() {
    curl -fsSL "$CLAUDE_INSTALL_URL" | bash || warn "Claude Code install failed - install manually after reboot."
    json_set_default "$HOME/.claude.json" shiftEnterKeyBindingInstalled true || warn "could not seed shiftEnterKeyBindingInstalled."
}
