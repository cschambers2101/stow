# Project profile

Set with Craig on 13 November 2026, when its working process was agreed. Update it
whenever any of this changes. Never fill it in by guessing.

| Item | Value |
|------|-------|
| Project name | stow: Craig's dotfiles and the Ubuntu 26.04 niri build for staff and student machines |
| App type | Shell installer and dotfiles, deployed with GNU Stow from `~/.dotfiles` |
| Repository | `cschambers2101/stow` on GitHub, **public**: students fetch the installer anonymously over HTTPS |
| CI mode | `local`. `lint.yml` stays on GitHub as well (free, because the repository is public) |
| Languages | Bash. `.local/bin/ytmusic-tag` (Python) and `_archive/` are exempt |
| Database | none |
| Other services | GitHub (raw.githubusercontent.com for the one-liner), Launchpad PPAs, cli.github.com, Oakford CA |

## Dev environment

| Item | Value |
|------|-------|
| Type | LXD |
| Host and how to reach it | ubuntu-craig-office, local `lxc` |
| App container | `stow-dev`: Ubuntu 26.04, profiles `default` and `lan` (bridged onto the school LAN) |
| Deploy | `deploy/dev-deploy.sh` copies `origin/beta` to `/home/ubuntu/stow-beta` in the container (the command is in `AGENTS.md`) |
| Testing there | Run the installer sections a change touches, as `ubuntu` (passwordless sudo): `lxc exec stow-dev -- sudo -iu ubuntu bash ~/stow-beta/install_programs/ubuntu_26.04_niri_install.sh --only <ids>`, then `verify-install.sh` |
| What a container cannot test | Section 0's clock (chrony.service is skipped in containers; run `chronyd -x` by hand), the kernel, graphics, the greeter and suspend. Those are tested on a real machine, with Craig running sudo |

## Production environment

| Item | Value |
|------|-------|
| Exists yet? | Yes: every machine built from this repository |
| How it is deployed | `install.sh` on each machine converges on `origin/main`. Nothing reaches a machine until a release merges `beta` into `main` |
| Release | A `beta` to `main` pull request, then an annotated tag and a GitHub release |
| Runbook | `docs/runbook.md` |

## Testing the running app

| Item | Value |
|------|-------|
| End-to-end tool | `install_programs/verify-install.sh` on the built machine |
| Unit tests | bats under `test/unit`, vendored bats in `test/bats` |

## Overrides of skill defaults

| Skill default | This project instead | Reason | Agreed on |
|---------------|----------------------|--------|-----------|
| Full Bash style checks (ShellCheck style findings, shfmt) on every file | Deferred; `lint.sh` and the bats tests are the checks | The installer predates the standard (about 800 ShellCheck style findings, no tests for most of `lib/`). New code meets it; old files are brought up to it one at a time | 13 Nov 2026 |
| No GitHub Actions | `lint.yml` kept | Public repository, so Actions cost nothing | 13 Nov 2026 |
| Semantic version in `VERSION` | Releases are dated tags (`v2026.11.16`); `VERSION` holds the date as `YYYY.MM.DD` | Craig chose dated versions | 16 Nov 2026 |

## Decisions and history

- 2026-11-13: local mode: added `AGENTS.md` with the process.

- 2026-11-13: local mode: kept `.github/workflows/lint.yml` on GitHub on the user's answer (it uses Actions minutes).

- 2026-11-13: profile written with Craig: Bash only, the Bash pack deferred for existing code, dev is `stow-dev`.

- 2026-11-16: moved to launcher hooks in `.githooks/`.
- 2026-11-18: dropped the external process scripts and the git hooks. `AGENTS.md` now carries the commands, merge,
  dev deploy and release steps.
