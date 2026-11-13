#!/usr/bin/env bats
# gh_apt_source adds GitHub's own apt repository for gh, so a build gets a
# current gh rather than the 2.46.0 in Ubuntu's archive.

setup() {
  load ../test_helper/common
  export S6C_NO_STRICT=1
  LIB="$ROOT/install_programs/lib/common.sh"
  GH_KEY_FPR="$(bash -c '. "$1"; echo "$GH_KEY_FPR"' _ "$LIB")"
  GH_KEYRING="$BATS_TEST_TMPDIR/etc/apt/keyrings/githubcli-archive-keyring.gpg"
  GH_SOURCE="$BATS_TEST_TMPDIR/etc/apt/sources.list.d/github-cli.list"

  fakes="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$fakes"
  PATH="$fakes:$PATH"
  # sudo runs the command as the test user, inside the temporary tree.
  printf '#!/usr/bin/env bash\nexec "$@"\n' >"$fakes/sudo"
  printf '#!/usr/bin/env bash\necho amd64\n' >"$fakes/dpkg"
  chmod +x "$fakes/sudo" "$fakes/dpkg"
  fake_curl 0
  fake_gpg "$GH_KEY_FPR"
}

# gh_apt_source runs in its own shell: the library sets an EXIT trap, which would
# replace the one bats reports results from. The paths point into the test's tree.
gh_apt_source() {
  bash -c '. "$1"; GH_KEYRING="$2"; GH_SOURCE="$3"; gh_apt_source' _ "$LIB" "$GH_KEYRING" "$GH_SOURCE"
}

# fake_curl <exit code>: writes a stand-in key to the -o path, then exits with the code.
fake_curl() {
  cat >"$fakes/curl" <<EOF
#!/usr/bin/env bash
out=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = -o ]; then out="\$2"; shift; fi
  shift
done
[ -z "\$out" ] || echo "key bytes" >"\$out"
exit $1
EOF
  chmod +x "$fakes/curl"
}

# fake_gpg <fingerprint>: reports one key with that fingerprint, as gpg --with-colons does.
fake_gpg() {
  printf '#!/usr/bin/env bash\necho "pub:-:4096:1:ABCDEF:1:::-:::scESC::::::23::0:"\necho "fpr:::::::::%s:"\n' "$1" >"$fakes/gpg"
  chmod +x "$fakes/gpg"
}

@test "adds the key and a source pointing at cli.github.com" {
  run gh_apt_source
  assert_success
  assert_file_exists "$GH_KEYRING"
  assert_file_contains "$GH_SOURCE" "^deb \[arch=amd64 signed-by=$GH_KEYRING\] https://cli.github.com/packages stable main$"
}

@test "the key and the source are world-readable, so apt can read them" {
  run gh_apt_source
  assert_success
  assert_equal "$(stat -c %a "$GH_KEYRING")" 644
  assert_equal "$(stat -c %a "$GH_SOURCE")" 644
}

@test "a failed download leaves no source, so gh comes from Ubuntu's archive" {
  fake_curl 22
  run gh_apt_source
  assert_failure
  assert_output --partial "could not fetch"
  assert_file_not_exists "$GH_SOURCE"
}

@test "a key with another fingerprint is refused and no source is written" {
  fake_gpg 0000000000000000000000000000000000000000
  run gh_apt_source
  assert_failure
  assert_output --partial "fingerprint"
  assert_file_not_exists "$GH_KEYRING"
  assert_file_not_exists "$GH_SOURCE"
}

@test "a key that cannot be installed leaves no source pointing at it" {
  mkdir -p "$(dirname "$GH_KEYRING")"
  chmod a-w "$(dirname "$GH_KEYRING")"
  run gh_apt_source
  chmod u+w "$(dirname "$GH_KEYRING")"
  assert_failure
  assert_output --partial "could not install"
  assert_file_not_exists "$GH_SOURCE"
}

@test "a second run rewrites the same source, so an update is safe to repeat" {
  gh_apt_source
  run gh_apt_source
  assert_success
  assert_equal "$(grep -c . "$GH_SOURCE")" 1
}
