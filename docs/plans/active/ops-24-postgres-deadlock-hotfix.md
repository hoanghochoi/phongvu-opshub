# Execution Plan: OPS-24 PostgreSQL Deadlock Hotfix

Date: 2026-07-25

## Status

Active

## Production release recovery — 2026-07-25

- Promotion reached `main` at `5bbb6396`, but production deploy run
  `30152246314` failed while building Sharp on the `aarch64` host. The image
  recipe built the correct arm64 addon and then asserted an x64-only filename.
- The workflow had already switched the release symlink and stopped API,
  realtime and Caddy. Its ERR trap was not inherited through `compose_cmd`, so
  the intended rollback did not execute. Production was recovered manually to
  `d488571f`; all core containers and public health endpoints passed afterward.
- Recovery scope: derive the Sharp musl addon/libvips directory from
  `process.arch` for supported x64 and arm64 builds, and explicitly route every
  risky compose step through rollback in addition to enabling ERR inheritance.
- The failed run had already published client artifacts and version metadata
  before the backend image failed. The public clients are compatible because
  `d488571f..5bbb6396` contains no Flutter runtime change, but production is a
  partial release until the backend is deployed. Transactional publication of
  runtime, env metadata, web and downloads remains a separate full-fix scope;
  it is intentionally not folded into this bounded recovery hotfix.
- Required proof before another release: static Dockerfile/workflow guards,
  full Nest/build proof, isolated x64 image proof when available, isolated
  arm64 image build plus Sharp PNG runtime control on the production host, then
  the normal PR -> staging deploy/QA -> protected promotion flow.

## Outcome

Production producers and the Home projection worker no longer form the known
PostgreSQL lock cycle. A transient `40P01` at an idempotent database boundary
is retried at most three total attempts with short exponential backoff and
jitter, while every other error is returned immediately.

## Context

- Linear `OPS-24` is the accepted hotfix contract and `OPS-23` is the
  production-log evidence: 130 deadlocks in the audited 24-hour window and
  about 14 after production release `d488571f`.
- `docs/decisions/0009-home-summary-outbox-projection.md` requires durable,
  transaction-coupled queue dirtying plus lease, dirty-generation and outbox
  semantics. The hotfix may not weaken those guarantees.
- `docs/stories/HOME-DASHBOARD-003-near-realtime-projection.md` owns the Home
  projection SLO: commit-to-complete p95 <= 5 seconds and p99 <= 15 seconds;
  Home API p95 <= 500 ms and p99 <= 1 second.
- The current SQL function in
  `20260720143000_home_projection_phase1_closure` locks
  `HomeSummaryProjectionState` before `HomeSummaryProjectionQueue`. The worker
  `finalizeProjection` and its error recovery transaction lock queue before
  state. This opposing order is the observed cycle.
- MAP ingestion persists a unique `transactionKey` before creating a payment
  notification. Sales Report cache/status writes use unique `orderCode` upserts
  and idempotent status updates. Home queue work is coalesced by
  `(summaryDate, projectionKind)` and guarded by claim token plus generation.

## Scope

In scope:

- A forward Prisma migration that acquires all affected Home queue rows in a
  stable kind order before projection state and source-outbox rows.
- A reusable PostgreSQL deadlock detector/retry helper that traverses Prisma
  driver-adapter causes, accepts only exact SQLSTATE `40P01`, uses three total
  attempts, deterministic-testable jitter and sanitized operational logs.
- Retry integration at MAP transaction upsert, Sales Report ERP cache/status
  persistence, Home finalize and Home reconciliation enqueue boundaries.
- Unit tests plus a scratch-PostgreSQL concurrency verifier for the old cycle
  and the corrected contention path.
- Affected-consumer proof for Payment Speaker notification creation, Home
  freshness/queue semantics, Sales Report scheduler/cache and MAP BigQuery
  outbox revisions.

Out of scope:

- Production database writes, ad-hoc lock termination, backfill, manual runtime
  patching, BigQuery worker enablement or payment-speaker latency changes.
- Direct pushes to `staging` or `main`, and production promotion without the
  repository's separate protected-release authorization and gates.

## Approach

1. Add failing unit coverage for exact SQLSTATE detection, bounded attempts,
   deterministic backoff/jitter, exhaustion and non-retryable errors.
2. Add a forward migration with one multi-kind enqueue primitive. It locks
   queue keys in deterministic order, updates state once, then updates source
   outbox rows and emits wake-up notifications. Existing single-kind and
   source-aware functions delegate to that primitive.
3. Add a scratch database verifier: manually reproduce the legacy
   queue/state cycle and observe one `40P01`; then contend a worker queue lock
   with the migrated function and prove both transactions complete without a
   deadlock while coalescing one queue job.
4. Wrap only idempotent database operations at the three victim boundaries.
   Preserve the original error after the third failed attempt and leave the
   Home job unacknowledged so the durable worker retry remains available.
5. Run focused tests first, then migration/concurrency, Prisma, Nest build/full
   tests and all mapped affected-consumer suites on the final fingerprint.

## Risks And Recovery

- Risk: queue coalescing, dirty generation or new-date dual-kind enqueue could
  regress. Mitigation: migration verifier checks stable lock order, one row per
  date/kind, generation increments and both kinds for a new date.
- Risk: retrying a non-idempotent side effect could duplicate notifications or
  outbox revisions. Mitigation: retry ends at the database upsert/transaction;
  notification publication remains after a successful MAP write, and durable
  rows keep their unique/dedupe keys.
- Risk: a broad error matcher could retry business or infrastructure failures.
  Mitigation: inspect structured `code`/`originalCode`/`sqlState` fields only;
  never match error-message text.
- Recovery: revert the application commit and apply the migration's
  `rollback.sql`, which restores the pre-hotfix functions. This is safe only
  through the normal staging/deploy workflow; do not patch production runtime
  manually.

## Progress

- [x] Checkpoint clean canonical `staging` and live `origin/staging` at
  `c9aa2c37554cb1f14e46b5df0b74b541153dfb2d`.
- [x] Create `codex/ops-24-deadlock-bounded-retry` with lifecycle `START PASS`.
- [x] Derive the lock graph and map protected consumers.
- [x] Add retry helper and unit tests.
- [x] Add lock-order migration, rollback and concurrency verifier.
- [x] Integrate retry at MAP, Sales Report and Home boundaries with tests.
- [x] Run final local and affected-consumer proof.
- [x] Recover production to healthy `d488571f` after failed run `30152246314`.
- [x] Prove the recovery image on the production ARM64 host without touching
  the running Compose project.
- [ ] Merge the release-recovery PR to `staging`, deploy/QA it and complete a
  new protected production promotion.

## Decisions

- 2026-07-25: Treat the work as high-risk because it changes a shared
  PostgreSQL trigger, background worker and existing producer behavior.
- 2026-07-25: Preserve queue/state/outbox durability and remove the cycle by
  consistent lock order; bounded retry is defense in depth, not the root fix.
- 2026-07-25: Use three total attempts with short in-process delays only for
  exact `40P01`; the existing durable Home retry remains the longer recovery
  path after exhaustion.
- 2026-07-26: Keep the ARM64/rollback recovery narrow. Record transactional
  publication as the durable release-workflow follow-up because the failed run
  proved that client metadata can advance before backend success.

## Validation

- Focused proof: retry-helper, MAP, Sales Report and Home projection Jest passed
  4 suites/226 tests.
- Integration proof: scratch PostgreSQL reproduced exactly one legacy
  `40P01`; migrated contention completed both transactions with one queue row
  and one generation increment. Migration up/down/reapply passed.
- Affected consumers: Payment Notification/Payment Speaker, full Home Summary,
  Sales Report ERP/BigQuery and MAP BigQuery passed 11 suites/135 tests.
- Migration chain: Home Phase 1 passed seed `90/180/180`, 5,000 signals to one
  job and rollback; OPS-24 passed; MAP BigQuery passed stable replay,
  identifier enrichment, dedupe, tombstone and layered rollback.
- Repository checks: Prisma format/validate/generate passed; Nest build passed;
  full Nest passed 90 suites/887 tests; `git diff --check` passed.
- Release recovery proof: Dockerfile/workflow contract guards and YAML parsing
  passed; explicit compose-failure routing preserved status `17` and invoked
  rollback; the isolated production-host image reported `linux/arm64`, loaded
  Sharp `0.35.3` with libvips `8.18.3`, and generated a 2x2 PNG with no network.
  The proof image and remote temporary files were removed afterward while the
  OPS-24 hotfix backup was retained.

## Result

Local implementation is verified. Production lock-cycle removal is represented
by the forward migration and bounded retry is integrated at all accepted victim
boundaries. No production/staging runtime was changed. Remaining proof is the
PR/CI staging deploy plus concurrent soak, followed by explicit production
promotion and bounded post-deploy log audit.
