# Execution Plan: OPS-9 production BigQuery enablement

Date: 2026-07-24

## Status

In progress

## Outcome

An existing MAP/eFAST transaction emits a new BigQuery revision only when its
canonical exported report snapshot changes, and production exports a real
transaction through the worker into the BigQuery current view. Raw persistence
churn must not grow the outbox; BigQuery must remain off the ingest/audio
critical path.

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
- PR #27 merged into `staging` and was promoted so `origin/main ==
origin/staging == aec81152414225cd49f1bdad0e7baea770393a1c`.
- Production deploy run `30075963800` applied migration v2, then the candidate
  API exited on PostgreSQL `40P01`. Server logs prove concurrent startup
  `JobRoleDefinition` inserts each invoked the all-user access-version trigger
  and deadlocked. MAP deep-sweep only overlapped in time; it did not issue the
  conflicting SQL.
- The deploy guard restored healthy release `f67917b2`; migration v2 remains
  applied and worker/backfill remain disabled.
- Hotfix checkpoint: branch `codex/ops-9-production-startup-deadlock`, HEAD
  `aec81152414225cd49f1bdad0e7baea770393a1c`, clean worktree created from live
  `origin/staging`.
- Production release `1a2d0fd4` passed startup and public-health proof, but the
  first live schema-provisioning attempt failed closed before creating any
  object because BigQuery rejects `NOT NULL` on repeated `ARRAY` fields. The
  worker/backfill remained disabled and no event was claimed or exported.
- PR #29 merged as `66aa0b96` and its staging deploy passed. Production's
  operator script was backed up and patched to the exact staging checksum; raw
  table/current view provisioning and backup-first backlog canonicalization
  passed. The first one-event canary failed closed with `interior hyphen` before
  writing a row, then the worker was disabled before its second poll.

## Scope

- Add a forward migration; do not edit either deployed OPS-9 migration.
- Compare the canonical BigQuery report snapshot at the revision boundary.
- Exclude revision metadata, provider-source description and volatile source
  update time from the comparison.
- Extend scratch PostgreSQL proof with hidden `transactionNumber` churn while
  the exported statement identifier remains stable.
- Preserve proof for orders, identifier enrichment, real status, tombstone,
  atomic rollback and layered migration rollback.
- Serialize startup writes to access-sensitive default role/personnel catalogs
  so one API process cannot create competing all-user invalidation
  transactions. Keep critical seed failure fail-closed and add sanitized
  start/success/failure timing logs.
- Add a regression test that observes the maximum concurrent catalog writes.
- Keep `orders` as a repeated `ARRAY<STRING>` while omitting the unsupported
  `NOT NULL` modifier from operator DDL; row mapping still always emits an
  array and BigQuery stores repeated fields as empty arrays rather than null.
- Codify the production bug workflow: assess hotfix and full-fix lanes, prefer
  production-impacting hotfixes across competing Linear issues, and allow a
  temporary audited runtime patch only after the Git fix passes staging.
- Supply JavaScript `Date` values for BigQuery Storage Write logical `DATE` and
  `TIMESTAMP` fields; retain the existing outbox JSON format and cover the
  mapper-to-`JSONWriter` encoder boundary with a regression test.

Out of scope until the hotfix is staging- and production-proven:

- BigQuery worker/backfill enablement or backlog mutation.
- Changes to MAP/eFAST persistence, dedupe, notifications, UI or API contracts.
- Broader Storage Write library upgrades or a full live logical-type contract
  suite; track those as full-fix hardening after the bounded hotfix succeeds.

## Recovery

Keep worker/backfill disabled. If the startup hotfix regresses staging, revert
the task commit through `staging`; no schema rollback is needed. Migration v2
retains its existing layered `rollback.sql` recovery path.

## Progress

- [x] Capture production evidence and a clean task checkpoint.
- [x] Implement forward migration and layered rollback.
- [x] Extend scratch verifier and durable validation docs.
- [x] Run focused, affected-consumer and full validation.
- [x] Publish PR #27, deploy staging and prove canonical revision behavior.
- [x] Promote `aec81152`; production migration v2 applied.
- [x] Diagnose failed production candidate and verify automatic rollback.
- [x] Implement and verify startup access-catalog serialization hotfix.
- [x] Publish through a new PR to staging and prove startup/upgrade health.
- [x] Promote/deploy with release guards; prove revision storm remains stopped.
- [x] Implement and locally verify the live BigQuery `ARRAY` DDL compatibility
      hotfix.
- [x] Record the hotfix/full-fix triage and staging-first runtime patch workflow.
- [x] Merge/deploy PR #29, patch the production DDL runtime, provision raw/view
      objects and canonicalize the pending backlog with a persistent backup.
- [x] Fail the first one-event worker canary closed and disable it before the
      second poll after identifying the Storage Write logical-type mismatch.
- [x] Implement and locally verify the `Date`-based logical-type hotfix.
- [ ] Publish the logical-type hotfix through staging and patch production
      runtime before retrying the canary.
- [ ] Publish the live BigQuery `ARRAY` DDL compatibility hotfix through staging
      and production.
- [ ] Provision raw/current BigQuery objects, safely canonicalize the pending
      backlog, enable a bounded worker canary and query one real transaction from
      BigQuery before completing OPS-9.

## Validation gates

- Scratch migration deploy/rollback verifier.
- Prisma validation, focused BigQuery tests and DDL tests.
- Protected MAP/eFAST, Payment Notification, Bank Statement, VietQR and Home
  Finance backend tests plus relevant Flutter consumers.
- Full Nest tests/build and `git diff --check`.
- Staging runtime soak: repeated provider polling produces zero revisions when
  the canonical exported snapshot is unchanged.
- Focused `UserService` startup regression proves catalog writes have maximum
  concurrency `1`; auth/bootstrap and organization/user admin consumers pass.
- Production deploy health proves zero startup deadlocks/restarts before any
  BigQuery feature flag changes.
- Final end-to-end proof records a PostgreSQL transaction/outbox revision,
  worker success and matching row returned from the BigQuery current view.

## BigQuery ARRAY DDL compatibility local proof — 2026-07-24

- Raw/current DDL tests PASS, 2/2; the regression rejects
  `orders ARRAY<STRING> NOT NULL`.
- Focused BigQuery mapper/config/writer PASS, 3 suites / 6 tests.
- Prisma schema validate PASS; Nest build PASS; full Nest PASS, 89 suites /
  870 tests.
- Worker/backfill and live BigQuery provisioning remained untouched during
  local proof.

## Storage Write logical-type hotfix local proof — 2026-07-24

- The production one-event canary wrote zero rows and returned the sanitized
  error `interior hyphen`; the event remained retryable and the worker was
  disabled before its second poll.
- The installed encoder maps BigQuery `DATE` to protobuf `int32` and
  `TIMESTAMP` to `int64`, converting them only when row values are JavaScript
  `Date` instances. The mapper had supplied ISO strings.
- Mapper/config/writer focused proof PASS, 3 suites / 7 tests; the new
  regression passes mapped logical values through `managedwriter.JSONWriter`
  before a fake Storage Write request. Nest build PASS; full Nest PASS, 89
  suites / 871 tests.

## Startup deadlock hotfix local proof — 2026-07-24

- Focused `UserService` PASS: 1 suite / 64 tests; the new regression observed
  more than one catalog write and maximum concurrent writes exactly `1`.
- Shared access consumers PASS: 6 suites / 126 tests for user, feature, policy,
  auth context, bootstrap and controller behavior.
- Full Nest PASS: 89 suites / 870 tests; Nest build PASS; Prisma schema validate
  PASS; OPS-9 DDL 2/2 PASS; scratch migration/replay/layered rollback verifier
  PASS against disposable PostgreSQL on `localhost`.
- Flutter protected auth, Bank Statement, Payment Monitor, VietQR and Home
  consumers PASS: 147 tests with file concurrency `1`; Payment Monitor provider
  also passed independently 41/41. The first parallel multi-file run had one
  test-isolation failure and is not counted as proof. Flutter analyze reported
  no issues.
- Remaining proof is environmental: staging and production candidate startup
  must show healthy API, completed seed timing and no PostgreSQL deadlock before
  any worker/backfill flag changes.
