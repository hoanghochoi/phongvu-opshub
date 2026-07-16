# AUTH-CONTEXT-001 — Shared auth context and Home scope performance

## Status

`local_verified`; staging migration, multi-replica/cache-failure proof and load
profile are release gates.

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
- Nest full Jest passed: 73 suites, 717 tests.
- Flutter analyze passed; Flutter full test passed: 536 tests, 3 skipped.
- Go test passed: 62 tests.
- `git diff --check` passed.

## Staging release proof

- Deploy the exact commit and confirm migration, release symlink, image and
  disabled side-effect settings.
- Smoke bootstrap `200`/`304`, profile, Home 1/7/30/90-day ranges, scopes and
  one `/ws/v2` ticket/upgrade.
- Prove shared Redis cache across replicas, version invalidation and Redis
  outage fallback without cross-version reuse.
- Run the fixed `25 -> 50 -> 100 QPS` ladder with 60 synthetic users/sockets;
  capture Node CPU and PostgreSQL `pg_stat_statements`/query plans.
- Revoke/delete synthetic users and verify zero remaining records before a
  production promotion decision.

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
