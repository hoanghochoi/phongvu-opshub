# 0011 Composite Principal Rate Limit Without A Global IP Bucket

Date: 2026-07-15

## Status

accepted

## Context

OpsHub serves signed-in staff who often share one showroom or corporate NAT.
Applying both a user bucket and a global IP bucket made unrelated staff exhaust
the same limit even when every user stayed below the intended quota. The shared
IP bucket caused avoidable HTTP 429 responses and prevented Home from loading;
raising its quota would only hide the identity-model error.

The API still needs a deterministic principal for public auth calls, a trusted
client IP behind Cloudflare Tunnel and Caddy, and bounded endpoint-specific
quotas. Caller-provided device or client identifiers are not trusted because
they can be rotated.

## Decision

- The global NestJS throttler has one named bucket, `principal`, with the
  existing quota of 120 requests per 60 seconds. Existing auth, upload,
  feedback, Payment Monitor, VietQR and realtime-ticket quotas stay unchanged.
- A verified JWT request uses
  `principal:user:<userId>:ip:<sha256(trustedIp)>` as its tracker. NestJS adds
  the throttler name, HTTP method and endpoint to the final storage key.
- An anonymous request with an email uses
  `principal:email:<sha256(normalizedEmail)>`. An anonymous request without an
  email uses `principal:ip:<sha256(trustedIp)>`.
- Caddy accepts `CF-Connecting-IP` only from the trusted Cloudflare Tunnel hop,
  then rewrites forwarded client-IP headers before Nest trusts exactly one
  proxy hop. Raw IP addresses must not appear in throttler keys or rate-limit
  logs.
- There is deliberately no second global IP bucket, including a hidden limiter
  outside the named `principal` contract. HTTP 429 includes `Retry-After`; logs
  contain method, route and retry duration, not query strings or identifiers.

## Consequences

- Different users behind one NAT do not consume each other's global quota.
  The same verified user and trusted IP share a bucket across sessions, while a
  verified user who changes IP receives a new bucket.
- Anonymous callers can rotate normalized email values, and signed-in users can
  rotate IP addresses, to receive another bucket. This abuse and the resulting
  database/SMTP load are explicitly accepted residual risks. Reintroducing a
  global IP bucket requires a new decision and must not happen as an implicit
  protection.
- Per-endpoint quotas remain the primary bound for expensive or side-effecting
  routes. Monitoring must separate intentional rate-limit semantics tests from
  unexpected 429 responses during capacity tests.
- Validation covers same user/same IP sharing, same user/different IP splitting,
  different users/same NAT splitting, invalid or expired JWT fallback,
  hashed-email fallback, no raw IP leakage, `Retry-After`, and preservation of
  every endpoint-specific quota.
