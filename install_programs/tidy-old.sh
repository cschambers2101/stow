#!/usr/bin/env bash
# One-off tidy for a machine stowed before September 2026: pull, drop stale links, restow.
# Usage: bash ~/.dotfiles/install_programs/tidy-old.sh [--no-pull]

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

PULL=yes
[ "${1:-}" = --no-pull ] && PULL=no

require_not_root
require_cmds git stow

if [ "$PULL" = yes ]; then
    section "Pulling $DOTFILES_DIR"
    if [ -n "$(git -C "$DOTFILES_DIR" status --porcelain)" ]; then
        warn "working tree has local changes - pulling with --ff-only anyway; resolve by hand if it refuses."
    fi
    git -C "$DOTFILES_DIR" pull --ff-only || die "pull failed - fix $DOTFILES_DIR and re-run."
fi

section "Removing links the old layout created"
removed=0
for link in "$HOME/install_programs" "$HOME/README.md" "$HOME/_archive"; do
    if [ -L "$link" ]; then
        rm -v "$link"; removed=$((removed + 1))
    fi
done
while IFS= read -r link; do
    rm -v "$link"; removed=$((removed + 1))
done < <(find "$HOME" "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share" -maxdepth 1 -xtype l -lname '*.dotfiles*' 2>/dev/null)
log "removed $removed stale link(s)"

section "Moving aside real files the repo now owns"
for d in niri DankMaterialShell danksearch alacritty; do
    if [ -e "$HOME/.config/$d" ] && [ ! -L "$HOME/.config/$d" ]; then
        mv -v "$HOME/.config/$d" "$HOME/.config/$d.pre-stow.bak"
    fi
done
cd "$DOTFILES_DIR"
while IFS= read -r f; do
    if [ -f "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
        mv -v "$HOME/$f" "$HOME/$f.pre-stow.bak"
    fi
done < <(find . -maxdepth 1 -type f -name '.*' -printf '%f\n')

section "Restowing"
conflicts="$(stow -n -R . 2>&1 | grep -v 'in simulation mode' || true)"
if [ -n "$conflicts" ]; then
    warn "stow reported conflicts:"
    printf '%s\n' "$conflicts" | sed 's/^/    /' >&2
    die "resolve the above, then run 'stow -R .' in $DOTFILES_DIR."
fi
stow -R .
log "restowed from $(git -C "$DOTFILES_DIR" log --oneline -1)"

section "Check"
left="$(find "$HOME" "$HOME/.config" "$HOME/.local/bin" -maxdepth 1 -xtype l -lname '*.dotfiles*' 2>/dev/null || true)"
[ -z "$left" ] && log "no dangling dotfiles links" || warn "still dangling: $left"
[ -x "$HOME/.local/bin/dank-lock.sh" ] && log "dank-lock.sh is executable" || warn "dank-lock.sh is not executable - run 'git -C $DOTFILES_DIR pull'"
[ -e "$HOME/install_programs" ] && warn "$HOME/install_programs still exists" || log "$HOME/install_programs gone"
ls -d "$HOME"/.config/*.pre-stow.bak "$HOME"/.*.pre-stow.bak 2>/dev/null | sed 's/^/moved aside: /' || true
log "done. Open a new terminal to pick up the shell changes."
