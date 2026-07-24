# AUTH-CONTEXT-001 — Shared auth context and Home scope performance

## Status

`hotfix_local_verified`; migration, cache-failure, two-replica and load/profile
gates passed earlier, but the first production promotion was rolled back after
an app/bootstrap identity-contract mismatch. The hotfix now requires a fresh
staging upgrade smoke and passive observation before production promotion.

## Problem

Startup, Home scope loading and realtime ticket issuance repeatedly hydrated
the same user, policy, feature and organization data. Policy rules could be
loaded per policy and organization checks could scan the whole tree, raising
PostgreSQL query count and Node CPU across replicas.

## Accepted behavior

- `/auth/bootstrap` is the canonical startup snapshot and performs ETag
  preflight before resolver work.
- Compatibility routes keep their public contracts but project from one
  `AuthContextService`.
- Context and Home scope caches are keyed by `userId + tokenVersion +
  sessionVersion + accessVersion`; entries from a different tuple are never
  reused.
- PostgreSQL triggers increment `User.accessVersion` in the same transaction as
  permission/topology mutations. `ACCESS_CHANGED` is published only after
  commit.
- Feature/policy rules are batch-loaded. Organization data uses bounded tree or
  subtree reads instead of a full per-check query.
- Realtime ticket remains a separate short-lived mutation and never logs its
  secret.

## Local proof

- Prisma migration SQL executed in a temporary PostgreSQL schema, including
  direct-user, subtree, broad-rule, platform-session and rollback checks; the
  transaction was rolled back.
- Prisma generate/validate and Nest build passed.
- Nest full Jest passed: 73 suites, 718 tests.
- Flutter analyze passed; Flutter full test passed: 536 tests, 3 skipped.
- Go test passed: 62 tests.
- `git diff --check` passed.

## Staging release proof

- Exact staging head `ad7efa03` deployed successfully in workflow
  `29539833066`. Migration, release symlink, public manifest, API health and
  compatibility smokes passed.
- Two-VU rate-limit semantics accepted 120 target and 42 control requests,
  intentionally throttled 61 target requests, and produced zero control
  failures, missing `Retry-After`, unexpected statuses, transport errors or
  dropped iterations; p95 was 106 ms.
- The fixed `25 -> 50 -> 100 QPS` ladder completed 121,628 HTTP requests with
  100% success, zero 5xx/transport/unexpected-429 responses and zero dropped
  iterations. Aggregate p95/p99 were 85.976/176.193 ms; the 100-QPS Home hold
  p95/p99 were 77.582/106.854 ms. All 60 WebSocket tickets connected and
  completed.
- Final recovery sample was API CPU 0.22%/122 MiB and PostgreSQL CPU
  3.11%/80.51 MiB, with 8 database connections, 1 active, no active wait,
  deadlock, Redis eviction, container restart or OOM. Node profiling found no
  dominant application-JavaScript hotspot.
- `pg_stat_statements` showed individually cheap top queries but excessive
  frequency as the remaining optimization target: User lookup 134,432 calls at
  0.0453 ms mean, platform session 121,637 at 0.0285 ms, Store 258,062 at
  0.0052 ms and OrganizationNode 44,455 at 0.0251 ms. Staging-only profiling
  settings were reset after capture.
- Two API replicas shared auth/scope Redis entries, deduplicated concurrent
  misses through a lease, rejected the invalidated old version and received
  public traffic evenly (21/21). Caddy dynamically discovered both replicas.
- During a controlled Redis outage, bootstrap and scopes both returned `200`,
  bootstrap ETag changed after `accessVersion` advanced, PostgreSQL fallback
  hydrated locally, and Redis/API recovered healthy. The outage exposed and
  fixed both long ioredis retries and an uncaught lease-acquisition failure.
- All 60 synthetic users and sessions were revoked, exactly 60 records were
  deleted, verification found zero tagged users/references, and server/local
  token, k6, profile and temporary script artifacts were removed.

## Promotion criteria

HTTP success is at least 99.9%, p95 at most 500 ms and p99 at most one second;
unexpected 429/5xx/timeouts are zero, no container restarts/OOM occur, database
headroom remains at least 80%, Redis has no evictions/blocked clients, and CPU
does not remain above 85% for two consecutive minutes.

## Production incident and access-bootstrap hotfix — 2026-07-17

- Production build `100127` loaded a pre-v2 saved session with zero persisted
  feature/policy entries, then called the canonical `/auth/bootstrap` route.
  The API returned `200`, but its `user` projection came from
  `AuthService.getUserData()` and omitted `id`/`email`. Flutter required a
  non-empty email and converted the otherwise successful response into a local
  contract exception, while legacy fallback was restricted to `404/501`.
- The application was rolled back first to `1b174205`; compatibility routes
  restored access hydration without reverting the additive database work.
- The server hotfix makes bootstrap self-contained by projecting authenticated
  `id` and normalized `email` after profile fields. Flutter also accepts a
  missing bootstrap email only from the current saved-session identity and
  rejects a conflicting response identity.
- A typed, sanitized contract failure records reason, HTTP status, schema,
  response size/duration, field-presence flags and top-level keys without
  logging response bodies or tokens. Contract failure falls back once to the
  compatibility routes only when no usable snapshot exists; network/5xx keeps
  a last-known-good snapshot stale instead of multiplying backend load.
- A `304` can mark access fresh only when a usable access snapshot exists. If
  not, the client retries once without `If-None-Match`; a second invalid `304`
  remains fail-closed.
- One shared JSON contract fixture is consumed by Nest and Flutter tests.
  Regression proof covers pre-v2 session upgrade, server-v1 missing-email
  compatibility, identity mismatch, malformed JSON diagnostics, `401`,
  `404/501`, cached `503`, unconditional `304` retry, late logout response and
  the AppShell fail-closed/retry surface.

## Hotfix local proof

- Flutter targeted auth/AppShell proof passed 36 tests.
- Flutter analyze passed; full Flutter passed 545 tests with 3 skips.
- Nest targeted bootstrap/controller proof passed 21 tests; Nest build passed;
  full Nest passed 73 suites and 720 tests.
- Go test passed 62 tests; Go vet and `git diff --check` passed.
- Windows debug build and Android `staging` debug build passed.
- Remaining release proof: deploy the exact candidate to staging, upgrade a
  real pre-v2/`100127` saved session, confirm bootstrap success and expected
  access counts in client/server logs, observe 30–60 minutes, then promote with
  `1b174205` kept as the application rollback target.

## Rollback

Keep public compatibility routes and the old resolver/process-local-cache kill
switch. The additive column/functions/triggers are backward-compatible with the
previous application build; rollback the application first and investigate
before removing database objects.

## Production startup deadlock follow-up — 2026-07-24

- A later OPS-9 production candidate exposed a startup interaction with the
  access-version trigger: parallel default `JobRoleDefinition` inserts each
  attempted the broad active-user version bump and PostgreSQL detected
  `40P01`. The deployment guard restored the previous healthy application;
  additive migrations remained applied.
- The application hotfix serializes all access-sensitive default catalog
  upserts inside one API process. It does not weaken atomic access invalidation,
  hide seed failures or change auth/bootstrap contracts.
- Local proof PASS: maximum startup catalog-write concurrency `1`; shared
  user/feature/policy/auth tests 126/126; full Nest 870/870; protected Flutter
  auth and affected OPS-9 consumers 147/147; Nest build and Flutter analyze
  clean. Staging upgrade/startup observation remains required.
