# AUTH-004 Validation

## Required Proof

| Layer | Proof |
| --- | --- |
| NestJS unit | Valid JWT users split buckets; same user shares a bucket; clientId/deviceId split non-JWT buckets; public auth email hashes split buckets; IP is last-resort fallback |
| NestJS build | Dependency injection and TypeScript compilation pass |
| Flutter | Not affected; backend 429 copy remains compatible with existing client handling |
| Release | `git diff --check` and exact diff review before deployment |

## Evidence

- 2026-07-01: focused `UserAwareThrottlerGuard` Jest suite passed 8 tests,
  including JWT user tracking, client identifier tracking, public-auth email
  hash tracking, and last-resort IP fallback.
- 2026-07-01: full backend Jest suite passed 46 suites and 398 tests.
- 2026-07-01: NestJS build passed.
- 2026-07-01: focused ESLint passed for the new guard/spec and changed module
  wiring.
- 2026-07-01: `git diff --check` passed.

## Remaining Runtime Proof

- Confirm production request logs stop returning shared-proxy 429 responses
  after deployment with more than 20 active payment monitor clients.
