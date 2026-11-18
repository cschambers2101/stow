# AGENTS.md

## How we work in this repository

This file holds everything an agent or a person needs to change this repository: the base branch, the commands to run,
how to deploy to dev and how to release.

### Before writing code

- Search first. Look for code here that already does the job, then the shared libraries, the packages already
  referenced, the language's standard library, and only then a new package. Use what exists. Extend what is close.
  When the same rule turns up in more than one place, move it into one shared place first, then use it.
- Write a failing test first, then the code that makes it pass.
- Stay inside the task. Note anything else in `docs/tech-debt.md`. Report a security problem straight away.

### The ten principles, in priority order

1. SOLID. Each class or module has one reason to change and depends on abstractions, not on details.
2. Separation of concerns. Interface, business rules and data access are kept apart. Business logic lives in a
   service, never in a page, a component or a controller.
3. KISS. The simplest code that solves the problem.
4. DRY. One definition of each rule or decision. Two or three similar lines are not a breach; a rule stated
   twice is.
5. YAGNI. No abstraction, option or extension point without a need that exists today.
6. Composition over inheritance. Build from small parts before reaching for a base class.
7. Fail fast. Check inputs at the boundary and stop there.
8. Immutability by default. Make data unchangeable unless it has to change.
9. Design for testability. Everything public can be tested without tricks or hidden global state.
10. Law of Demeter. Talk to what you were given, not through it to its neighbours.

Scale each to the code in front of you: a short script is not held to SOLID, and tests may repeat themselves. When
two clash, the higher one wins, unless that would create an abstraction with a single use: then KISS and YAGNI win.

### Branches and commits

- Never commit or push to `main` or `beta`. Work on a `feature/` or `bugfix/` branch cut from `beta`.
- Commit messages are Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`; a `!` marks a
  breaking change). Type them truthfully.
- Never force-push.

### Commands

Run these in your worktree before you say a change is done. All must pass.

- `bash install_programs/lint.sh` runs `bash -n` and ShellCheck over the installer, the libraries and the dotfiles.
- `test/bats/bin/bats -r test/unit` runs the unit tests. The bats files are a submodule, so run
  `git submodule update --init` once in a new worktree.
- `bash -n <script>` on every script you changed, if `lint.sh` does not already cover it.

Write the tests for new and changed code first. The installer predates the tests, so most of `install_programs/lib/`
has none yet. Bring files up to the standard one at a time (`docs/tech-debt.md`).

Two things are exempt from the language rule (code goes in Bash only): `.local/bin/ytmusic-tag`, a personal
tagging helper kept as it is, and `_archive/`, which holds retired material that is neither stowed nor linted.

### Merging

1. Open a pull request into `beta`.
2. When the commands above pass, merge it with `gh pr merge <number> --squash --delete-branch`.
3. Remove your worktree and local branch.

### Deploying to dev

Dev is the `stow-dev` LXD container on ubuntu-craig-office. Run this from a checkout of the repository:

`bash <(git show origin/beta:deploy/dev-deploy.sh) origin/beta stow-dev`

It reads `deploy/dev-deploy.sh` from `origin/beta`, then copies that commit into `/home/ubuntu/stow-beta` in the
container, replacing the last copy. Pass another ref or container as the two arguments to deploy something else.

### Releases

Cut a release only after the owner says "cut a release".

1. On a `chore/release-<version>` branch from `beta`, set `VERSION` to the release date as `YYYY.MM.DD` and add a
   section for it to `CHANGELOG.md`. Merge that into `beta` as usual.
2. Open a pull request from `beta` to `main`. Merge it with a merge commit. Never use `--delete-branch`.
3. Tag `v` plus the version on `main`, then publish a GitHub release for the tag.

### Ask the owner first

Anything that touches production, drops or restores data, adds a paid or closed-source dependency, or changes the
checks themselves.
