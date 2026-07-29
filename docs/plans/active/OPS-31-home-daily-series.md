# Execution Plan: OPS-31 Home Daily Series

Date: 2026-07-29

## Status

Active

## Outcome

`GET /home/summary` optionally returns an authorized, ascending, zero-filled
daily series for the selected 1/7/30/90-day range without changing the existing
aggregate response for clients that do not opt in. The daily values come from
the complete Home projection, preserve aggregate parity and scope semantics,
and meet the existing Home latency/reliability gates.

## Context

- Linear OPS-31, including architecture Q1-Q7, decision-engine sensitivity,
  implementation checkpoint, and the approved additive API/cache contract.
- `docs/product/backend-platform.md` and `docs/product/sales-report.md`.
- `docs/stories/HOME-DASHBOARD-002-sales-finance-kpis.md`.
- `docs/stories/HOME-DASHBOARD-003-near-realtime-projection.md`.
- `docs/decisions/0009-home-summary-outbox-projection.md`.
- `backend-nest/src/home-summary/` and its focused tests.
- `docs/TEST_MATRIX.md` and `deploy/staging/load-proof-runbook.md`.

Checkpoint:

- Branch: `codex/ops-31-home-daily-series`.
- Base and initial HEAD:
  `bbba1e736c9ad244d0e05a351596c18a3f27475e`.
- Base equals live `origin/staging`; canonical staging and task worktree were
  clean when the lifecycle `start --execute` gate passed.

## Scope

Lane: high-risk because the change touches a public authenticated API contract,
authorization/scope, existing consumers, response cache behavior, a shared
projection producer, background invalidation, PII-derived scope, and
verification/load tooling.

In scope:

- Strict optional query `includeDailySeries=true|false`, default false.
- Optional response `dailySeries` with `date`, `totalRevenue`,
  `totalOrders`, `reportedOrders`, and `totalReports`.
- Inclusive ascending zero-fill for at most 90 opted-in days.
- One range-wide SALES projection query, grouped by date in memory.
- Exact ALL/MANAGED_SCOPE/OWN and selected-SA sales semantics.
- Existing range-wide freshness, 60-second response cache, refresh-ahead,
  in-flight dedupe, generation/race protection, and per-date invalidation.
- Vietnamese action-oriented validation errors and sanitized AppLogger/Nest
  lifecycle logs.
- Focused/full backend proof, old Flutter consumer proof, load/parity tooling,
  product/story/test-matrix updates, PR, staging deploy, and executable staging
  proof available without credential disclosure.

Out of scope:

- Flutter chart UI or visual redesign.
- New metrics, finance daily series, schema/migration, service/database split,
  realtime event type, permission, rate limit, source formula, or ranges above
  90 days.
- Production promotion; `Done` still requires production deployment.

## Approach

1. Add strict DTO parsing and keep the existing controller route.
2. Extend the response type with an optional daily point array.
3. Reuse the current projection scope predicate, select `summaryDate` plus
   additive metrics once for the full range, group/store sums by date, and
   zero-fill expected dates.
4. Attach the series only when opted in and sales access/scope is available.
5. Separate cache generations by opt-in flag while preserving every existing
   TTL, dedupe, refresh, invalidation, and stale/503 behavior.
6. Add start/success/failure/branch logs with flag/day/grain/duration and no
   raw user, email, order, or payload values.
7. Extend focused tests and affected-consumer/load proof before broad gates.
8. Update durable docs and this plan with actual results before publication.

## Risks And Recovery

- Scope leak or selected-SA drift: reuse the exact `salesMetricsScope` built
  for aggregate sales metrics and test every supported scope.
- Aggregate parity drift: derive all four values from the same projected rows
  and compare sums with the aggregate response in tests and staging proof.
- N+1 or latency regression: enforce one projection query per opted-in request,
  cap the series at 90 days, and measure p50/p95/p99/max.
- Cache cross-contamination: include the strict opt-in value in a bumped cache
  key version and retain version-aware invalidation/race tests.
- Permission ambiguity: omit the optional series when sales is unavailable;
  preserve the existing aggregate unavailable response.
- Recovery before merge: discard or revert only this task branch/worktree.
- Recovery after staging merge: revert the squash commit through a reviewed PR;
  no database rollback is required because the change adds no schema or state.
- Stop if implementation requires a schema, new event, new permission, new
  metric, synchronous fact read/rebuild, or a range above 90 days.

## Progress

- [x] Guarded task branch/worktree created from exact live staging.
- [x] Architecture Q1-Q7 and SLO/RPO/RTO authority recorded in Linear.
- [x] Additive API/cache contract recorded and read back in Linear.
- [x] Product, story, decision, code, and existing proof reviewed.
- [x] Implement DTO/service/cache/logging behavior.
- [x] Add focused backend and old Flutter consumer tests.
- [x] Extend load/parity proof and durable product/test documentation.
- [x] Run focused, affected-consumer, build, full relevant, and diff checks.
- [x] Independent code/security review and fix all actionable findings.
- [x] Record exact implementation proof in Linear, publish PR #52 to staging,
      and pass CI.
- [x] Merge PR #52, run lifecycle finish, and deploy exact staging SHA
      `6fc7c530e5e52a7be02bb0ed463d270231d0bdf1`.
- [x] Run staging smoke and the first fixed 250-VU/2,000-request proof; record
      the latency failure and complete mandatory synthetic-user/token cleanup.
- [x] Reduce cold principal/shape computation without sharing user responses or
      weakening scope, parity, cache invalidation, or thresholds.
- [ ] Re-run local affected-consumer proof, independent review, PR/CI/lifecycle,
      exact-SHA staging deploy, cold load QA, selected-SA QA, and cleanup.

## Decisions

- 2026-07-29: p99 capacity envelope 50 QPS and read:write 20:1; this is
  capacity planning, not a rate limit.
- 2026-07-29: Shared multi-tenant, sync request path with async projection
  jobs, PII tier, and existing NestJS modular monolith.
- 2026-07-29: RPO 24 hours, RTO 4 hours, success SLO at least 99.9% over
  rolling 30 days, p50/p95/p99 at 250/500/1000 ms, max 3 seconds, Engineering
  owns the error budget, and promotion stops below 25% remaining.
- 2026-07-29: Reuse `GET /home/summary` with strict opt-in and an optional
  four-metric series; old clients receive the old response.
- 2026-07-29: Series follows selected-SA sales scope, omits when sales is
  unavailable, reuses top-level freshness, and never enters Redis/realtime.

## Validation

- Focused proof:
  - `npm test -- --runInBand src/home-summary/home-summary.dto.spec.ts src/home-summary/home-summary.controller.spec.ts src/home-summary/home-summary.service.spec.ts`.
  - Projection/outbox and Sales Report scope suites protecting the shared
    producer/scope resolver.
  - Flutter Home parser/dashboard/repository cache/realtime focused tests with
    an unknown optional `dailySeries` fixture.
- Integration or end-to-end proof:
  - Existing Home phase-1 HTTP/parity proof extended for opted-in 1/7/30/90.
  - Staging 250 concurrent / 2,000 request proof: success >=99.9%,
    p50/p95/p99 <=250/500/1000 ms and max <=3 seconds.
  - Authenticated staging response checks for authorized scope, selected-SA,
    unavailable sales, zero-fill, parity, freshness, and legacy no-flag shape.
- Repository-required checks:
  - Nest Prettier/check, build, and full relevant Jest.
  - Flutter analyze and affected Home tests; broaden to full Flutter if shared
    parsing/cache files change or focused evidence is insufficient.
  - `git diff --check`, exact diff review, clean task worktree, and unchanged
    canonical staging/other task worktrees.

## Result

Local implementation is complete and remains uncommitted for independent
review. `GET /home/summary` now accepts only the exact optional strings `true`
or `false`; `true` returns the authorized four-metric series from the same
single range-wide SALES projection query used for aggregate metrics. Points are
ascending and zero-filled, the inclusive range is capped at 90 days, and the
series is omitted without Sales access. Cache key `v4` separates legacy/false
from opted-in responses while retaining the existing TTL, refresh-ahead,
in-flight dedupe, per-date version invalidation and stale-store protection.
Strict opted-in reads do not enter the legacy synchronous fact fallback.

Local evidence:

- Focused Home DTO/controller/service Jest: 3 suites, 62 tests passed.
- Shared projection producer and Sales scope Jest: 2 suites, 99 tests passed.
- Full Nest Jest: 90 suites, 939 tests passed; `npm run build` passed.
- Existing Flutter Home/cache/dashboard/realtime/details/avatar proof: 48 tests passed,
  including a legacy repository request that does not opt in and ignores an
  unknown `dailySeries`; `flutter analyze --no-pub` passed with no issues.
- Changed TypeScript/JavaScript Prettier, both k6 `node --check` commands and
  `git diff --check` passed. The paired legacy/daily comparator passed 3 Node
  tests, preserves the fixed 2,000-request envelope as 1,000 same-principal/
  same-range pairs, and fails on cross-variant aggregate drift. Both load
  profiles enforce p50/p95/p99/max `250/500/1000/3000 ms` for Home, including
  each 1/7/30/90-day range.

Independent review found and closed two Medium proof gaps (matched
legacy/opt-in parity and real opted-in selected-SA isolation) plus one Low
daily-cache invalidation gap. Codex Security completed all 7 source-like
worklist rows with zero reportable findings.

Unverified release gates are authenticated staging response/parity checks, the
fixed 250-concurrent/2,000-request profile,
exact-SHA deploy/QA, and publication lifecycle. No local k6 or authenticated
staging run is claimed here.

### Staging QA attempt 1 and recovery

PR #52 deployed successfully through staging workflow run `30452682182` at the
exact squash SHA `6fc7c530e5e52a7be02bb0ed463d270231d0bdf1`. The public health,
direct-origin, client artifact, side-effect guard, symlink and container checks
passed. Authenticated smoke proved legacy/daily contract, 1/7/30/90 ordering,
zero-fill, parity and non-stale freshness.

The fixed cold profile then returned 2,000/2,000 HTTP 200 responses with 100%
contract/parity and zero 429/5xx, but failed latency: client p50/p95/p99/max
were `612.27/2537.48/2872.48/3228.62 ms`; server-side values were
`494/2094/2241/3002 ms`. The exact window contained 120 misses, 417 in-flight
joins and 1,463 hits. API CPU briefly peaked at 147.29%, while PostgreSQL used
at most 17/100 connections, Redis had zero evictions/blocked clients and no
runtime container restarted. Exactly 60 synthetic users/sessions were revoked
and deleted; server/local token files and k6 processes were verified absent.

The bounded full-fix keeps response caches principal-specific. It may dedupe
only inputs proven independent of the principal (range-wide projection
freshness and store/global sales progress), reuse principal-specific progress
between the legacy and daily response shapes, extend a fresh legacy response
with one same-scope daily projection read, parallelize independent projected
SALES/FINANCE reads, and move per-request hit/join diagnostics to debug. Any
scope ambiguity, parity drift, stale-version race, schema/event/permission
change or weakened cold-load threshold stops the fix.

### Full-fix local proof

The full-fix remains additive and requires no schema, migration, event,
permission, rate-limit or Flutter production change. Exact local gates on the
full-fix changeset passed:

- Home DTO/controller/service Jest: 3 suites, 69 tests.
- Shared projection producer and Sales scope Jest: 2 suites, 99 tests.
- Full Nest Jest: 90 suites, 946 tests; Nest build passed.
- Existing Flutter Home parser/cache/dashboard/realtime/details/avatar
  consumers: 48 tests; `flutter analyze --no-pub` found no issue.
- Changed Home TypeScript Prettier and `git diff --check` passed.

The remaining release-readiness proof is PR review/CI, exact-SHA staging
deployment, the unchanged cold 250-VU/2,000-request profile, authenticated
selected-SA scope checks, resource monitoring and mandatory synthetic cleanup.
