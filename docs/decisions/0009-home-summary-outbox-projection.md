# 0009 Home Summary Outbox Projection

Date: 2026-07-14

## Status

accepted

## Context

`GET /home/summary` previously refreshed its fact tables synchronously before
reading them. A request covering several days could therefore perform thousands
of source-row upserts before returning. That design couples dashboard latency to
the amount of ERP, sales-report, MAP, and eFAST data and cannot support the
target of 10,000 accounts and 2,000 concurrent WebSocket connections.

OpsHub also needs a durable realtime foundation that can later carry chat and
meeting control-plane events. Redis Pub/Sub alone is not durable, and rebuilding
Home inside a business write transaction would lengthen the source write path.

## Decision

- Source changes dirty `HomeSummaryProjectionQueue` in the same PostgreSQL
  transaction. `DomainOutboxEvent` retains durable source signals and committed
  outbound events. PostgreSQL `NOTIFY` is only a wake-up hint; a worker still
  polls the durable queue every second.
- `HomeSummaryProjectionQueue` coalesces work by summary date and projection
  kind (`SALES` or `FINANCE`). Lease tokens, lease expiry, dirty generation,
  and `FOR UPDATE SKIP LOCKED` prevent concurrent rebuilds while preserving one
  follow-up job when a source commit arrives during an active rebuild.
- MAP polling uses a bounded TTL/LRU fingerprint cache as a read/write shedding
  layer. Cache misses still use the database idempotency contract, and new
  transactions are committed before payment notifications are published.
- MAP transaction updates that do not change Home finance inputs are ignored by
  the projection trigger. API clients apply per-endpoint cooldown after HTTP
  429 and the server emits/obeys standard `Retry-After` hints.
- The worker rebuilds kind-specific additive daily aggregates for `GLOBAL`,
  `STORE`, and `USER_STORE` grains outside source transactions. Extended SALES
  counters are stored as internal additive JSON snapshot metrics because they
  are replaced and read as one unit, never filtered as source facts. Rates are
  calculated when reading rather than persisted; revenue and projection
  versions remain 64-bit values.
- The projection transaction atomically replaces one date/kind and appends the
  outbound event before commit. The publisher leases that outbox row only after
  commit. `HOME_SUMMARY_UPDATED` contains only affected dates and a globally
  monotonic projection version; clients re-read the authenticated HTTP API for
  KPI data and compare versions per affected date.
- `GET /home/summary` never rebuilds synchronously when projection mode is on.
  It returns the latest complete projection and a `freshness` object. A complete
  result older than 15 seconds is marked stale; absence of any complete result
  returns HTTP 503 with Vietnamese, action-oriented copy.
- The legacy fact refresh/read path remains available behind a feature flag for
  one release. Redis is a low-latency signal path, not a source of truth.

## Consequences

- Internal commits can appear on an open Home screen within seven seconds p95
  without increasing business transaction latency.
- Source-to-screen freshness still includes external polling cadence: MAP is
  expected within ten seconds and ERP/eFAST within seventy seconds during their
  fast-sync windows.
- Outbox backlog, queue delay, projection duration, projection lag, and publish
  failures become operational signals that must be logged and monitored.
- Cache hits, DB no-op rows, provider backoff and client endpoint cooldown are
  logged as bounded operational counters rather than per-row payloads.
- Reconciliation and checkpointed backfill are required because legacy rows
  may predate the outbox.
- A missed Redis message or disconnected socket is safe: reconnect/app-resume
  triggers one HTTP refresh and PostgreSQL retains the durable state.
- Phase 2 must consolidate existing feature sockets and move schedulers into a
  dedicated worker process before the 2,000-socket load target is treated as
  production-ready. Chat and meeting media remain separate later initiatives.

## Validation Impact

- Validate Prisma schema plus migration up/down behavior and idempotent backfill.
- Prove KPI parity for 1/7/30/90-day ranges and every supported scope.
- Test missed `NOTIFY`, worker restart, duplicate/out-of-order events, Redis
  reconnect, stale/no-projection responses, and backfill resume.
- Measure source commit to projection completion, projection completion to
  event, and event to Home repaint separately.
- Phase 1 gates are projection p95 at most five seconds, API p95 at most 500 ms,
  a 5,000-row burst without job storms, and the standard NestJS, Go, Flutter,
  Prisma, and repository validation suites.
