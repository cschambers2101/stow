#!/usr/bin/env bash
# Alias for install.sh, because "run the update script" is how an existing
# machine is talked about. One script does both.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || HERE=""
if [ -n "$HERE" ] && [ -f "$HERE/install.sh" ]; then
    exec bash "$HERE/install.sh" "$@"
fi
exec bash <(wget -qO- https://raw.githubusercontent.com/cschambers2101/stow/main/install_programs/install.sh) "$@"
