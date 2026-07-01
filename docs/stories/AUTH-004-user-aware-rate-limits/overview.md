# AUTH-004 User-aware API Rate Limiting

## Status

implemented

## Risk Reason

This is high-risk maintenance because it changes the global API throttling
identity, verifies JWT claims before authentication guards run, and changes the
fallback behavior behind the production reverse proxy.

## Problem

The NestJS throttler used `req.ip` while the API runs behind Caddy. All signed-in
OpsHub clients could therefore share the proxy IP bucket. Payment monitor clients
poll every 10 seconds, so more than 20 active clients could exhaust the
120-request-per-minute limit for the same endpoint and cause a newly opened app
to receive HTTP 429 immediately.

## Acceptance Criteria

- A valid signed JWT uses its `sub` user id as the throttling tracker.
- Different users behind the same proxy receive independent per-endpoint
  throttling buckets.
- Multiple valid sessions for the same user share that user's bucket.
- Requests without a valid JWT use stable client identifiers first:
  `X-OpsHub-Client-Id`, `X-Client-Id`, `X-Device-Id`, `clientId`, or `deviceId`.
- Public auth requests without a client identifier use a normalized, hashed
  email bucket.
- The trusted client IP is only the last-resort bucket when no user/client/email
  identifier is available.
- The API trusts only the single Caddy hop when resolving the fallback IP.
- HTTP 429 responses use Vietnamese, action-oriented copy instead of exposing
  `ThrottlerException`.

## Rollback

Restore the default `ThrottlerGuard`, remove the exported `JwtModule`, and remove
the single-hop `trust proxy` setting. The client identifier and hashed-email
fallbacks are contained in the custom guard, so rollback removes them together.
The previous 120-request-per-minute configuration remains otherwise unchanged.
