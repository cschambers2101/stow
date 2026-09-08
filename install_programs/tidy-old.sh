#!/usr/bin/env bash
# Catch-up for a machine the installer has already built: bring it to the
# latest build. Pull, run any migrations the new commits need, drop stale
# links, restow, fix the git remote. Safe to re-run: every step is idempotent
# and does nothing when the machine is already current.
#
# Usage: bash ~/.dotfiles/install_programs/tidy-old.sh [--no-pull]

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

PULL=yes
[ "${1:-}" = --no-pull ] && PULL=no

require_not_root
require_cmds git stow

# --- self-update ---------------------------------------------------------------
# Chicken and egg: the migrations a new commit needs live in this script, but an
# old machine starts by running its OLD copy, which does not have them yet. The
# 8 Sep settings.json change proved it -- the old script hits a pull that
# refuses and dies before any migration can run. So refresh the build scripts
# from the remote first, then re-exec once. Only install_programs/ is refreshed;
# config files are left to the pull below.
if [ "$PULL" = yes ] && [ -z "${S6C_TIDY_REEXEC:-}" ]; then
    section "Self-update"
    if git -C "$DOTFILES_DIR" fetch --quiet origin 2>/dev/null; then
        if git -C "$DOTFILES_DIR" diff --quiet HEAD origin/main -- install_programs/; then
            log "build scripts already current"
        else
            log "newer build scripts on origin - refreshing and re-running"
            if git -C "$DOTFILES_DIR" checkout origin/main -- install_programs/; then
                exec env S6C_TIDY_REEXEC=1 bash "$HERE/tidy-old.sh" "$@"
            fi
            warn "could not refresh install_programs/ - continuing with what is on disk"
        fi
    else
        warn "fetch failed - continuing with the scripts already on disk"
    fi
fi

LIVE_DMS="$DOTFILES_DIR/.config/DankMaterialShell/settings.json"
PRESERVED=""

# --- migration: settings.json became untracked (8 Sep 2026) -------------------
# Before that commit the file was tracked, and DMS rewrites it constantly, so
# an old machine reaches this script with local modifications to a file the
# incoming commit deletes. Two things go wrong if that is not handled:
#
#   1. `git pull` refuses outright -- "local changes would be overwritten".
#   2. The obvious recovery, `git checkout -- <file>` then pull, DELETES the
#      live file, because the incoming commit removes it from the tree. That
#      is the user's whole DMS configuration: theme, bar layout, timeouts.
#
# So take a copy first, let the pull remove the tracked file, and put the copy
# back afterwards as an untracked file. Only fires while the file is still
# tracked, so re-running this script later is a no-op.
if [ "$PULL" = yes ] && git -C "$DOTFILES_DIR" ls-files --error-unmatch \
        .config/DankMaterialShell/settings.json >/dev/null 2>&1; then
    section "Migrating DankMaterialShell settings.json out of git"
    if [ -f "$LIVE_DMS" ]; then
        PRESERVED="$(mktemp -t dms-settings-XXXXXX.json)"
        cp "$LIVE_DMS" "$PRESERVED"
        log "preserved your live settings to $PRESERVED"
        git -C "$DOTFILES_DIR" checkout -- .config/DankMaterialShell/settings.json 2>/dev/null || true
    else
        log "no live settings.json to preserve"
    fi
fi

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

section "DankMaterialShell settings"
if [ -n "$PRESERVED" ] && [ -f "$PRESERVED" ]; then
    mkdir -p "$(dirname "$LIVE_DMS")"
    cp "$PRESERVED" "$LIVE_DMS"
    log "restored your live settings (now untracked, as DMS owns the file)"
    rm -f "$PRESERVED"
elif [ ! -f "$LIVE_DMS" ]; then
    # Second source: a machine whose ~/.config/DankMaterialShell was a real
    # directory gets it moved aside above, taking the live settings with it.
    bak="$HOME/.config/DankMaterialShell.pre-stow.bak/settings.json"
    if [ -f "$bak" ]; then
        mkdir -p "$(dirname "$LIVE_DMS")"
        cp "$bak" "$LIVE_DMS"
        log "recovered settings from $bak"
    fi
fi
# Merge in any S6C fleet keys this machine is missing. These no longer arrive by
# git pull, because the live file is untracked. Adds only what is absent, so a
# setting the user has changed is never overwritten.
json_seed_defaults "$HERE/dms-settings.s6c.json" "$LIVE_DMS" \
    || warn "could not seed the S6C DMS settings."

section "Git remote"
# Prefer SSH whenever the key authenticates. Machines built before 8 Sep 2026
# were pinned to HTTPS by the old s15_git_identity and could never get back,
# so this is the step that promotes them. Nothing interactive: no gh login.
if github_ssh_works; then
    log "GitHub SSH key authenticates - using the SSH remote."
    set_origin_protocol ssh "$DOTFILES_DIR" || warn "could not set origin to SSH."
else
    log "No GitHub-registered SSH key - staying on the HTTPS remote."
    set_origin_protocol https "$DOTFILES_DIR" || warn "could not set origin to HTTPS."
    if have_cmd gh && gh auth status -h github.com >/dev/null 2>&1; then
        gh auth setup-git -h github.com >/dev/null 2>&1 \
            && log "   gh is authorised - set as the git credential helper." \
            || warn "'gh auth setup-git' failed - HTTPS push will ask for a username."
    fi
fi

section "Check"
left="$(find "$HOME" "$HOME/.config" "$HOME/.local/bin" -maxdepth 1 -xtype l -lname '*.dotfiles*' 2>/dev/null || true)"
[ -z "$left" ] && log "no dangling dotfiles links" || warn "still dangling: $left"
[ -x "$HOME/.local/bin/dank-lock.sh" ] && log "dank-lock.sh is executable" || warn "dank-lock.sh is not executable - run 'git -C $DOTFILES_DIR pull'"
[ -e "$HOME/install_programs" ] && warn "$HOME/install_programs still exists" || log "$HOME/install_programs gone"
ls -d "$HOME"/.config/*.pre-stow.bak "$HOME"/.*.pre-stow.bak 2>/dev/null | sed 's/^/moved aside: /' || true
log "done. Open a new terminal to pick up the shell changes."
