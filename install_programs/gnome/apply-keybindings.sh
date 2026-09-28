#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
apt-get install -y --no-install-recommends gnome-system-monitor
install -Dm0644 "$here/dconf-profile-user" /etc/dconf/profile/user
install -Dm0644 "$here/20-s6c-keybindings" /etc/dconf/db/local.d/20-s6c-keybindings
install -Dm0755 "$here/s6c-gnome-keys" /usr/local/bin/s6c-gnome-keys
dconf update
echo "done: log out and back in to pick up the new defaults"
