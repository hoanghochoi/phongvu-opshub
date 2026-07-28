# Execution Plan: OPS-26 Transactional Production Release

Date: 2026-07-29

## Status

Active

## Outcome

Production and static-only release publication stage all runtime, env,
web/help/download and client inputs before promotion, retain a run-scoped
checkpoint through public verification, and restore the exact previous
runtime/env/shared publication on any guarded failure. Success removes
temporary rollback metadata only after every public gate passes.

## Context

- Linear OPS-26 acceptance criteria and failed production run 30152246314.
- `docs/runbooks/git-release-playbook.md`, `docs/ARCHITECTURE.md`,
  `deploy/home-server/SECURITY_HARDENING_RUNBOOK.md`.
- Existing staging transaction implementation in
  `.github/workflows/deploy-opshub-staging.yml`.
- Production workflow `.github/workflows/deploy-opshub.yml`, including the
  full deploy and `deploy_download_static` jobs.
- User decisions on 2026-07-29: migrations must use expand/contract so the
  previous runtime remains compatible; `deploy_download_static` is in scope.

## Scope

In scope:

- Full production deploy and static-only publication.
- Run/attempt-scoped staging paths, env/shared snapshots, promotion markers,
  exact previous-release rollback, public verification rollback, and
  success-only cleanup.
- Bash fixture/contract tests for failpoints and retained evidence.
- Runbook and validation-matrix updates for migration compatibility and
  recovery evidence.

Out of scope:

- Database snapshot/restore; destructive schema rollback.
- Promotion authorization, release locks, reviewer gates, or unrelated app
  behavior.
- Staging workflow redesign beyond proof needed to exercise the same
  transaction contract.

## Approach

1. Capture current production/static workflow and staging transaction seams.
2. Extract a reusable, allowlisted transaction helper where practical, with a
   temporary-directory fixture covering snapshot, promote, restore, finalize,
   and restore-failure retention.
3. Wire full production deploy to stage all inputs and snapshot before env or
   shared mutation; keep exact previous runtime and env together.
4. Wire static-only deploy to the same transaction without changing app-version
   metadata; rollback Help/download/static paths on verification failure.
5. Keep migration/backend operations behind the rollback trap and document the
   expand/contract requirement for every release migration.
6. Run focused shell/workflow tests, YAML/Node checks, and affected release
   workflow proof before PR and staging deploy.

## Risks And Recovery

- A forward migration that is not expand/contract can strand the old runtime;
  fail closed and retain checkpoints if compatibility proof is absent.
- Filesystem publication is not globally atomic; markers and exact snapshots
  make recovery resumable and prevent cleanup after partial restore.
- Runner cancellation can strand snapshots; the runbook recovery command must
  identify the exact run/attempt and preserve evidence.
- If any local proof changes the fingerprint, recompute and rerun all gates.

## Progress

- [x] Record intake/checkpoint and user policy decisions.
- [x] Add transaction fixture and failure-injection tests.
- [x] Integrate full production deploy transaction.
- [x] Integrate static-only deploy transaction.
- [x] Update runbook/test matrix.
- [x] Run focused proof, merge PR #46 to staging, and verify the exact merged
  SHA with a normal staging deployment.
- [ ] Merge staging-only controlled failpoints and prove rollback after shared
  promotion, from the migration/backend-build gate, during public verification,
  and through the shared static-only transaction rehearsal.

## Decisions

- 2026-07-29: Use expand/contract migrations so the previous runtime remains
  runnable during rollback; do not snapshot/restore the production database.
- 2026-07-29: Include `deploy_download_static` in the same transactional
  publication contract.
- 2026-07-29: Restore the exact previous release recorded in the checkpoint;
  do not select an arbitrary older release when the exact candidate is known.

## Validation

- Focused proof: `tests/release/test-release-transaction.sh` PASS, including
  snapshot/promote/restore, injected env/shared restore failures, static-only
  Caddy/Help/download rollback, exact previous-release state and ordering.
  Embedded deploy Bash syntax PASS, all workflow YAML parse PASS, platform
  security PASS, release workflow fixtures `9/9` PASS, lifecycle fixtures
  `11/11` PASS, runtime-release preview packaging PASS, Node syntax PASS and
  `git diff --check` PASS.
- PR #46 squash-merged as `5c6563cc57a7dd132fedb6fcd8c49bb29741ece9`;
  exact-SHA staging run `30402514299` passed Android/Windows builds, signing,
  Defender, web/backend deploy, direct-origin checks and public health/version/
  manifest/help/download verification.
- Staging failpoint fingerprint contract, shared static transaction rehearsal,
  workflow YAML parsing and all embedded Bash blocks pass locally. The
  failpoint workflow now keeps its input in the deploy step, fingerprints
  staging-named client artifacts with path/type/mode/owner/content metadata,
  and routes the runtime failpoint through the migration/backend-build command.
  Live controlled rollback runs remain.
- The repository's existing `tests/release/test-release-workflow-contract.sh`
  and `test-post-merge-release-recovery.sh` remain blocked by pre-existing
  references to absent `.github/workflows/post-merge-maintenance.yml` and
  `premerge.yml`; no files in that Harness-only surface were changed here.
- Integration/end-to-end: exact-SHA staging deploy, public health/version/
  manifest/help/download checks, and failed-verification rollback evidence.
- Repository-required checks: affected release consumers and any required
  Nest/Flutter/Go checks when workflow or runtime paths are touched.

## Result

Production transaction implementation is merged to staging and its normal
exact-SHA deploy/public verification passed. The staging-only failpoint follow-up
and four live controlled rollback runs remain before OPS-26 can move to Ready
for Release. The fourth run is an isolated rehearsal on the staging host using
the same `release-transaction.sh` helper as production static-only publication.
