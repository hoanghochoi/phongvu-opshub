# OPS-210 Production deploy reliability and OPS-39 integration

Date: 2026-08-21

## Outcome

Repair the production deployment handoff for the `phongvu.work` migration and
integrate the approved, still-uncommitted OPS-39 bank-operation changes without
altering the original OPS-39 worktree.

## Checkpoint

- Base: `origin/staging` `f9ff9141a0240bb78501b1c697c3da4ad2d06c74`.
- Production promotion reached the same SHA, but Deploy OpsHub run
  `32479258037` failed before runtime health verification.
- The original `codex/ops-39-ui-only-bank-operations` worktree remains intact;
  its tracked and untracked changes were copied into this task worktree.

## Root cause and repair

Production passed `OPSHUB_PUBLIC_BASE_URL` to local build and smoke steps but
omitted it from the environment assignment sent to its remote SSH shell. That
shell uses `set -u` and later expands the variable to publish `PUBLIC_BASE_URL`,
`IMAGE_BASE_URL`, and `ALLOWED_ORIGINS`, so it terminated with an unbound-variable
error. Staging already passes the value.

The repair explicitly passes the public URL in the production SSH environment
block and adds a release-workflow regression assertion. No production runtime
is patched directly; a new SHA must complete staging deploy and QA before a new
explicit production promotion.

## Validation and recovery

- Validate workflow YAML, release workflow regression tests, platform security,
  OPS-39 local-only/backup/Caddy boundaries, Nest, Flutter, Go, and affected
  consumers from this exact worktree.
- Commits `e7b76b8685504943ef985a33bce9b2fda8ec2b6b` (implementation) and
  `88e8cb6a` (evidence refresh) are the local release candidate. The retained
  owner manifest now binds to the implementation commit and records normalized
  SHA/byte metadata for the changed release workflows.
- `node scripts/verify-retained-owner-review.mjs --input
  docs/migrations/ops-73-retained-owner-review.json` passed with 4 candidates
  and 19 retained paths.
- `node scripts/verify-task.mjs --full` passed every selected repository
  profile, including Nest/Flutter/Go, deployment/Caddy, OPS-39 affected
  consumers, platform security, and lifecycle verification. The worktree is
  clean and `git diff --check` passes.
- Confirm the production deploy passes its remote runtime step before changing
  the production Tunnel from fail-closed routing.
- If staging deploy fails, keep production on the prior healthy release and
  investigate the staging log; do not retry production.

## Staging follow-up

The first exact-SHA staging deploy after PR #354 (`32486763960`) built and
published the runtime, then failed the direct-origin gate because canonical
`/help` returned `404`; the workflow completed its controlled rollback. The
failure is reproducible at the release boundary, while the public rollback
state remains healthy. This follow-up makes the `/help` SPA entrypoint explicit
in Caddy and adds a static contract assertion before the next staging attempt.
