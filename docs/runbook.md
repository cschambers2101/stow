# Runbook

## Environments

| Environment | Where | URL | Health check |
|-------------|-------|-----|--------------|
| Dev | | | |
| Production | none yet | | |

## Deploying to dev

`bash <(git show origin/beta:deploy/dev-deploy.sh) origin/beta stow-dev`

See `AGENTS.md` for what it does.

## Rolling back dev

Deploy the earlier ref the same way, for example `bash <(git show origin/beta:deploy/dev-deploy.sh) <ref> stow-dev`.

## Deploying to production

Only with the user's go-ahead. Steps:

1. Back up the database with `pg_dump`.
2. Apply migrations with the migration bundle.
3. Deploy the build from the release tag.
4. Smoke test (read-only).
5. Watch the logs.

## Rolling back production

1. Redeploy the previous release tag. The database stays (expand-then-contract makes this safe).
2. Restoring a backup loses data written since. The user decides.

## Restoring a backup

`pg_restore` steps:

## Logs

Where they are and how to read them.

## Secrets

Where each secret is stored, and who can rotate it. Never the values.

## Who to tell

