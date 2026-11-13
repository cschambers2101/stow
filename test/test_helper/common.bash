# shellcheck shell=bash
# Shared set-up for a repository's bats tests (the cc-local-development Bash pack). Copy to
# test/test_helper/common.bash and load it first in each test file:
#
#   setup() {
#     load test_helper/common
#     source "$ROOT/lib/<library>.sh"
#   }
#
# It loads bats-support, bats-assert and bats-file from the submodules beside it (add-bats.sh vendors them), sets
# ROOT to the repository root as a path without "..", which the coverage step needs, and gives stub.

BATS_LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)${BATS_LIB_PATH:+:$BATS_LIB_PATH}"
bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
export ROOT

# stub <command> [exit code] [output]: put a fake <command> first on PATH for this test. It prints [output], exits
# with [exit code] (0) and appends its arguments, one call per line, to "$BATS_TEST_TMPDIR/<command>.calls".
stub() {
  local name="$1" rc="${2:-0}" out="${3:-}" dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$dir"
  {
    echo '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" "$*" >>%q\n' "$BATS_TEST_TMPDIR/$name.calls"
    [[ -z "$out" ]] || printf 'printf "%%s\\n" %q\n' "$out"
    printf 'exit %d\n' "$rc"
  } >"$dir/$name"
  chmod +x "$dir/$name"
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) PATH="$dir:$PATH" ;;
  esac
}
