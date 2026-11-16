#!/usr/bin/env bats
# deploy/dev-deploy.sh copies a ref of the repository into the dev container,
# where installer sections are then run by hand.

setup() {
  load ../test_helper/common
  SCRIPT="$ROOT/deploy/dev-deploy.sh"

  # A throwaway repository with a local "origin", so fetch works offline.
  git init -q --bare "$BATS_TEST_TMPDIR/origin.git"
  git clone -q "$BATS_TEST_TMPDIR/origin.git" "$BATS_TEST_TMPDIR/work" 2>/dev/null
  cd "$BATS_TEST_TMPDIR/work"
  git -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
  echo one >on-beta.txt
  git add on-beta.txt
  git -c user.name=t -c user.email=t@example.invalid commit -q -m beta
  git push -q origin HEAD:beta
  echo two >on-other.txt
  git add on-other.txt
  git -c user.name=t -c user.email=t@example.invalid commit -q -m other
  git push -q origin HEAD:other

  fakes="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$fakes"
  PATH="$fakes:$PATH"
  fake_lxc 0
}

# fake_lxc <exit code>: records each call, and lists the files of any archive piped to tar -x.
fake_lxc() {
  cat >"$fakes/lxc" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$BATS_TEST_TMPDIR/lxc.calls"
case "\$*" in *"tar -x"*) tar -t >>"$BATS_TEST_TMPDIR/archived" ;; esac
exit $1
EOF
  chmod +x "$fakes/lxc"
}

@test "copies origin/beta into stow-dev by default, replacing the old copy" {
  run bash "$SCRIPT"
  assert_success
  assert_file_contains "$BATS_TEST_TMPDIR/lxc.calls" "^exec stow-dev -- rm -rf /home/ubuntu/stow-beta$"
  assert_file_contains "$BATS_TEST_TMPDIR/lxc.calls" "^exec stow-dev -- tar -x -C /home/ubuntu/stow-beta$"
  assert_file_contains "$BATS_TEST_TMPDIR/lxc.calls" "^exec stow-dev -- chown -R ubuntu:ubuntu /home/ubuntu/stow-beta$"
  assert_file_contains "$BATS_TEST_TMPDIR/archived" "^on-beta.txt$"
  run grep -c "on-other.txt" "$BATS_TEST_TMPDIR/archived"
  assert_output 0
}

@test "takes a ref and a container name" {
  run bash "$SCRIPT" origin/other test-box
  assert_success
  assert_file_contains "$BATS_TEST_TMPDIR/lxc.calls" "^exec test-box -- tar -x -C /home/ubuntu/stow-beta$"
  assert_file_contains "$BATS_TEST_TMPDIR/archived" "^on-other.txt$"
}

@test "says which commit it deployed" {
  run bash "$SCRIPT"
  assert_success
  assert_output --partial "deployed $(git rev-parse --short origin/beta) to stow-dev"
}

@test "fails when the container cannot be reached" {
  fake_lxc 1
  run bash "$SCRIPT"
  assert_failure
}
