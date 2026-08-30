#!/bin/bash

# =================================================================
# BACKUP / RESTORE THE THINGS THAT ARE NOT IN GIT
#
# Everything else on this machine is reproducible: the dotfiles come
# from the repo, the packages come from apt. These do not, and losing
# them means locking yourself out.
#
#   ./backup-secrets.sh backup  [outfile.tar.gz.gpg]
#   ./backup-secrets.sh restore <infile.tar.gz.gpg>
#
# The archive is symmetrically encrypted with gpg (AES256) and is safe
# to put on Google Drive, a USB stick, or anywhere else. It is only as
# safe as the passphrase you choose, so choose a long one.
#
# CHICKEN AND EGG: restore ~/.ssh BEFORE you try to clone anything with
# an SSH remote. bootstrap.sh avoids this by cloning over HTTPS, so a
# rebuild does not depend on this archive at all — but your keys,
# rclone tokens and wifi passwords still do.
# =================================================================

set -euo pipefail

MODE="${1:-}"
STAMP="$(date +%Y-%m-%d)"
DEFAULT_OUT="$HOME/secrets-backup-$(hostname)-$STAMP.tar.gz.gpg"

# Paths are relative to $HOME. Missing ones are skipped, not fatal.
PATHS=(
    .ssh                      # 🔴 SSH keys. Without these you cannot push anywhere.
    .gnupg                    # GPG keyring (signed commits, encrypted files)
    .config/rclone            # OAuth tokens for gdrive-personal: and gdrive_s6c:
    .pki                      # Chrome/NSS cert store, incl. the Oakford CA trust
    .local/share/keyrings     # gnome-keyring: NM secrets, saved passwords
    .config/gh                # gh CLI auth token
    .claude/.credentials.json # Claude Code login
    .claude.json              # Claude Code settings and project history
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
    # NOT `local`: the EXIT trap runs after the function has returned, where a
    # local is out of scope and `set -u` would abort on it.
    staging="$(mktemp -d)"
    trap 'rm -rf "$staging"' EXIT

    echo "Collecting..."
    # Stage everything under one tree so the tar and the restore are both
    # trivial: staging/home/<path> and staging/etc-NetworkManager/.
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

    # NetworkManager profiles live outside $HOME. The directory is world
    # readable but the .nmconnection files inside are root-owned 0600, so
    # copying them needs sudo. They hold every wifi PSK and VPN secret this
    # machine knows. Skipping them is a warning, not a failure — the rest of
    # the archive is still worth having.
    if [ -d /etc/NetworkManager/system-connections ]; then
        # `sudo true`, NOT `sudo -v`. Ubuntu 26.04's sudo-rs fails `sudo -v`
        # whenever credentials are not already cached, even where policy
        # would allow the command -- and with stderr suppressed that failure
        # is silent, so the wifi PSKs would be dropped from the archive
        # while the backup still reported success. `sudo true` uses the
        # cached timestamp if there is one and prompts if there is not.
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

    # Home-directory items.
    for p in "${PATHS[@]}"; do
        if [ -e "$staging/home/$p" ]; then
            echo "    $p"
            mkdir -p "$(dirname "$HOME/$p")"
            cp -a "$staging/home/$p" "$(dirname "$HOME/$p")/"
        fi
    done

    # Permissions matter: ssh refuses to use a key that others can read.
    if [ -d "$HOME/.ssh" ]; then
        chmod 700 "$HOME/.ssh"
        find "$HOME/.ssh" -type f -name 'id_*' ! -name '*.pub' -exec chmod 600 {} +
    fi
    if [ -d "$HOME/.gnupg" ]; then chmod 700 "$HOME/.gnupg"; fi

    # NetworkManager profiles must be root-owned 0600 or NM ignores them.
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
