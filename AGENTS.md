# AGENTS.md

<!-- cc-local-development: start (written and refreshed by the skill; put your own notes outside these markers) -->
## How we work in this repository

This repository follows the cc-local-development process. The scripts it runs are in `~/.local/share/cc-local-development/scripts/`. Agents that
have the `cc-local-development` skill get the full process from it; this is the short form, for every agent and
every person.

### Before writing code

- **Search first.** Look for code here that already does the job, then the shared libraries, the packages already
  referenced, the language's standard library, and only then a new package. Use what exists. Extend what is close.
  When the same rule turns up in more than one place, move it into one shared place first, then use it.
- **A failing test first,** then the code that makes it pass.
- **Stay inside the task.** Note anything else in `docs/tech-debt.md`. Report a security problem straight away.

### The ten principles, in priority order

1. **SOLID.** Each class or module has one reason to change and depends on abstractions, not on details.
2. **Separation of concerns.** Interface, business rules and data access are kept apart. Business logic lives in a
   service, never in a page, a component or a controller.
3. **KISS.** The simplest code that solves the problem.
4. **DRY.** One definition of each rule or decision. Two or three similar lines are not a breach; a rule stated
   twice is.
5. **YAGNI.** No abstraction, option or extension point without a need that exists today.
6. **Composition over inheritance.** Build from small parts before reaching for a base class.
7. **Fail fast.** Check inputs at the boundary and stop there.
8. **Immutability by default.** Make data unchangeable unless it has to change.
9. **Design for testability.** Everything public can be tested without tricks or hidden global state.
10. **Law of Demeter.** Talk to what you were given, not through it to its neighbours.

Scale each to the code in front of you: a short script is not held to SOLID, and tests may repeat themselves. When
two clash, the higher one wins, unless that would create an abstraction with a single use: then KISS and YAGNI win.

### Branches and commits

- Never commit or push to `main` or `beta`. Work on a `feature/` or `bugfix/` branch cut from `beta`.
- Commit messages are Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`; a `!` marks a
  breaking change). The next version number is worked out from them, so type them truthfully.
- Never skip the git hooks (`--no-verify`). Never force-push.

### The three commands

- `bash ~/.local/share/cc-local-development/scripts/verify.sh` runs every check (`--quick` while working). A change is not done until it passes.
- `bash ~/.local/share/cc-local-development/scripts/merge.sh <pull request>` merges a pull request into `beta`: it verifies, merges, tidies up
  and deploys to dev. Nothing is merged any other way.
- `bash ~/.local/share/cc-local-development/scripts/release.sh` cuts a release, and only when the owner has said "cut a release".

### Ask the owner first

Anything that touches production, drops or restores data, adds a paid or closed-source dependency, or changes the
checks themselves.
<!-- cc-local-development: end -->
