# Execution Plan: OPS-61 ERP status sync starvation hotfix

Date: 2026-08-10

## Status

Completed

## Outcome

Production-bound ERP status synchronization filters pending orders that are not
due before applying bounded query limits, and gives both unreported cache rows
and reported sales rows recurring access to the pending quota. Older due rows
must no longer be hidden behind newer rows that are still in backoff or have
already reached the Vietnam-day attempt limit.

## Context

- Product authority: `docs/product/sales-report.md`.
- Story authority: `docs/stories/SALES-REPORT-001-sales-report.md`.
- Runtime producer: `backend-nest/src/sales-reports/sales-reports.service.ts`.
- Existing proof: `backend-nest/src/sales-reports/sales-reports.service.spec.ts`
  and `docs/TEST_MATRIX.md`.
- Production evidence at release `7b981491`: 1,980 reported pending orders were
  due, 1,978 had not been checked in 24 hours, and all 29 retained successful
  runs selected zero `reportedPending` rows.
- Git checkpoint: branch `codex/ops-61-erp-status-sync-starvation`, HEAD
  `7b98149102132fbc6753761cc5dc66bc54d2bc56`, clean worktree. OPS-60 is a
  separate dirty worktree and must remain untouched.

## Scope

In scope:

- Apply the three-hour age, 60-minute backoff, and three-attempt Vietnam-day
  rules in Prisma pending queries before `take`.
- Keep the in-memory eligibility guard as a fail-safe.
- Alternate eligible reported/cache pending candidates so neither source can
  occupy the entire pending window indefinitely.
- Prefer candidates that have waited longest for another attempt, with sale
  recency only as a stable tie-breaker.
- Add focused regression coverage and update product/story/test-matrix truth.

Out of scope:

- Prisma schema or production data changes.
- Manual production sync, backfill, runtime patch, commit, push, PR, deploy, or
  production promotion.
- Changes to completed-order cadence, batch/concurrency, Redis lease, store
  quota, persistence, realtime publication, or Home KPI formulas.
- Long-term scheduler telemetry or backlog administration UI.

## Approach

1. Build typed due-now Prisma predicates for cache and reported pending rows
   using the same Vietnam attempt date and cutoff calculations as the existing
   in-memory guard.
2. Order each due-only source by never/least-recently attempted first, then use
   ERP sale date as a deterministic tie-breaker; keep bounded reads.
3. Interleave reported and cache candidates before applying the existing
   pending/completed and per-store quotas. Mark a code as seen only after the
   fail-safe eligibility guard accepts it.
4. Add a regression that asserts due predicates are applied before `take` and
   proves an older reported row receives a slot while cache candidates exist.
5. Preserve all existing cadence/quota tests and update durable docs.

## Risks And Recovery

- Risk: changing order can increase ERP calls for older rows. Mitigation: batch
  80, concurrency 2, three calls/day, 60-minute backoff, Redis lease and store
  quota remain unchanged.
- Risk: Prisma predicate drifts from the in-memory guard. Mitigation: retain the
  guard and assert both query shape and behavior under fixed Vietnam dates.
- Risk: OPS-60 advances or overlaps this producer. Mitigation: stop before more
  edits and recompute from the new HEAD; never copy or revert OPS-60 files.
- Recovery: before publication, discard only the OPS-61 worktree/branch through
  the approved lifecycle path. After release, rollback is a revert through
  `staging`; the existing `ERP_ORDER_STATUS_SYNC_ENABLED` flag remains the
  emergency kill switch.

## Progress

- [x] Production diagnosis, Linear OPS-61 intake, branch/worktree checkpoint.
- [x] Implement due-only queries and source fairness.
- [x] Add regression tests and update docs.
- [x] Run focused and repository validation.
- [x] Record exact implementation/proof in Linear.

## Decisions

- 2026-08-10: This is a bounded hotfix; no backfill or runtime patch is included.
- 2026-08-10: Fairness alternates reported/cache pending sources and prioritizes
  least-recently attempted due rows. This directly removes both observed
  starvation mechanisms while retaining every ERP load guard.

## Validation

- Focused proof: `npm test -- --runInBand src/sales-reports/sales-reports.service.spec.ts`.
- Integration or end-to-end proof: full `npm test -- --runInBand` from
  `backend-nest/`; no live ERP call in local proof.
- Repository-required checks: `npm run build` and `git diff --check`.

## Result

The hotfix now filters due pending rows before bounded reads, interleaves
reported/cache sources, and keeps the original load and safety guards. Focused
Jest passed 102/102 tests, the Nest build passed, and the full backend suite
passed 104/104 suites with 1,130 tests passed and one existing skip. No live ERP,
staging database, production data, commit, push, PR, or deployment action was
performed. Staging runtime proof remains a release gate outside this local
implementation plan.
