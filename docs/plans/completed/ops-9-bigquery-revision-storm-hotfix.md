# Execution Plan: OPS-9 BigQuery revision storm hotfix

Date: 2026-07-24

## Status

Completed

## Outcome

Mỗi giao dịch MAP/eFAST canonical tạo đúng một BigQuery outbox event sau khi
PostgreSQL ghi thành công. Replay cùng giao dịch với hai cách biểu diễn
`Thành công`/`SUCCESS` hoặc nguồn MAP/eFAST không tiếp tục tăng revision. Mã
đơn, statement identifier và các trường báo cáo thực sự thay đổi vẫn tạo event
mới.

## Context

- Product contract: `docs/product/map-vietin-bigquery.md`.
- Story: `docs/stories/OPS-9-map-vietin-bigquery-sync/`.
- Existing migration:
  `backend-nest/prisma/migrations/20260723100000_map_vietin_bigquery_outbox/`.
- Production inspection on 2026-07-24 found the worker disabled but more than
  9,000 pending events for about 139 transactions. Nearly every repeated event
  alternated only `status` and `provider_source` between MAP and eFAST forms.
- Checkpoint: branch `codex/ops-9-hotfix-bigquery-revision-storm`, HEAD
  `328d126b5190f0d2410486331ca272f54020881b`, clean worktree created from live
  `origin/staging`.

## Scope

In scope:

- Add a forward migration; do not edit the migration already deployed.
- Canonicalize successful MAP/eFAST status values to `SUCCESS` in the outbox
  payload and revision comparison.
- Derive a stable `provider_source` for the exported payload, but do not treat
  raw provider-source alternation as a revision-worthy change.
- Preserve revision events for real report changes, including orders and
  statement identifiers.
- Extend the scratch migration verifier for alternating MAP/eFAST replay,
  meaningful updates, atomic rollback and migration rollback.
- Update OPS-9 design and validation documentation.

Out of scope:

- BigQuery provisioning, credentials, worker/backfill enablement or live append.
- Production backlog deletion, compaction or replay.
- Changes to MAP/eFAST dedupe, payment notifications, UI or API contracts.
- Commit, push, PR, staging deploy or production promotion.

## Approach

1. Add immutable SQL helpers for canonical status and provider source.
2. Replace the outbox payload function to use canonical values.
3. Replace the before-write revision function so equivalent success labels do
   not increment revision and raw provider source is not a revision condition.
   Keep identifier, orders and other report-field comparisons unchanged.
4. Add a rollback file that restores the pre-hotfix functions and removes only
   the new helpers.
5. Extend executable scratch-PostgreSQL proof and protected-consumer tests.
6. Run focused proof, full Nest proof, relevant Flutter consumer tests and
   inspect the final diff.

## Risks And Recovery

- Risk: suppressing a real status transition. Mitigation: only known successful
  aliases canonicalize together; other status values remain distinct and are
  covered by a regression test.
- Risk: losing eFAST statement enrichment. Mitigation: provider identifier
  comparisons remain revision-worthy and statement-number proof is explicit.
- Risk: changing an applied migration. Mitigation: use a new forward migration
  with an independent rollback; the original migration remains untouched.
- Recovery: run the new migration's `rollback.sql` to restore the previous
  payload and revision functions. Worker/backfill remain disabled throughout.
- Existing production backlog remains untouched and requires a separately
  reviewed operator action after the hotfix is deployed and observed.

## Progress

- [x] Capture clean branch/HEAD/worktree checkpoint.
- [x] Add forward and rollback migration.
- [x] Extend scratch migration verification.
- [x] Update OPS-9 docs.
- [x] Run focused and affected-consumer proof.
- [x] Review final diff and record result.

## Decisions

- 2026-07-24: Keep PostgreSQL as the source of truth and fix only the outbox
  projection/revision boundary; do not redesign MAP/eFAST persistence.
- 2026-07-24: Treat successful status aliases as equivalent. Provider source is
  descriptive metadata and does not independently create a revision.
- 2026-07-24: Orders and statement identifiers remain report data; a real
  change to either creates a new event.
- 2026-07-24: Do not include production backlog repair in this code hotfix.

## Validation

- Focused proof: Prisma validate, MAP BigQuery focused tests, schema DDL test
  and scratch migration upgrade/rollback verifier.
- Integration proof: alternating MAP/eFAST replay creates no repeated revision;
  orders/status/identifier changes still create exactly one new revision.
- Protected consumers: MAP/eFAST persistence and dedupe, payment notification,
  Bank Statement/XLSX, VietQR and Home Finance backend tests plus relevant
  Flutter tests.
- Repository-required checks: full Nest tests/build and `git diff --check`.

## Result

Implemented a forward-only canonical revision migration without editing the
already-deployed OPS-9 migration. Equivalent MAP/eFAST success/source replay no
longer emits repeated revisions; orders, statement identifier enrichment and
real status changes still emit one event.

Verified locally with scratch PostgreSQL migration/rollback proof, Prisma
validation, BigQuery DDL and focused tests, 298 affected Nest tests, all 869
Nest tests, Nest build, 53 protected Flutter tests and Flutter analyze. Existing
production backlog and live BigQuery remain intentionally untouched.
