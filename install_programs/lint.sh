#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mapfile -t FILES < <(
    {
        find install_programs -path install_programs/archived -prune -o -type f -name '*.sh' -print
        find install_programs/lib install_programs/suspend -type f
        find .local/bin -maxdepth 1 -type f ! -name '*.py' ! -name '*.pyc'
        find .config -type f -name '*.sh'
        printf '%s\n' .bashrc .bash_aliases .bash_functions .bash_profile .bash_x11
    } | sort -u
)

SH=()
for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    if head -1 "$f" | grep -qE '^#!.*(ba)?sh' || [[ "$f" == .bash* ]] || [[ "$f" == */lib/* ]]; then
        SH+=("$f")
    fi
done

rc=0
for f in "${SH[@]}"; do
    bash -n "$f" || rc=1
done

while IFS= read -r f; do
    case "$(git ls-files -s -- "$f" | awk '{print $1}')" in
        100755|"") ;;
        *) echo "not executable in git: $f (git update-index --chmod=+x)"; rc=1 ;;
    esac
done < <(find .local/bin -maxdepth 1 -type f ! -name '*.pyc'; find .config -type f -name '*.sh'; find install_programs -maxdepth 2 -type f -name '*.sh' ! -path '*/lib/*'; printf '%s\n' install_programs/suspend/rtw89-reload)
if ! command -v shellcheck >/dev/null 2>&1; then
    echo "lint: shellcheck is NOT installed - only the bash -n and mode passes ran." >&2
    echo "lint: install it (sudo apt install shellcheck) for the real lint." >&2
    exit 1
fi
shellcheck -S warning "${SH[@]}" || rc=1

if [ "$rc" -eq 0 ]; then
    echo "lint: ${#SH[@]} shell files OK"
fi
exit "$rc"
