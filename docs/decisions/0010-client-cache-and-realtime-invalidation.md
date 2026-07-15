# 0010 Client Cache And Realtime Invalidation

Date: 2026-07-15

## Status

accepted

## Context

Authenticated startup currently restores a partial user snapshot, then calls
profile, feature and policy endpoints separately. If feature resolution fails,
Flutter can finish initialization with an empty access map, so permission-aware
navigation disappears even though the session and last successful access state
were valid.

Several global providers also perform eager reads or own feature WebSockets.
Payment delivery metrics polls every minute, Home turns short realtime bursts
into repeated full reads, and Payment Monitor can start list work before its
screen is opened. This increases backend load and makes transient failures
visible as missing or blank UI.

## Decision

- Use a small application query cache with keyed in-flight deduplication,
  stale-while-revalidate, explicit freshness metadata and optional persistence.
- Persist only data classified safe for local snapshots. Sensitive operational
  rows remain memory-only. JWT remains in secure storage and never enters the
  query cache.
- Add one authenticated conditional bootstrap endpoint for profile, feature
  access and policy access. Flutter hydrates last-known-good access first and
  refreshes it in the background.
- Treat cached authorization as presentation state only. Every protected API
  remains server-authorized, so a stale visible menu cannot grant data access.
- Use route and foreground lifecycle as request eligibility. Inactive features
  retain snapshots but do not fetch, poll or retry.
- Home uses `HomeSummaryRepository.summaryFreshTtl` as its only freshness
  source, fixed at 60 seconds. Route activation before 60 seconds reuses cache;
  at or after 60 seconds it deduplicates one revalidation. A failed
  revalidation retains the original snapshot timestamp so a later activation
  can retry rather than treating stale data as newly fetched.
- Consolidate authenticated invalidation and low-latency feature signals onto
  `/ws/v2`. WebSocket messages are not the data source; they carry typed,
  audience-filtered invalidation/version data and clients re-read HTTP when a
  complete record is required.
- Keep all-scope policy selectors in a dedicated `policyCodes` namespace. They
  must never match organization, department, business, or store codes with the
  same text.
- Keep explicit `last updated`, stale/error state and manual retry in the UI.
  Cached content must never silently appear current.
- Keep legacy auth endpoints and `/ws` during rollout. New clients fallback to
  legacy auth fan-out only for an unsupported bootstrap endpoint, not for
  network or server errors.

## Consequences

- Saved-session startup normally needs one conditional bootstrap rather than
  three access calls, and navigation remains stable during temporary outages.
- Concurrent widgets sharing a query key cannot create duplicate requests.
- Most feature traffic becomes route-driven or event-driven; timer polling is a
  bounded recovery mechanism rather than the primary refresh strategy.
- Home has no timer polling. Its realtime event is the primary invalidation;
  reconnect and app resume each permit one forced network recovery read.
- A single authenticated socket reduces ticket issuance and connection count,
  but every new topic needs explicit audience and fail-closed tests.
- Access grant/revoke invalidation disconnects the affected socket after event
  delivery; otherwise ticket claims could remain valid until the socket closes.
- Cached operational data requires schema versioning, environment/user
  isolation, corruption handling, logout cleanup and sanitized logging.
- UI gains a small amount of persistent status copy, but existing content stays
  readable during background refresh and errors.

## Rejected Alternatives

- Fail closed by clearing menus whenever access refresh fails: repeats the
  reported user-visible failure and confuses availability with authorization.
- Cache every API response on disk: risks sensitive-data retention and creates
  invalidation bugs.
- Add another local database package immediately: unnecessary for the bounded
  safe snapshots in this phase and increases cross-platform migration risk.
- Keep one WebSocket and one timer per feature: preserves the connection and
  polling load this initiative is intended to remove.
- Put full business payloads in Redis/WebSocket events: duplicates HTTP source
  contracts and enlarges the sensitive realtime surface.

## Validation Impact

- Test cache TTL/dedupe/304/stale/backoff and user/environment isolation. Home
  specifically proves no HTTP at 59 seconds, exactly one revalidation at 60
  seconds, stale fallback with the original timestamp, and realtime invalidation
  taking precedence over TTL.
- Test bootstrap `200`, `304`, unsupported-server fallback, non-401 stale
  fallback and `401` session removal.
- Test route/background eligibility and one-shot resume refresh.
- Test every v2 topic for audience filtering, malformed payload rejection,
  duplicate/out-of-order handling and Redis-loss resync.
- Measure request counts for startup, Home bursts, metrics cadence and inactive
  Payment Monitor before accepting staging and production rollout.
