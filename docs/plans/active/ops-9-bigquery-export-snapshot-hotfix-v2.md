# Execution Plan: OPS-9 BigQuery export snapshot hotfix v2

Date: 2026-07-24

## Status

In progress

## Outcome

An existing MAP/eFAST transaction emits a new BigQuery revision only when its
canonical exported report snapshot changes. Raw persistence churn that is
hidden by the canonical statement identifier must not grow the outbox. Real
order, statement, amount, store, status, paid time, income type and delete
changes must still emit exactly one revision.

## Context

- Production release `f67917b2` applied the first canonical status/source
  hotfix successfully.
- Post-deploy proof still observed `+291` events in 47 seconds.
- In the first classified sample, `814/916` events had no export-visible report
  change. `101/146` affected transactions had a raw `transactionNumber` masked
  by a provider identifier in the exported statement number.
- Checkpoint: branch `codex/ops-9-hotfix-bigquery-export-snapshot`, HEAD
  `f67917b2c93efa34672568ffa9b3c1070e4e76f1`, clean worktree created by the
  guarded lifecycle command from live `origin/staging`.

## Scope

- Add a forward migration; do not edit either deployed OPS-9 migration.
- Compare the canonical BigQuery report snapshot at the revision boundary.
- Exclude revision metadata, provider-source description and volatile source
  update time from the comparison.
- Extend scratch PostgreSQL proof with hidden `transactionNumber` churn while
  the exported statement identifier remains stable.
- Preserve proof for orders, identifier enrichment, real status, tombstone,
  atomic rollback and layered migration rollback.

Out of scope until the storm is proven stopped:

- BigQuery provisioning, credentials or worker/backfill enablement.
- Production backlog deletion, compaction or replay.
- Changes to MAP/eFAST persistence, dedupe, notifications, UI or API contracts.

## Recovery

Run this migration's `rollback.sql`. It first restores the deployed v1 trigger
function, then removes the snapshot helper. Worker/backfill remain disabled.

## Progress

- [x] Capture production evidence and a clean task checkpoint.
- [x] Implement forward migration and layered rollback.
- [x] Extend scratch verifier and durable validation docs.
- [x] Run focused, affected-consumer and full validation.
- [ ] Publish through PR to staging and prove runtime soak.
- [ ] Promote only after staging proof and exact protected-release authority.

## Validation gates

- Scratch migration deploy/rollback verifier.
- Prisma validation, focused BigQuery tests and DDL tests.
- Protected MAP/eFAST, Payment Notification, Bank Statement, VietQR and Home
  Finance backend tests plus relevant Flutter consumers.
- Full Nest tests/build and `git diff --check`.
- Staging runtime soak: repeated provider polling produces zero revisions when
  the canonical exported snapshot is unchanged.
