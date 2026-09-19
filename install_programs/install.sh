#!/usr/bin/env bash
# S6C Ubuntu 26.04 build: the one entry point, for a new machine and an existing one.
#
#   bash <(wget -qO- https://raw.githubusercontent.com/cschambers2101/stow/main/install_programs/install.sh)
#   bash ~/.dotfiles/install_programs/install.sh
#
# Both forms do the same thing. The script works out what the machine needs:
# clone and full install, or converge on the latest build and update.
#
# Usage: install.sh [--strict] [--no-pull] [--greeter] [--help]
#
# On an existing machine it also runs the installer's update-safe sections, so a
# new package, driver or service reaches the machine. `ubuntu_26.04_niri_install.sh
# --list` marks the sections that stay install-only, with the reason.
#
# Phase A below is deliberately standalone -- no lib/common.sh -- because it has
# to run before the repo exists. It ends by re-execing the repo's own copy, so
# the rest always runs the newest code. Plan and reasoning:
# projects/linux-device-build-2026/notes/install-update-script-plan-2026-09-19.md

set -u

REPO_HTTPS="${S6C_REPO_HTTPS:-https://github.com/cschambers2101/stow.git}"
REPO_SSH="${S6C_REPO_SSH:-git@github.com:cschambers2101/stow.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
STATE_DIR="${S6C_STATE_DIR:-$HOME/.local/state/s6c}"
STAMP="$STATE_DIR/build"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
PRESERVE_DIR="$STATE_DIR/preserved/$TS"
PRESERVED_COUNT=0
DMS_REL=".config/DankMaterialShell/settings.json"
DMS_PRESERVED=""

STRICT=no
PULL=yes
FORCE_GREETER=no
for arg in "$@"; do
    case "$arg" in
        --strict)   STRICT=yes ;;
        --no-pull)  PULL=no ;;
        --greeter)  FORCE_GREETER=yes ;;
        --help|-h)  sed -n '2,10p' "$0"; exit 0 ;;
        *)          echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# --- Phase A: standalone -------------------------------------------------------
if [ -z "${S6C_INSTALL_PHASE_B:-}" ]; then
    a_say()  { printf '   %s\n' "$*"; }
    a_head() { printf '\n== %s ==\n' "$*"; }
    a_die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

    [ "$(id -u)" -eq 0 ] && a_die "run this as your normal user, not root."

    if ! command -v git >/dev/null 2>&1; then
        a_head "Installing git"
        sudo apt update && sudo apt install -y git || a_die "could not install git."
    fi

    if ssh -T -o BatchMode=yes -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=accept-new git@github.com 2>&1 |
            grep -q "successfully authenticated"; then
        REPO_URL="$REPO_SSH"
        a_say "GitHub SSH key detected - using the SSH remote."
    else
        REPO_URL="$REPO_HTTPS"
        a_say "No usable GitHub SSH key - using the HTTPS remote."
    fi

    keep() {
        # Copy a repo-relative path into the preserve directory, mirroring its path.
        local rel="$1" src="$DOTFILES_DIR/$1"
        [ -e "$src" ] || return 0
        mkdir -p "$PRESERVE_DIR/$(dirname "$rel")"
        cp -a "$src" "$PRESERVE_DIR/$rel" 2>/dev/null || return 0
        PRESERVED_COUNT=$((PRESERVED_COUNT + 1))
    }

    if [ -e "$DOTFILES_DIR" ] && [ ! -d "$DOTFILES_DIR/.git" ]; then
        a_head "Moving a non-git ~/.dotfiles aside"
        mkdir -p "$PRESERVE_DIR"
        mv "$DOTFILES_DIR" "$PRESERVE_DIR/dotfiles-not-a-git-checkout" \
            || a_die "could not move $DOTFILES_DIR aside."
        a_say "kept at $PRESERVE_DIR/dotfiles-not-a-git-checkout"
    fi

    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        a_head "Cloning the build"
        git clone "$REPO_URL" "$DOTFILES_DIR" || a_die "clone failed."
    elif [ "$PULL" = yes ]; then
        a_head "Bringing $DOTFILES_DIR to the latest build"
        git -C "$DOTFILES_DIR" remote set-url origin "$REPO_URL" 2>/dev/null || true

        # A --depth 1 clone cannot answer ahead/behind, and older machines have one.
        if [ "$(git -C "$DOTFILES_DIR" rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
            a_say "shallow clone - fetching full history so state can be read"
            git -C "$DOTFILES_DIR" fetch --unshallow --quiet origin 2>/dev/null || true
        fi
        git -C "$DOTFILES_DIR" fetch --quiet --prune origin \
            || a_die "cannot reach GitHub. Check the network and re-run."

        # settings.json is preserved and RESTORED (Phase B); everything else is
        # preserved and discarded, because the repo version wins.
        if git -C "$DOTFILES_DIR" ls-files --error-unmatch "$DMS_REL" >/dev/null 2>&1 \
                && [ -f "$DOTFILES_DIR/$DMS_REL" ]; then
            mkdir -p "$PRESERVE_DIR/$(dirname "$DMS_REL")"
            cp -a "$DOTFILES_DIR/$DMS_REL" "$PRESERVE_DIR/$DMS_REL"
            DMS_PRESERVED="$PRESERVE_DIR/$DMS_REL"
            a_say "preserved your DMS settings (they are restored after the update)"
        fi

        dirty="$(git -C "$DOTFILES_DIR" status --porcelain --untracked-files=no)"
        if [ -n "$dirty" ]; then
            if [ "$STRICT" = yes ]; then
                printf '%s\n' "$dirty" >&2
                a_die "--strict: local changes above. Commit or stash them, then re-run."
            fi
            while IFS= read -r rel; do
                [ -n "$rel" ] || continue
                [ "$rel" = "$DMS_REL" ] && continue
                # Build scripts are ours, never the user's. The pre-19-Sep
                # self-update stages install_programs/ before handing over, so
                # without this every migrating machine "preserves" six of our own
                # files and warns the student about changes they never made.
                case "$rel" in install_programs/*) continue ;; esac
                keep "$rel"
            done < <(git -C "$DOTFILES_DIR" diff --name-only HEAD)
            [ "$PRESERVED_COUNT" -gt 0 ] && a_say "set aside $PRESERVED_COUNT locally-changed file(s)"
        fi

        # An untracked file sitting where an incoming commit adds one blocks the
        # update. Move those, and only those, out of the way.
        while IFS= read -r rel; do
            [ -n "$rel" ] || continue
            if [ -e "$DOTFILES_DIR/$rel" ] &&
               ! git -C "$DOTFILES_DIR" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
                keep "$rel" && rm -rf "${DOTFILES_DIR:?}/$rel"
            fi
        done < <(git -C "$DOTFILES_DIR" diff --name-only --diff-filter=A HEAD origin/main 2>/dev/null)

        ahead="$(git -C "$DOTFILES_DIR" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)"
        if [ "${ahead:-0}" -gt 0 ]; then
            if [ "$STRICT" = yes ]; then
                a_die "--strict: $ahead local commit(s) not on origin. Push or drop them, then re-run."
            fi
            git -C "$DOTFILES_DIR" branch "s6c-local-$TS" >/dev/null 2>&1 || true
            a_say "$ahead local commit(s) kept on branch s6c-local-$TS"
        fi

        # One primitive for every case: behind, dirty, ahead or diverged.
        git -C "$DOTFILES_DIR" reset --hard --quiet origin/main \
            || a_die "could not converge on origin/main."
        a_say "now at $(git -C "$DOTFILES_DIR" log --oneline -1)"
    fi

    NEXT="$DOTFILES_DIR/install_programs/install.sh"
    [ -f "$NEXT" ] || a_die "$NEXT not found after the update."
    chmod +x "$NEXT" 2>/dev/null || true
    exec env S6C_INSTALL_PHASE_B=1 \
             S6C_PRESERVE_DIR="$PRESERVE_DIR" \
             S6C_PRESERVED_COUNT="$PRESERVED_COUNT" \
             S6C_DMS_PRESERVED="$DMS_PRESERVED" \
             S6C_TS="$TS" \
             bash "$NEXT" "$@"
fi

# --- Phase B: in-repo ----------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

PRESERVE_DIR="${S6C_PRESERVE_DIR:-$PRESERVE_DIR}"
PRESERVED_COUNT="${S6C_PRESERVED_COUNT:-0}"
DMS_PRESERVED="${S6C_DMS_PRESERVED:-}"
TS="${S6C_TS:-$TS}"
LIVE_DMS="$DOTFILES_DIR/$DMS_REL"
CHANGED=no
HEAD_BEFORE="$(git -C "$DOTFILES_DIR" rev-parse HEAD 2>/dev/null || echo none)"

require_not_root
require_cmds git stow

# The stamp is the primary signal, but it only started existing on 19 Sep 2026 --
# so every machine already in the fleet lacks one. Treating those as fresh would
# re-run the whole installer on a working desktop, including the sections that are
# not safe to repeat. Fall back to asking whether this machine is already stowed
# from THIS checkout, and backfill the stamp if so.
if [ -f "$STAMP" ]; then
    MODE=update
elif [ -L "$HOME/.config/niri" ] \
        && [ "$(readlink -f "$HOME/.config/niri")" = "$DOTFILES_DIR/.config/niri" ] \
        && have_cmd niri; then
    MODE=update
    log "no build stamp, but this machine is already stowed from $DOTFILES_DIR - treating as an update"
else
    MODE=install
fi

if [ "$MODE" = install ]; then
    section "Full install"
    log "no build stamp at $STAMP - running the installer end to end"
    INSTALLER="$HERE/ubuntu_26.04_niri_install.sh"
    [ -f "$INSTALLER" ] || die "$INSTALLER not found."
    chmod +x "$INSTALLER" 2>/dev/null || true
    "$INSTALLER" || die "the installer did not finish - fix the errors above and re-run."
    CHANGED=yes
else
    # The update-safe sections: packages, drivers, repos, services. Section 10 is
    # deliberately not among them -- the dotfiles path below owns that on an update,
    # because it carries the settings.json preserve/restore and the migrations that
    # section 10 does not. `--list` marks what --update leaves out, and why.
    section "Build sections"
    INSTALLER="$HERE/ubuntu_26.04_niri_install.sh"
    if [ ! -f "$INSTALLER" ]; then
        warn "$INSTALLER not found - skipping the build sections."
    elif sudo -n true 2>/dev/null || [ -t 0 ]; then
        chmod +x "$INSTALLER" 2>/dev/null || true
        if "$INSTALLER" --update; then
            CHANGED=yes
        else
            warn "some build sections failed - see above. The dotfiles steps below still run."
        fi
    else
        warn "no cached sudo and no terminal to ask at - skipping the build sections."
        warn "Packages, drivers and services are unchanged. Re-run from a desktop terminal for those."
    fi
fi

section "Removing links the old layout created"
removed=0
for link in "$HOME/install_programs" "$HOME/README.md" "$HOME/_archive"; do
    if [ -L "$link" ]; then rm -v "$link"; removed=$((removed + 1)); fi
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
# Phase A preserved the live file before converging, because the 8 Sep commit
# removes it from the tree and it holds the whole desktop configuration.
if [ -n "$DMS_PRESERVED" ] && [ -f "$DMS_PRESERVED" ]; then
    mkdir -p "$(dirname "$LIVE_DMS")"
    cp "$DMS_PRESERVED" "$LIVE_DMS"
    log "restored your live settings (now untracked, as DMS owns the file)"
    CHANGED=yes
elif [ ! -f "$LIVE_DMS" ]; then
    bak="$HOME/.config/DankMaterialShell.pre-stow.bak/settings.json"
    if [ -f "$bak" ]; then
        mkdir -p "$(dirname "$LIVE_DMS")"
        cp "$bak" "$LIVE_DMS"
        log "recovered settings from $bak"
    fi
fi
seed_out="$(seed_dms_settings "$HERE/dms-settings.s6c.json" "$LIVE_DMS" 2>&1)" \
    || warn "could not seed all the S6C DMS settings - see above."
printf '%s\n' "$seed_out"
case "$seed_out" in
    *"set "*"key"*|*"seeded "*"key"*) CHANGED=yes ;;
esac

section "Greeter"
# Needs sudo, rewrites the greetd config twice and leaves two backups in /etc on
# every run, so it fires only when the run actually changed something. It also
# needs a session: over SSH there is no tty for the sudo prompt.
[ "$(git -C "$DOTFILES_DIR" rev-parse HEAD 2>/dev/null || echo none)" = "$HEAD_BEFORE" ] || CHANGED=yes
if [ "$CHANGED" = no ] && [ "$FORCE_GREETER" = no ]; then
    log "nothing changed - skipping the greeter sync (force it with --greeter)"
elif [ -z "${WAYLAND_DISPLAY:-}" ] && [ ! -t 0 ] && [ "$FORCE_GREETER" = no ]; then
    warn "no graphical session and no tty - skipping the greeter sync. Run 'dms-greeter sync' when next at the desktop."
elif have_cmd dms-greeter || have_cmd dms; then
    sync=(dms greeter sync)
    have_cmd dms-greeter && sync=(dms-greeter sync)
    if DMS_PRIVESC=sudo "${sync[@]}"; then
        log "greeter synced"
    else
        warn "greeter sync failed - re-run '${sync[*]}' by hand."
    fi
else
    log "no dms/dms-greeter on PATH - skipping greeter sync"
fi

section "Git remote"
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
[ -x "$HOME/.local/bin/dank-lock.sh" ] && log "dank-lock.sh is executable" || warn "dank-lock.sh is not executable"
[ -e "$HOME/install_programs" ] && warn "$HOME/install_programs still exists" || log "$HOME/install_programs gone"
ls -d "$HOME"/.config/*.pre-stow.bak "$HOME"/.*.pre-stow.bak 2>/dev/null | sed 's/^/moved aside: /' || true

# The stamp is what makes "is this machine on the latest build?" answerable. Its
# absence is why 18WessexUbuntu sat 7 commits behind unnoticed until 19 Sep 2026.
mkdir -p "$STATE_DIR"
{
    echo "commit=$(git -C "$DOTFILES_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "mode=$MODE"
    echo "script=install.sh"
    if [ "$PRESERVED_COUNT" -gt 0 ] || [ -n "$DMS_PRESERVED" ]; then
        echo "preserved=$PRESERVE_DIR"
    else
        echo "preserved=-"
    fi
} > "$STAMP"
log "build stamp written to $STAMP"

if [ "$PRESERVED_COUNT" -gt 0 ]; then
    warn "$PRESERVED_COUNT of your changed file(s) were replaced by the repo version."
    warn "Your copies are safe in $PRESERVE_DIR"
fi
log "done. Open a new terminal to pick up the shell changes."
