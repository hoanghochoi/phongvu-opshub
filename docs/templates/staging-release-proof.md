# OpsHub Staging Release Proof

Status: `not_run | passed | failed | blocked`

This template contains no execution evidence until every field is filled from
the actual run. Do not paste tokens, emails, raw IPs, secrets, full request URLs,
local paths or unsanitized logs.

## Release identity

- Test date/time and timezone:
- Operator:
- Branch and local SHA:
- `origin/staging` SHA:
- Deploy workflow URL/run id and conclusion:
- Staging `current` release SHA/symlink:
- Previous rollback release:
- Database migration in this batch: `none`

## Local gates

| Gate | Command/scope | Result | Evidence summary |
| --- | --- | --- | --- |
| Payment cooldown | focused Flutter tests | not_run | |
| Home TTL/realtime | focused Flutter tests | not_run | |
| Updater failure/SHA | focused Flutter tests | not_run | |
| Principal throttler | focused NestJS tests | not_run | |
| NestJS full | build + full Jest | not_run | |
| Flutter full | analyze + full tests | not_run | |
| Go realtime | test + vet | not_run | |
| Caddy/platform/workflows | validate/adapt + security/syntax checks | not_run | |
| Repository | exact diff review + `git diff --check` | not_run | |

## Deploy and route proof

- Automatic rollback trap armed:
- Side-effect flags false and SMTP absent:
- Direct-origin `/download/` -> 308 `Location: /download`:
- Direct-origin `/help/` -> 308 `Location: /help`:
- Canonical route content/no loop:
- Enforced CSP and security headers:
- Public Cloudflare Access/health/API/download smoke:
- `/ws/v2` authenticated upgrade:

## Capacity result

- k6 version and verified archive SHA-256:
- Run id (non-identifying):
- Verified COMPLETE Home end date:
- Ladder and 100-QPS hold duration:
- HTTP total/success rate/p95/p99:
- Unexpected 429/timeouts/5xx/dropped iterations:
- WS attempts/connect success/invalid envelopes:
- API/realtime/PostgreSQL/Redis peak metrics:
- Restart/OOM/DB waits/Redis eviction or blocked clients:
- Stop condition triggered:
- Capacity conclusion:

## Separate semantics and manual proof

- Target principal accepted then received 429:
- `Retry-After` present and valid:
- Control principal on same source IP remained 200:
- Manual Payment first refresh produced exactly one bypass request:
- Second manual refresh was deferred locally:
- Intentional 429 excluded from capacity totals:

## Windows staging N to N+1

- Installed staging build N:
- Published staging build N+1:
- Metadata URL host, package type, size and SHA match:
- Authenticode status/signer pin/timestamp:
- Defender workflow gate:
- Download, verify, Inno launch, close and relaunch result:
- Relaunched version/build:
- Separate production installation unaffected:
- Sanitized success/failure log evidence:

## Cleanup

- k6/WS stopped:
- Sessions revoked and token versions incremented:
- Synthetic users deleted / remaining count:
- Server token file removed:
- Workstation token/k6/raw-output files removed:
- Cleanup conclusion:

## Promotion boundary

- Overall staging conclusion: `ready | not_ready`
- Blocking failures/remaining uncertainty:
- Rolling 30-day SLO evidence: `not provided by this 15-minute proof`
- Engineering error-budget remaining (promotion stops below 25%):
- RPO 24h proof status:
- RTO 4h proof status:
- Main/production action taken: `none`
