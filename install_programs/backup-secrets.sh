#!/usr/bin/env bash
# Back up / restore the things that are not in git (ssh, gpg, rclone, keyrings, wifi profiles).
# Usage: backup-secrets.sh backup [outfile.tar.gz.gpg] | restore <infile.tar.gz.gpg>

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

MODE="${1:-}"
STAMP="$(date +%Y-%m-%d)"
DEFAULT_OUT="$HOME/secrets-backup-$(hostname)-$STAMP.tar.gz.gpg"

PATHS=(
    .ssh
    .gnupg
    .config/rclone
    .pki
    .local/share/keyrings
    .config/gh
    .claude/.credentials.json
    .claude.json
    .netrc
    .git-credentials
    .gitconfig
)

usage() {
    echo "Usage: $0 backup [outfile.tar.gz.gpg]"
    echo "       $0 restore <infile.tar.gz.gpg>"
    exit 1
}

do_backup() {
    local out="${1:-$DEFAULT_OUT}"
    staging="$(mktemp -d)"
    trap 'rm -rf "$staging"' EXIT

    echo "Collecting..."
    mkdir -p "$staging/home"
    local found=0
    for p in "${PATHS[@]}"; do
        if [ -e "$HOME/$p" ]; then
            printf '    %-28s %s\n' "$p" "$(du -sh "$HOME/$p" 2>/dev/null | cut -f1)"
            mkdir -p "$staging/home/$(dirname "$p")"
            cp -a "$HOME/$p" "$staging/home/$(dirname "$p")/"
            found=1
        else
            printf '    %-28s (absent, skipped)\n' "$p"
        fi
    done

    if [ -d /etc/NetworkManager/system-connections ]; then
        if sudo true 2>/dev/null; then
            echo "    NetworkManager profiles"
            mkdir -p "$staging/etc-NetworkManager"
            if sudo cp -a /etc/NetworkManager/system-connections/. \
                    "$staging/etc-NetworkManager/" 2>/dev/null \
               && sudo chown -R "$(id -u):$(id -g)" "$staging/etc-NetworkManager"; then
                :
            else
                echo "    WARNING: could not read NetworkManager profiles — skipped."
                rm -rf "$staging/etc-NetworkManager"
            fi
        else
            echo "    WARNING: no sudo — wifi/VPN profiles NOT backed up."
            echo "    WARNING: this archive will NOT restore your wifi."
        fi
    fi

    if [ "$found" -eq 0 ] && [ ! -d "$staging/etc-NetworkManager" ]; then
        echo "Nothing found to back up."
        exit 1
    fi

    echo ""
    echo "Encrypting to $out"
    echo "Choose a LONG passphrase — this archive is your whole identity."
    tar -czf - -C "$staging" . \
        | gpg --symmetric --cipher-algo AES256 --output "$out"

    chmod 600 "$out"
    echo ""
    echo "Done: $out  ($(du -h "$out" | cut -f1))"
    echo ""
    echo "Now get it OFF this machine. Any of:"
    echo "    rclone copy \"$out\" gdrive-personal:backups/"
    echo "    cp \"$out\" /media/\$USER/<usb-stick>/"
    echo ""
    echo "Verify it before you wipe anything:"
    echo "    gpg --decrypt \"$out\" | tar -tzf - | head"
}

do_restore() {
    local in="${1:-}"
    [ -n "$in" ] || usage
    [ -f "$in" ] || { echo "ERROR: $in not found."; exit 1; }

    echo "Restoring from $in ..."
    staging="$(mktemp -d)"
    trap 'rm -rf "$staging"' EXIT

    gpg --decrypt "$in" | tar -xzf - -C "$staging"

    for p in "${PATHS[@]}"; do
        if [ -e "$staging/home/$p" ]; then
            echo "    $p"
            mkdir -p "$(dirname "$HOME/$p")"
            cp -a "$staging/home/$p" "$(dirname "$HOME/$p")/"
        fi
    done

    if [ -d "$HOME/.ssh" ]; then
        chmod 700 "$HOME/.ssh"
        find "$HOME/.ssh" -type f -name 'id_*' ! -name '*.pub' -exec chmod 600 {} +
    fi
    if [ -d "$HOME/.gnupg" ]; then chmod 700 "$HOME/.gnupg"; fi

    if [ -d "$staging/etc-NetworkManager" ]; then
        echo "    NetworkManager profiles"
        sudo cp -a "$staging/etc-NetworkManager/." \
            /etc/NetworkManager/system-connections/
        sudo chown -R root:root /etc/NetworkManager/system-connections
        sudo chmod 600 /etc/NetworkManager/system-connections/*.nmconnection 2>/dev/null || true
        sudo systemctl reload NetworkManager 2>/dev/null || true
    fi

    echo ""
    echo "Restored. Check it worked:"
    echo "    ssh -T git@github.com"
    echo "    rclone listremotes"
}

case "$MODE" in
    backup)  shift; do_backup "$@" ;;
    restore) shift; do_restore "$@" ;;
    *)       usage ;;
esac
