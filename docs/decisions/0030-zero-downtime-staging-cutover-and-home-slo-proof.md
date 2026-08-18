# ADR-0030: Blue/green cutover contract and Home SLO proof boundary

Status: Proposed by OPS-200 for staging design/proof review; operational
approval is required before implementation and production remains release-gated.

Date: 2026-08-18

## Context

The current staging workflow runs one Docker Compose application plane and
stops/removes `api`, `realtime` and `caddy` before recreating them. A healthy
post-deploy check proves recovery, but it cannot prove zero downtime. HTTP and
WebSocket traffic also have different connection-drain requirements. The
existing Home load runbook already defines a read-only authenticated staging
profile, fixed parity checks and cleanup of exactly 60 synthetic users, but a
short load hold is not a rolling 30-day SLO proof.

## Decision

1. The target cutover topology is blue/green for the application plane behind a
   stable Caddy edge. PostgreSQL and Redis remain shared, stable dependencies;
   Caddy is reloaded atomically and is never stopped as part of the traffic
   switch. Each color has an isolated Compose project/network identity and a
   versioned release directory. The inactive color is retained until the
   observation and rollback window closes.
2. Both colors must serve the same expand/contract database contract. A
   destructive or one-way migration, an unverified background job change, or a
   schema write that the previous color cannot understand blocks the switch.
   Migration proof runs before traffic switch and is separately reversible or
   explicitly forward-only with a documented runtime rollback boundary.
3. HTTP switches only after the candidate color passes container health,
   direct-origin `/health`, authenticated `/auth/me` and `/auth/bootstrap`,
   representative Home 1/7/30/90 parity, app-version identity and sanitized
   error/latency gates. WebSocket upgrade tickets for new connections route to
   the candidate after the switch; existing connections remain on the old color
   until a bounded drain timeout of 120 seconds, after which the switch stops if
   active sessions remain unexpectedly high.
4. Rollback is an atomic Caddy upstream reload plus restoration of the previous
   release pointer. The old color and its image digests remain available until
   health/version, error-rate, latency, database, Redis and WebSocket drain
   checks pass for the approved observation window. Runtime rollback never
   attempts an unsafe database downgrade.
5. OPS-78 staging load proof uses the existing
   `deploy/staging/load-proof-runbook.md`: official k6 checksum, explicit
   approval, 60 least-privilege users, read-only Home/realtime traffic, fixed
   parity and SLO thresholds, sanitized telemetry and mandatory `verify-empty`
   cleanup. It proves the stated staging envelope only; rolling 30-day SLO,
   RPO 24 hours and RTO 4 hours remain separate production gates.
6. A release window is locked before any traffic mutation. The window records
   exact Git SHA, image digests, migration state, current/previous release
   pointers, approver, operator, start/end UTC, monitoring owner and rollback
   deadline. Any unexpected write, restart, 429/5xx/timeout, parity mismatch,
   resource threshold breach, ticket/upgrade failure or cleanup uncertainty is
   a fail-closed stop.

## Consequences

- The existing single-plane workflow must not be labeled zero-downtime and is
  retained as a recovery/deploy path until the blue/green implementation is
  independently proven.
- Caddy reload, color-specific Compose identity, connection drain and
  expand/contract migration support become explicit implementation contracts.
- Staging load proof is operationally controlled and produces sanitized evidence;
  raw tokens, logs, k6 output and snapshots stay outside Git.
- Production promotion remains blocked until the implementation, rollback and
  release-window evidence satisfy the production gates.

## Validation impact

- OPS-200 owns this authority contract. Later OPS-78 slices must link the exact
  implementation SHA, workflow run, image digests, health/version evidence,
  drain counters, Home parity/SLO report and cleanup proof.
- No runtime, API, DTO, permission, data or deployment behavior changes are
  made by this ADR.
