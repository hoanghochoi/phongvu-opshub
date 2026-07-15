# AUTH-004 User-aware API Rate Limiting

## Status

implemented

## Risk Reason

This is high-risk maintenance because it changes the global API throttling
identity, verifies JWT claims before authentication guards run, and changes the
fallback behavior behind the production reverse proxy.

## Problem

The NestJS throttler resolved a verified JWT user tracker but still applied a
second named `ip` bucket to every request. Staff behind the same showroom or
corporate NAT therefore shared the 120-request-per-minute IP ceiling even when
each user remained well below the principal limit. Production evidence on
2026-07-15 showed healthy API/DB resources while HTTP 429 accounted for about
65% of requests; `/home/summary` alone returned 798 throttles in a 30-minute
window.

## Acceptance Criteria

- A valid signed JWT uses
  `principal:user:<userId>:ip:<sha256(trustedIp)>` as the throttling tracker;
  Nest adds the method and endpoint to the effective storage key.
- The global throttler config contains only the `principal` bucket; signed-in
  requests do not also consume an independent IP bucket.
- Endpoint-specific `@Throttle` overrides use only `principal` limits.
- Different users behind the same proxy receive independent per-endpoint
  throttling buckets.
- Multiple valid sessions for the same user share that user's bucket.
- Caller-supplied client or device identifiers are not trusted as throttling
  principals because an attacker could rotate them.
- Public auth requests use
  `principal:email:<sha256(normalizedEmail)>` when an email is available.
- Requests without a verified user or email use
  `principal:ip:<sha256(trustedIp)>`. The trusted IP is part of the signed-in
  composite principal or the anonymous fallback, never a second simultaneous
  limiter.
- The API trusts only the single Caddy hop when resolving the fallback IP.
- Raw IP addresses never appear in throttler storage keys or rate-limit logs.
- HTTP 429 responses use Vietnamese, action-oriented copy instead of exposing
  `ThrottlerException`, and include a standard `Retry-After` header.
- Existing route-specific quotas for auth, upload, feedback, Payment Monitor,
  VietQR and realtime tickets remain unchanged.

## Accepted Residual Risk

Anonymous callers can rotate email and signed-in users can change their source
IP to receive a new principal bucket. Đại Ca explicitly accepts that risk to
avoid blocking unrelated staff behind one NAT. No global IP bucket may be added
implicitly; changing this boundary requires a new decision record.

## Verification

- Passive production baseline, 2026-07-15 14:26-14:56 Vietnam time: API about
  5.25% CPU, PostgreSQL about 0.34% CPU, all OpsHub containers healthy; 8,814 of
  13,416 requests returned HTTP 429, including 798 of 2,115
  `GET /home/summary` requests.
- Source audit: no named `ip` throttler remains under `backend-nest/src`.
- Focused Jest: `user-aware-throttler.guard.spec.ts` passed 14/14.
- Full NestJS Jest: 69 suites and 676 tests passed.
- `npm run build` passed.

The evidence above is the pre-release local baseline. Composite user+IP
semantics and shared-NAT behavior remain release gates in
`validation.md`; do not treat this section as staging proof.

## Rollback

Revert the composite-principal change as one application release if it causes a
runtime incident. Do not silently restore a global IP bucket: that would
contradict decision 0011 and reintroduce the shared-NAT outage mode. Keep JWT
verification, hashed identifiers, single-hop `trust proxy`, endpoint-specific
quotas, `Retry-After` and Vietnamese 429 copy intact.
