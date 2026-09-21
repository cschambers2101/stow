#!/usr/bin/env bash
# Run installer section 5b (DMS package currency) on each named machine over ssh.
#
#   fleet-dms-currency.sh [--dry-run] HOST [HOST...]
#
# One `ssh -t` per host, so each prompts once for its own sudo password. The host
# pulls its own ~/.dotfiles first so the section exists there.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

DRYRUN=no
HOSTS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRYRUN=yes ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        -*) die "unknown option: $arg" ;;
        *) HOSTS+=("$arg") ;;
    esac
done
[ "${#HOSTS[@]}" -gt 0 ] || die "name at least one host. Usage: $0 [--dry-run] HOST [HOST...]"

REMOTE='git -C ~/.dotfiles pull --ff-only --quiet || echo "WARN: could not fast-forward ~/.dotfiles - running whatever is checked out"; grep -q "\"5b:s05b_dms_currency:" ~/.dotfiles/install_programs/ubuntu_26.04_niri_install.sh || { echo "ERROR: this checkout has no section 5b - fix the pull first"; exit 3; }; ~/.dotfiles/install_programs/ubuntu_26.04_niri_install.sh --only 5b'

declare -A RESULT=()
for host in "${HOSTS[@]}"; do
    section "$host"
    if [ "$DRYRUN" = yes ]; then
        log "would run: ssh -t $host '$REMOTE'"
        RESULT[$host]="dry-run"
        continue
    fi
    if ssh -t -o ConnectTimeout=10 "$host" "$REMOTE"; then
        RESULT[$host]="ok"
    else
        RESULT[$host]="FAILED ($?)"
        warn "$host: section 5b did not complete - see above."
    fi
done

section "Summary"
for host in "${HOSTS[@]}"; do
    printf '  %-40s %s\n' "$host" "${RESULT[$host]}"
done
