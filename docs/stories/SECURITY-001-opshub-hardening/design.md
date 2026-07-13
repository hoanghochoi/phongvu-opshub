# SECURITY-001 Design

## Trust boundaries

1. Cloudflare/Caddy receive public HTTP(S) traffic.
2. NestJS is the source of truth for user, feature, organization, session, and
   media authorization.
3. Redis carries short-lived authentication tickets and sanitized event
   envelopes; it is not an authorization source by itself.
4. Go realtime consumes tickets, resolves the server-provided audience, and
   owns connection backpressure.
5. Flutter receives only short-lived media URLs and one-use WebSocket tickets.
6. Persistent upload storage is private. Help assets are the only public media
   namespace.

## WebSocket ticket contract

- NestJS authenticates the normal bearer JWT and validates the current
  UserPlatformSession.
- POST /auth/realtime-ticket creates 32 random bytes, stores only the SHA-256
  keyed Redis record for 45 seconds, and returns the raw ticket once.
- The record is versioned and contains sanitized user/session/scope claims.
- Go consumes the record atomically. A ticket cannot be replayed.
- store_id from a query string is never trusted to widen the ticket scope.
- Legacy access_token support is an explicit, time-bounded compatibility flag;
  it is not the default end state.
- Logout, password reset, session replacement, or user lock publishes a
  revocation event so matching live connections are closed.

## Private media contract

- New media use opaque ids/storage keys and are stored outside a public
  file-server namespace.
- Business records store internal media references, not permanent public URLs.
- Authorized warranty/profile/feedback responses receive short-lived signed
  media URLs only after record-scope authorization.
- A media fetch verifies signature, expiry, object state, and safe path before
  streaming with no-store/nosniff headers.
- Existing URLs are dual-read through an explicit backfill/legacy resolver.
- Help content remains public in a separate namespace.
- Closing the Caddy public upload route and purging edge cache are manual
  cutover steps after client/version telemetry proves compatibility.

## Logging contract

- Never log bearer tokens, WebSocket tickets, secrets, raw query strings, raw
  media URLs, or full sensitive payloads.
- Log user/store/client identifiers only when needed and prefer hashes/counts.
- Docker rotates logs. Success logs are sampled where high volume would hide
  failures.

## Compatibility

- Security migrations deploy server support first, then Flutter clients, then
  disable legacy paths after telemetry.
- The compatibility window has a named env flag and removal date; it cannot be
  left as an undocumented permanent bypass.
- User-visible errors are Vietnamese-first and action-oriented.
