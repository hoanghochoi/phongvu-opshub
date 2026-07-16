# AUTH-CONTEXT-001 — Shared auth context and Home scope performance

## Status

`staging_verified`; migration, cache-failure, two-replica and load/profile gates
passed. Production promotion and passive post-deploy observation remain.

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

## Rollback

Keep public compatibility routes and the old resolver/process-local-cache kill
switch. The additive column/functions/triggers are backward-compatible with the
previous application build; rollback the application first and investigate
before removing database objects.
