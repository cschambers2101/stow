# Tech debt log

Problems found outside the scope of a task. Logged, not fixed, unless the user agrees. Security problems are reported to the user immediately as well as logged here.

| Date | Location | What is wrong | Severity (High / Medium / Low) | Suggested fix | Status |
|------|----------|---------------|--------------------------------|---------------|--------|
| 2026-11-13 | Every shell file except `deploy/dev-deploy.sh` | The installer predates the Bash pack: about 800 ShellCheck findings at style severity (mostly SC2292 `[[ ]]`, SC2312, SC2310), 34 files shfmt would reformat, 30 review-rule findings, and no tests for most of `install_programs/lib/` | Medium | Bring one file at a time up to the standard, with bats tests for its functions, then lift `PACKS_DEFERRED`. Re-run a VM build after any large reformat | Open |
| 2026-11-13 | `install_programs/bootstrap.sh`, `update.sh`, `tidy-old.sh`, `lib/devtools.sh` | Review rule `curl-pipe-sh`: a download run straight into a shell. The one-liner and its shims do this by design, because students run them before the repository exists | Low | Leave the shims, mark them `# verify: allow` with the reason when the pack is turned on; download-then-check in `devtools.sh` | Open |
| 2026-11-13 | `VERSION` | `release.sh` reads a semantic version from `VERSION` (0.1.0); this repository's releases are dated tags | Low | Agree with Craig at the next release: switch to semantic versions, or keep dated tags and tag by hand | Open |
