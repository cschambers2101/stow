#!/usr/bin/env bash
# Kept forever, and NOT because anyone should run it. Machines built before
# 8 Sep 2026 hardcode this filename in their self-update re-exec, and
# `git checkout origin/main -- install_programs/` does not delete a file the new
# tree lacks -- so without this shim the stale copy survives on disk, gets
# re-execed, and the machine silently runs old code while reporting success.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || HERE=""
if [ -n "$HERE" ] && [ -f "$HERE/install.sh" ]; then
    exec bash "$HERE/install.sh" "$@"
fi
exec bash <(wget -qO- https://raw.githubusercontent.com/cschambers2101/stow/main/install_programs/install.sh) "$@"
