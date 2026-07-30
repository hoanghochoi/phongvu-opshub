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

### Staging QA attempt 2 and authentication follow-up

PR #53 deployed successfully at exact staging SHA
`8bb651fa7b5944956cfb4cf9abdccc017f73ef62` through run `30459662495`.
Authenticated smoke again passed the legacy/daily 1/7/30/90-day contract,
ordering, zero-fill, parity and freshness. The fixed cold profile returned
2,000/2,000 HTTP 200 with 100% contract/parity and zero 429/5xx/timeout, but
failed latency: client p50/p95/p99/max were
`625.40/2140/2860/5630 ms`; server Home values were
`464/1560.25/2001.04/2284 ms`.

The Home full-fix was active: there were only 60 initial misses and 60 daily
extensions for the 60 principal/range shapes. Daily extension p50/p95/p99/max
fell to `145/304.7/338.4/339 ms`, while the 60 initial authenticated loads
remained at `1713/1957.2/2027.84/2042 ms`. API CPU briefly peaked at 140.46%,
PostgreSQL peaked at 17/100 connections with zero active wait, Redis had zero
evictions/blocked clients and no container restarted. All 60 synthetic users
and sessions were revoked/deleted and both token copies were verified absent.

Correctness and security review rejected the initial whole-validation
single-flight approach: a request starting after a committed lock, token change,
access change or session revocation could join an older request's pending
promise and receive its stale authorization result. Settlement cleanup and a
generation-rich key did not close that race because the key contained signed
claims rather than current database state. The earlier local proof counts for
that rejected implementation are therefore superseded.

The corrected bounded fix removes all cross-request validation sharing. Every
protected request executes its own narrowly parameterized PostgreSQL statement
that left-joins `User` and `UserPlatformSession`, so status, token version,
current access version, session identity/platform/version, revocation and expiry
come from one per-request statement snapshot. Existing behavior remains: token
version is compared with the signed claim, current access version is returned
as the authorization-context generation, and session failures retain the
existing Vietnamese responses. Each query result produces a request-local user
principal and auth-session object. The implementation does not enable a global
Prisma relation strategy and changes no schema, migration, token, permission,
event or API contract. The existing `AuthSessionService` remains the single
authority for platform, version, revocation, expiry, Vietnamese response and
sanitized rejection-log semantics; the JWT strategy supplies its preloaded row
without issuing a second query. Focused auth/session proof, affected-consumer
proof and another exact cold staging run remain mandatory before release
readiness.

Corrected pre-integration local proof passed: JwtStrategy plus AuthSessionService
2 suites/23 tests, Nest build, changed-file Prettier and `git diff --check`.
Exact-SHA staging load/cleanup remains the release gate.

### Staging QA attempt 3 and pre-query batch follow-up

PR #55 deployed successfully at exact staging SHA
`967613e2d47dad4d3050f21bdfa4eaf6ab7e0d36` through run `30469998848`.
Authenticated smoke passed auth, bootstrap, scopes and legacy/daily 1/7/30/90
ordering, zero-fill, parity and freshness. The fixed cold profile again returned
2,000/2,000 HTTP 200 with 100% contract/parity and zero 429/5xx/timeout, but
failed latency: client p50/p95/p99/max were
`474.12/2530/3400/4080 ms`; server Home values were
`339/1758.05/2180.06/2786 ms`.

There were still only 60 initial Home loads and 60 daily extensions. Extension
p50/p95/p99/max was `150.5/324.65/491.41/492 ms`, while initial loads were
`1839/2294.45/2689.28/2694 ms` under contention from 2,000 per-request auth
snapshot queries. API CPU peaked at 143.15%, PostgreSQL at 82.21% with at most
17/100 connections, one active connection in sampled windows and zero active
wait; Redis had no eviction/blocked client and no container restarted. Cleanup
revoked/deleted exactly 60 synthetic sessions/users and proved zero remaining
records plus absent server/local tokens and k6 process.

The next bounded fix may batch only requests that are waiting **before** the
authoritative snapshot statement starts. A two-millisecond window groups exact
signed user/token/access/session/platform generations; the map entry is removed
synchronously before calling PostgreSQL. A request arriving after that point
always creates a later batch/query and therefore cannot reuse an older database
snapshot. If a lock/revocation commits while a batch is still open, its later
query observes the changed state. There is no TTL or post-query sharing, each
caller receives independent principal/session/Date objects, and map saturation
falls back to an independent full validation. Regression proof must cover both
sides of the query-start boundary before another staging run.

### Pre-query batch local proof

The bounded implementation uses the approved two-millisecond pre-query window
and deletes the exact map entry before issuing the authoritative PostgreSQL
statement. The validation key includes the exact user claim plus normalized
token/access/session/platform generations. Missing or malformed session keys
bypass batching and execute full validation. A 5,000-entry cap is fail-closed:
an already-open exact batch can still accept its matching caller, while new
principals execute independent snapshot queries without growing the map. No
result or in-flight query is shared after the statement starts.

Exact local proof on the final three-file fingerprint passed:

- JwtStrategy: 17 tests, including 250 requests across 60 principals producing
  exactly 60 snapshot queries; before-query lock visibility; after-query lock,
  token and session isolation; exact-claim separation; request-local mutable
  objects; and saturation join/overflow behavior.
- JwtStrategy plus AuthSessionService: 2 suites, 28 tests.
- Affected auth/session/throttler/Home: 11 suites, 173 tests.
- Full Nest: 90 suites, 961 tests; Nest build passed.
- Existing Flutter auth bootstrap/session/access-refresh/realtime/Home
  consumers: 76 tests; `flutter analyze --no-pub` found no issue.
- Changed-file Prettier and `git diff --check` passed.

No schema, migration, token, permission, event, rate-limit or public API
contract changes. Expand/contract migration policy is therefore not invoked.
Remaining gates are PR/CI/lifecycle, exact-SHA staging deployment, unchanged
cold 250-VU/2,000-request load proof, selected-SA isolation and mandatory
synthetic cleanup.

### Staging QA attempt 4 and cross-principal statement batching

PR #56 deployed successfully at exact staging SHA
`d108748eb7ef9d89170613d2ce4bd7eaaff3df2d` through run `30474756531`.
Authenticated smoke again passed auth, bootstrap, scopes and legacy/daily
1/7/30/90 ordering, zero-fill, parity and freshness. The fixed cold profile
returned 2,000/2,000 HTTP 200 with 100% contract/parity and zero
429/5xx/timeout, but still failed latency. Client p50/p95/p99/max were
`425.9/2130/2910/3360 ms`; server Home values were
`312/1610.2/2368.17/2741 ms`.

The exact-principal pre-query window grouped 483 requests in 185 multi-caller
batches, saving 298 statements and leaving an inferred 1,702 snapshot
statements. Sixty initial Home loads remained at
`1655.5/2468.3/2642.71/2661 ms`; sixty daily extensions were
`178.5/318.25/365.61/378 ms`. API CPU peaked at 137.10% and PostgreSQL at
87.06% with at most 17/100 connections, one active connection and zero active
wait in samples. Redis had no eviction/blocked client and no container
restarted. Cleanup revoked/deleted exactly 60 synthetic sessions/users and
proved zero remaining records plus absent server/local tokens and k6 process.

The next bounded fix keeps the same query-start security boundary but batches
all requests already waiting in the two-millisecond window into one
parameterized PostgreSQL statement. The pending array is detached before that
statement starts; requests arriving afterward form a later batch and cannot
reuse its snapshot. `jsonb_to_recordset` supplies a generated request index,
exact user id and normalized session id; indexed user/session joins return one
row per request. Token, current access state, platform, session version,
revocation and expiry are still evaluated separately for every caller, with
request-local principal/session/Date objects. A missing/locked user rejects only
its matching request, database failure rejects the whole batch, and a 5,000
pending-request cap falls back to independent full validation. There is no TTL,
post-query sharing, schema, migration, token, permission, event, rate-limit or
public API change.

### Cross-principal statement-batch local proof

The implementation detaches the pending array synchronously before issuing the
database statement. A 250-request burst across 60 distinct principals therefore
uses one parameterized statement while every request retains its own payload,
row index, authorization evaluation and cloned principal. A live read-only
staging `EXPLAIN` with nonexistent synthetic ids confirmed the SQL syntax and
primary-key user join; the lateral session lookup remains bounded to the exact
session id. No data row or PII was returned by that check.

Exact local proof on the final three-file fingerprint passed:

- JwtStrategy: 20 tests covering the one-statement 250-request burst,
  before-query lock visibility, after-query lock/token/session isolation,
  mixed-principal failure isolation, immutable captured claims, query-failure
  cleanup/recovery, request-local mutable objects and fail-closed saturation.
- JwtStrategy plus AuthSessionService: 2 suites, 31 tests.
- Affected auth/session/throttler/Home: 11 suites, 176 tests.
- Full Nest: 90 suites, 964 tests; Nest build passed.
- Existing Flutter auth bootstrap/session/access-refresh/realtime/Home
  consumers: 76 tests; `flutter analyze --no-pub` found no issue.
- Changed-file Prettier and `git diff --check` passed.

No migration exists in this changeset, so expand/contract policy is not
invoked. Remaining release gates are PR/CI/lifecycle, exact-SHA staging deploy,
the unchanged cold load profile, selected-SA isolation and mandatory synthetic
cleanup.

### Staging QA attempt 5 and single Home auth-context hydration

PR #57 deployed successfully at exact staging SHA
`6a1bee1a5989a6840636c2dffbb93baa5f0bbf52` through run `30479218523`.
Before merge, a read-only PostgreSQL transaction with two real user/session
fixtures proved numeric request-index mapping, duplicate-principal isolation,
valid association, inactive-session and cross-principal mismatch visibility,
and missing-user omission; the transaction was rolled back and emitted no id
or token. Release Guard, CodeQL, runtime health and the five disabled
side-effect flags passed, with no SMTP variables present.

Synthetic run `ops31batch-20260730-0135` passed auth/bootstrap/scopes and
legacy/daily 1/7/30/90 contract, ordering, freshness and parity. The fixed
profile returned 2,000/2,000 HTTP 200 with 100% contract/parity and zero
429/5xx/timeout, but latency still failed. Client p50/p95/p99/max were
`216.13/2210/2560/2820 ms`. Sixty cold Home loads were
`1892/2045/2056.1/2062 ms`, while 59 daily extensions were only
`76/113.1/120.84/122 ms`. API CPU peaked at 123.01%, PostgreSQL at 60.82%,
connections at 17/100 with one active and zero waiting, and Redis/restart
signals stayed clean. Cleanup revoked exactly 60 users/sessions, deleted
exactly 60 users and proved zero remaining/tagged/code/reference rows plus
absent server/local tokens and k6 process.

The remaining cold path resolves section features twice and the Home scope
once. Without an attached auth context, those consumers may independently
hydrate the same user/organization snapshot before projection reads begin.
`AuthContextService` already owns the versioned scope snapshot and feature map,
with L1/Redis/in-flight isolation per exact principal, but Home summary did not
reuse it. The next bounded fix hydrates that existing context once per response
cache miss and passes the same request-local enriched principal to section
access, scope resolution and sales-progress work. Sanitized stage timings are
added to distinguish context, section, scope, projection preparation, progress
and metric reads on the next exact-SHA run.

This does not share context across principals or tenants, weaken a permission
check, change cache identity, alter API/schema/migration behavior, or change
Home calculations. Expand/contract migration policy is not invoked. Required
proof covers context propagation, auth-context version isolation, Home legacy
and daily consumers, full affected backend/Flutter gates, exact-SHA load and
mandatory cleanup.

### Staging QA attempt 6 and Home-specific authorization slice

PR #58 deployed successfully at exact staging SHA
`c5b6ea33ced8ec575dd09aa6b03a1da6cf90738c` through run `30482995010`.
Authenticated smoke again passed the supported Home contract. Synthetic run
attempt 6 returned 2,000/2,000 HTTP 200 with 100% contract and parity, zero
429/5xx/timeout, and client p50/p95/p99/max of
`144.17/2150/2410/2520 ms`. Sixty cold Home loads remained
`1647/2026/2062/2071 ms`, while daily extension was only
`72/102/102.42/103 ms`.

Sanitized server timings isolated the cold bottleneck. Full auth-context
hydration was `1269/1421 ms` at p50/p95, section access was `0/0 ms`, scope
resolution `279/425 ms`, sales progress `104/183 ms`, and metrics `62/89 ms`.
API CPU peaked at 141.43%, PostgreSQL at 61.06%, and database connections at
17/100 with two active and zero waiting. Containers remained healthy with zero
restart. Cleanup revoked and deleted exactly 60 synthetic users/sessions and
proved zero remaining tagged/email-code/reference records, absent server/local
tokens, and no k6 process.

The full context is semantically correct but needlessly projects profile data,
all feature and policy maps, and Redis serialization for a Home cold miss. The
next bounded fix therefore loads only the existing organization scope snapshot
and resolves exactly `HOME_DASHBOARD_SALES` plus
`HOME_DASHBOARD_FINANCE`. Requests already waiting in a two-millisecond window
share one Prisma `user.findMany` scope read across exact user ids. The pending
array is detached before the query starts; later requests form a later batch.
Missing users deny both features, query failure rejects only that detached
batch, and a 5,000-request cap falls back to the existing independent
`findUnique` scope read. There is no TTL, post-query cache, Redis access,
profile projection, policy hydration, cross-request result reuse, or public
contract change.

The selected shared multi-tenant deployment model is preserved: each returned
row is associated only with its exact globally unique user id, and feature
evaluation continues through the user's own organization roots and active node
assignments. No schema or migration is introduced, so old and new runtimes use
the same database shape and the expand/contract migration policy is not
invoked. Exact-SHA staging latency, selected-SA isolation, affected consumers,
and mandatory synthetic cleanup remain release gates.

### Home-specific authorization-slice local proof

The Home cold summary path now calls the lightweight slice with exactly the
sales and finance dashboard feature codes. The slice batches exact-user scope
rows only before the Prisma query begins, then reuses the returned request-local
scope snapshot for feature, Home scope, and sales-progress authorization. The
existing full AuthContext remains unchanged for bootstrap/profile/policy and
other consumers.

Exact local proof on the final seven-file fingerprint passed:

- Focused AuthContext, Feature and Home: 3 suites / 88 tests. New regressions
  cover cross-principal row mapping, missing-user deny, pending-array detach,
  query failure/recovery, 5,000-request overflow fallback, no
  profile/policy/Redis/full-feature hydration, two-feature assignment batching,
  inactive/missing features, active-only super-admin bypass, and end-to-end
  passage of batched principal snapshots through the real feature resolver
  without a secondary user query.
- Affected auth/session/JWT/bootstrap/realtime, feature guard/controller,
  policy, Home DTO/controller/service and Sales Report scope resolver:
  13 suites / 251 tests.
- Full Nest: 90 suites / 973 tests; Nest build passed.
- Existing Flutter auth bootstrap/session/device/access-refresh/realtime and
  Home legacy/daily parser, cache, details, dashboard, selected-SA, avatar and
  shell consumers: 88 tests; `flutter analyze --no-pub` found no issue.
- Changed-file Prettier and `git diff --check` passed.

Independent correctness review found that the first subset implementation let
super admin bypass inactive or missing feature definitions, unlike the existing
full-map path, and identified the missing real FeatureService handoff proof.
Both findings were corrected and the post-fix focused, affected and full gates
above passed.

No schema, migration, token, session, permission, cache-key, event, rate-limit,
API or Flutter production contract changes. Remaining gates are PR/CI/lifecycle,
exact-SHA staging deployment, the unchanged fixed cold load profile, selected-SA
isolation and mandatory synthetic cleanup.

### Staging QA attempt 7 and cross-principal feature batching

PR #59 deployed successfully at exact staging SHA
`c92bef8f5b1ce376dac113b6bb8104b10a4e61b4` through run `30487118598`.
Smoke passed auth/bootstrap/scopes and legacy/daily 1/7/30/90-day contract,
ordering, freshness and parity. Synthetic run `ops31slice-20260730-0304`
returned 2,000/2,000 HTTP 200 with 100% contract/parity and zero
429/5xx/timeout, but latency regressed. Client p50/p95/p99/max were
`334.25/3030/4100/4150 ms`; every range failed the p95 and p99 gates.

Sixty cold synthetic Home loads plus smoke measured
`2483/2945/2991.4/3043 ms` at p50/p95/p99/max, while 59 daily extensions were
`148/251.2/260.26/262 ms`. Lightweight context itself was
`1643/1855 ms` at p50/p95; scope resolution was `471/814 ms`, sales progress
`240/439 ms`, and metrics `180/343 ms`. API CPU peaked at 139.19%, PostgreSQL
at 87.60%, and connections at 17/100 with five active and zero waiting. Redis
eviction/blocked and all restart counts remained zero.

The two-millisecond scope window produced only 14 multi-caller batches covering
31 callers, with two to four principals per batch. The inferred scope query
count remained 44. More importantly, every principal resumed separately after
that read and issued its own active-feature and node-assignment resolution,
creating another pair of PostgreSQL queries per cold caller. The partial batch
therefore synchronized a large cold wave without eliminating enough database
work, and the resulting contention also delayed downstream scope, progress and
metric reads.

Cleanup revoked exactly 60 users and sessions, deleted exactly 60 users, and a
separate idempotent verification proved zero remaining users, tagged grants,
email codes and known references. Server/local tokens and the k6 process were
absent; containers stayed healthy with zero restart. Selected-SA proof was not
run because latency failed.

The next bounded fix keeps the same no-TTL, pre-query-only security boundary
but closes the entire feature/scope slice as one cross-principal batch. A
20-millisecond cold-miss window is detached before the first database query.
One exact-user scope read is followed by one active-feature lookup, one shared
organization-tree load and a union node-assignment lookup for all principals in
that detached batch. The normal Home batch uses one assignment query; unusually
large target sets are split into bounded chunks. Each caller still receives
only its own scope row and requested feature map; missing users deny, any
scope/feature query failure rejects only that batch, and overflow uses the
existing independent path.
There is no post-query sharing or migration, so old and new runtimes remain
database-compatible under the expand/contract policy.

### Cross-principal feature/scope batch local proof

The bounded patch now groups the exact-user scope read and feature resolution in
one detached 20-millisecond pre-query batch. Duplicate principals are resolved
once, feature codes are unioned for shared queries, and each caller receives
only its own scope row and requested feature subset. The batched feature
resolver performs one active-definition lookup and reuses the shared
organization tree load. Context resolution and union node-assignment queries
are both capped at 250 items per chunk, preventing a 5,000-caller burst from
creating unbounded concurrent context work or one oversized Prisma `OR`. Super
admin contexts never contribute assignment targets, so an all-super-admin batch
keeps active-only access even if the assignment store is unavailable. Missing
users deny, scope or feature failures reject the detached batch, and overflow
retains the independent path. Batch start/success/failure and overflow branches
now log counts, duration and sanitized errors without identity or credential
payloads. There is still no TTL, Redis, post-query sharing, schema, migration,
API, permission, token, session, event, rate-limit, or Flutter production
change.

The first independent correctness review blocked publication on the
id-bearing super-admin failure coupling, an unbounded union-assignment query,
missing failure diagnostics and stale proof. The security review independently
confirmed principal isolation and parameterization, closed revocation and
shared-object concerns as non-actionable, and kept only the same bounded-batch
availability risk. The patch now closes those actionable findings with:

- an id-bearing super-admin regression proving active-only access without an
  assignment query;
- a 2,001-principal/target regression proving context concurrency and every
  assignment-query `OR` stay at or below 250 while all access maps remain exact;
- a two-principal failure/recovery regression proving one sanitized batch error
  log with no email or token content;
- duplicate-principal, mixed-subset, missing-user, detach, overflow and real
  FeatureService handoff regressions retained unchanged.

The post-finding focused gate passes 3 suites / 92 tests, Nest build, changed-
file Prettier and `git diff --check`. Earlier affected/full Nest and Flutter
results predate this review patch and are intentionally stale. The final
publication fingerprint must receive a second independent correctness/security
read and fresh focused, 13-suite affected, full Nest/build, protected Flutter,
analyze, Prettier and diff proof before commit. Exact results belong in the PR
and Linear proof attached to that unchanged commit so this plan does not create
another post-proof fingerprint change.

### Resume checkpoint after flat organization cache

PR #62 is merged into staging at
`cccb5ad2fcb53855161fc30bc863510a754b1cce`. Its final fingerprint passed 3
focused suites / 99 tests, 13 affected suites / 260 tests, 90 full Nest suites /
982 tests, Nest build, 114 protected Flutter tests, Flutter analyze, Prettier
and diff checks. The exact-SHA staging deploy and contract/parity smoke passed.

The fixed 250-VU/2,000-request run returned 2,000 HTTP 200 responses with 100%
contract/parity and no 429, timeout or 5xx, but client latency still failed at
p50/p95/p99/max `221.49/3100/4860/5240 ms`. Sanitized server stages isolated
the remaining cold work: context `306/458/518/518 ms`, scope
`373/784/833/833 ms`, sales progress `129/224/251/251 ms`, metrics
`65/124/147/147 ms`, and total `850/1471/1567/1567 ms`. Selected-SA QA was not
run after the latency failure. All 60 synthetic users and sessions were revoked
and deleted, zero tagged/email/reference rows remained, and temporary tokens
and k6 processes were absent.

The next task checkpoint is branch
`codex/ops-31-home-scope-consumer-access` from that exact staging SHA. The
bounded fix adds `ADMIN_SALES_REPORTS` to the existing Home authorization slice
and makes Sales Reports consume the exact pre-resolved feature decision and
scope snapshot before considering legacy fallback queries. Explicit false
still checks the managed job-role contract from the same snapshot; consumers
without an auth context retain the old FeatureService and user-query fallback.
No schema, migration, permission, API, cache, event, rate-limit or Flutter
production contract changes. Local proof, independent review, PR/CI/lifecycle,
exact-SHA deploy, the unchanged load gate, selected-SA isolation and mandatory
cleanup remain required.

### Staging public-ingress isolation after PR #63

At the exact deployed SHA `144e6ac20d4ae37961d24bd73593e1d3ab45a767`, the
staging host retained the dedicated `cloudflared-opshub-staging` service,
loopback origin `http://127.0.0.1:8090`, four HA connections, zero restarts,
and the unrelated Cloudflare connector was not touched. A same-host public
`/api/health` burst of 250 concurrent requests was used only to isolate the
transport path; it produced 120 HTTP 200 and 130 intentional principal-limit
429 responses. Successful latency was `923/938/940/957 ms` p50/p95/p99/max.

A transient, rollback-ready connector was started with a fixed metrics port
and `--proxy-keepalive-connections 300`. The main connector was stopped only
after the probe reported four HA connections. The probe counter proved traffic
distribution: `cloudflared_tunnel_total_requests` increased from `0` to `252`
(one health check plus the 250-request burst and one verification request),
with zero tunnel request errors. The same 250-request burst through the probe
returned 119 HTTP 200 and 131 intentional 429 responses; successful latency
was `743/770/773/788 ms` p50/p95/p99/max. The main connector was restarted,
verified at four HA connections, and the transient probe stopped with no
listener or persistent unit remaining.

This isolates a measurable public-ingress improvement without changing the
origin protocol, Caddy trust boundary, rate-limit policy, database schema or
runtime API. The durable staging installer change pins the same 300-connection
origin pool and binds metrics to loopback `127.0.0.1:20242`; the official Home
fixed profile, selected-SA proof and queue-before-Nest comparison remain
release gates on the resulting exact SHA.
