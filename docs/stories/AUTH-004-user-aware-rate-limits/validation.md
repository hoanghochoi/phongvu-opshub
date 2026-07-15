# AUTH-004 Validation

## Required Proof

| Layer | Proof |
| --- | --- |
| NestJS unit | Same user + same trusted IP shares a bucket; same user + different IP splits; different users behind one NAT split; anonymous email is normalized and hashed; invalid/expired JWT falls through safely; anonymous no-email uses hashed trusted IP; no raw IP leaks into a tracker or rate-limit log |
| NestJS contract | Only global `principal` 120/minute remains; Nest method/endpoint isolation works; auth/upload/feedback/Payment Monitor/VietQR/realtime-ticket quotas are unchanged; HTTP 429 has Vietnamese copy and `Retry-After` |
| NestJS build | Dependency injection and TypeScript compilation pass |
| Flutter | Not affected; backend 429 copy remains compatible with existing client handling |
| Release | Full Nest tests/build, `git diff --check`, exact diff review, then staging semantics proof before promotion |

## Evidence

- 2026-07-01: focused `UserAwareThrottlerGuard` Jest suite passed 8 tests,
  including JWT user tracking, client identifier tracking, public-auth email
  hash tracking, and last-resort IP fallback.
- 2026-07-01: full backend Jest suite passed 46 suites and 398 tests.
- 2026-07-01: NestJS build passed.
- 2026-07-01: focused ESLint passed for the new guard/spec and changed module
  wiring.
- 2026-07-01: `git diff --check` passed.
- 2026-07-15 passive production baseline before the composite tracker: API and
  database had headroom while 8,814/13,416 requests returned 429 in 30 minutes,
  including 798/2,115 `GET /home/summary` requests. This diagnoses the former
  shared-IP behavior; it does not prove the new staging contract.

## Required Staging Proof

- Use 60 deterministic staging principals from one source IP. During the
  capacity run, every principal stays below 120/minute and unexpected 429 must
  remain zero.
- In a separate semantics run, drive one user above 120/minute using a safe
  read-only GET. It must receive 429 plus `Retry-After`, while a control user
  from the same source IP continues to receive 200. Intentional 429 responses
  are excluded from capacity SLO calculations.
- Inspect sanitized logs and throttler storage evidence to confirm there is no
  raw client IP and no hidden global IP bucket.
- Promotion remains blocked until these checks and cleanup of all synthetic
  users/sessions/tokens are complete.
