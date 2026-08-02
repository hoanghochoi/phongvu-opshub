# Staging Home And Realtime Release-Proof Runbook

This runbook is for the explicitly approved OpsHub staging release proof only.
It is not authorized for production. It exercises read-only authenticated HTTP
and `/ws/v2`; public/legacy sockets, Payment ready polling and write endpoints
stay disabled.

## Safety boundary

- Run the fixed Home HTTP proof only against the exact allowlisted base URL
  `https://opshub-staging.hoanghochoi.com/api` or the OPS-42 API-only ingress
  `https://api-opshub-staging.hoanghochoi.com/api`. Realtime and every other
  staging profile remain restricted to
  `wss://opshub-staging.hoanghochoi.com/ws/v2` and the original base URL. The
  scripts hard-fail for any other target, approval phrase, run id, user count,
  RPS or socket count.
- Use an official stable k6 binary on the workstation and record its exact
  version before the run. A package-manager installation is acceptable when
  it resolves to the official k6 release; otherwise download an archive to a
  temporary workstation directory and verify its SHA-256 against the checksum
  published with that exact release. Never copy the generator to the staging
  host.
- Record branch/SHA, workflow run, staging release symlink, container/image
  state and rollback target before creating users. Keep all raw tokens, k6 raw
  output and resource snapshots outside the repository and out of the report.
- Confirm the workflow forced ERP cache sync, ERP status sync, VietQR
  auto-reconcile, MAP global sync and Home ERP backfill to `false`, and removed
  all `SMTP_*` values. Stop immediately if any side effect is observed.
- The maintenance command selects a contiguous 90-day window whose Home
  projection is `COMPLETE` and has global aggregates. If it cannot find that
  data, stop; do not refresh or copy production data to satisfy the test.

## Prepare 60 least-privilege users

Before preparing any synthetic user for OPS-42, run the API-only health gate:

```text
BASE_URL=https://api-opshub-staging.hoanghochoi.com/api
TEST_RUN_ID=<unique-lowercase-run-id>
LOAD_APPROVAL=OPSHUB_STAGING_API_HEALTH_GATE_APPROVED
```

Run `scripts/load/opshub-staging-api-health-gate.js` with the persistent local
k6 binary. The profile sends exactly 100 concurrent requests, stays below the
120-request unauthenticated principal/IP minute bucket, requires the exact Nest
health response, zero unexpected status/429/5xx/timeout, p95 below 300 ms, p99
below one second and max below three seconds. Stop without creating users if
any threshold fails.

On `mementoamoris`, choose a unique lowercase run id of 3-32 characters. The
wrapper requires hostname, staging sentinels, exact public origin and the
maintenance flag, then creates exactly 60 `STAFF` users with prefix
`staging.load.<run-id>.`. Before creation it requires
`staging.staff@phongvu.vn` to match the sanitized store-only invariant: active
`STAFF`, completed and branch-locked profile, one store, no broader scalar
scope, no active organization assignment, and no direct feature or policy
grant. Synthetic users copy only the source store, profile-completion and branch
lock fields; organization assignments, broad feature rules and policy rules are
never cloned. The wrapper grants only the two Home section features required for
the proof (`HOME_DASHBOARD_SALES` and `HOME_DASHBOARD_FINANCE`) on the staging
source store's organization node chain, never in production. Existing enabled
node assignments are reused; existing disabled conflicts stop the run instead
of being overwritten. Newly created rows are tagged with the run id so cleanup
can prove zero remaining records. Any source-account drift stops the run before
the first user is created. The command never sends email.

```bash
RUN_ID=release-yyyymmdd-nnn
bash deploy/staging/manage-load-users.sh prepare "$RUN_ID" PREPARE_OPSHUB_STAGING_LOAD_USERS
```

The token manifest is written atomically outside the repo at
`/srv/opshub-staging/load-output/<run-id>.tokens.json` with mode `0600`. Copy it
to a temporary workstation directory through the approved SSH path, restrict
the local ACL to the current operator, and never print or paste its contents.
The manifest contains deterministic user order and the verified Home end date.

## Preflight and monitoring

- Smoke the API, authenticated `/auth/me`, `/auth/bootstrap`, Home 1/7/30/90
  day ranges, Home scopes and one `/ws/v2` ticket/upgrade before increasing
  load. Confirm no public or legacy socket is opened.
- Start sanitized observation of API/realtime logs, `docker stats`, PostgreSQL
  active/waiting connections and pool headroom, and Redis CPU, evictions and
  blocked clients. Capture one baseline before k6.
- Stop immediately for a write/side effect, container restart, OOM, database
  deadlock, Redis eviction/blocked client, unexpected 429 or cleanup-risk signal.
  Also stop after two consecutive one-minute windows with CPU above 85%, DB
  wait/pool headroom below 80%, or an HTTP/WS SLO breach.

### Synchronized public-ingress telemetry

The Caddy access logger `staging_home_load_telemetry` activates only for the
dedicated staging hostname and `GET /api/home/summary` when all three official
load headers are present. Caddy validates the telemetry nonce as exactly 64
lowercase hexadecimal characters and accepts only the fixed 1/7/30/90-day
range tags plus `legacy` or `daily_series`. It overwrites any caller-supplied
`X-Request-Id` with Caddy's request UUID before proxying to Nest. The nonce is a
per-run provenance value, not an authentication control; application auth and
API authentication remain mandatory.

Caddy deletes the complete request, response headers, TLS data and user field
before writing the log. It keeps only timestamp, status, byte counts, total
Caddy duration, total reverse-proxy handler duration, the selected upstream
attempt duration, retry count, the first four SHA-256 bytes of the nonce, the
validated range/variant tags and the Caddy UUID echoed by the existing
sanitized Nest `HttpRequest` entry. Normal staff traffic, the separate capacity
profile and production do not carry the nonce and therefore cannot match this
logger.

Generate a new cryptographically random 32-byte nonce for every fixed run,
store its 64-character lowercase hexadecimal form with the same protected
workstation ACL as the token manifest, and load it into `TELEMETRY_NONCE`
without putting the raw value in a command line, log, issue or report. Compute
the expected telemetry hash locally as the first eight lowercase hexadecimal
characters of `SHA-256(TELEMETRY_NONCE)`; this hash is safe to pass to the
analyzer. Delete the nonce file during mandatory cleanup.

Before the run, record the current line count and inode of
`/srv/opshub-staging/caddy/data/staging-home-load-telemetry.log`, the UTC start
time, and a Cloudflared metrics snapshot from `127.0.0.1:20242`. During the run,
sample at least these metrics often enough to observe the peak, not only the
start/end values:

- `cloudflared_tunnel_concurrent_requests_per_tunnel`;
- `cloudflared_tunnel_ha_connections`, request errors and response codes;
- QUIC latest/smoothed/min RTT, congestion window, closed connections and
  packet-too-big drops.

End this telemetry window immediately after the fixed 2,000-request profile
and before starting the capacity ladder. Fail the telemetry gate if the Caddy
log inode changed or the line count moved backwards. Copy only the new Caddy
lines and only sanitized API `HttpRequest` lines whose path is exactly
`/home/summary` from the matching UTC window to a protected temporary directory
outside the repository. Do not copy the whole API log window. Aggregate without
printing request ids:

```powershell
node scripts/load/analyze-home-ingress-telemetry.mjs `
  --caddy <temporary-caddy-ndjson> `
  --nest <temporary-api-log> `
  --telemetry-hash <expected-8-character-sha256-prefix> `
  --expected-count 2000 `
  --expected-per-group 250 `
  --output <temporary-sanitized-summary-json>
```

The analyzer exits nonzero unless it has exactly 2,000 unique correlated
Caddy/Nest `200/200` rows, zero malformed/duplicate/missing/status-mismatch
rows, zero proxy retries, no negative timing delta and exactly 250 rows in each
of the eight range/variant groups. Rows carrying another telemetry hash are
ignored and cannot affect the run. The summary separates Caddy total,
reverse-proxy total, selected upstream attempt, Nest and per-request timing
deltas overall and by group. The upstream-attempt metric includes that attempt's
response-body write and is not labeled as pure origin compute; reverse-proxy
total also includes selection/retry handling.

Compare these measurements with the same-window k6 client percentiles and
Cloudflared peak metrics to locate delay before Caddy without subtracting
independent percentiles as though they were correlated samples. Delete the raw
Caddy/Nest slices, nonce and any diagnostic output after the sanitized summary
has been reviewed. The later 100-QPS profile intentionally does not set
`TELEMETRY_NONCE` and opens a separate observation window.

## Capacity profile

Trước capacity ladder, chạy parity/load profile
`scripts/load/opshub-home-phase1-http-proof.js` với `BASE_URL`, `TEST_RUN_ID`,
`TOKENS_FILE`, `TARGET_VUS=250`, `TARGET_REQUESTS=2000` và approval tương ứng
staging hoặc loopback. Profile luân phiên response legacy và
`includeDailySeries=true` cho đủ 1/7/30/90 ngày. Nó fail nếu legacy vô tình có
`dailySeries`, series thiếu/thừa hoặc sai thứ tự ngày, field không phải số, hay
tổng bốn metric theo ngày lệch aggregate; đồng thời giữ SLO
p50/p95/p99/max `250/500/1000/3000 ms` riêng từng range.

The fixed 2,000-request envelope is executed as 1,000 matched pairs. Each pair
uses the same synthetic principal and date range, sends one legacy request and
one `includeDailySeries=true` request sequentially, and compares
`totalRevenue`, `totalOrders`, `reportedOrders`, and `totalReports`
across both responses. The run fails even when the opted-in series is internally
consistent if any protected aggregate differs from its matched legacy response.
Range and variant tags remain attached to both latency samples.
The fixed profile also requires the protected per-run `TELEMETRY_NONCE`
described above; no other load profile receives that value.

Run `scripts/load/opshub-staging-home-100qps.js` with the temporary k6 binary
and these exact environment values:

```text
BASE_URL=https://opshub-staging.hoanghochoi.com/api
WS_URL=wss://opshub-staging.hoanghochoi.com/ws/v2
TEST_RUN_ID=<run-id>
TOKENS_FILE=<absolute-temporary-token-manifest-path>
TARGET_RPS=100
TARGET_SOCKETS=60
PUBLIC_WS_ENABLED=0
LEGACY_WS_ENABLED=0
LOAD_APPROVAL=OPSHUB_STAGING_HOME_100QPS_APPROVED
```

The fixed ladder is smoke 1-5 users, 25 QPS for two minutes, 50 QPS for three
minutes, ramp to 100 QPS for three minutes, hold 100 QPS for 15 minutes, then
ramp down for two minutes. Token selection is deterministic round-robin. The
read mix is 70% Home summary (35% one day, 20% seven days, 10% 30 days, 5% 90
days), tất cả Home request trong capacity profile dùng
`includeDailySeries=true`; 10% Home scopes, 10% auth bootstrap và 10% auth me,
plus 60 `/ws/v2`
connections. Each synthetic user requests exactly one realtime ticket, opens at
most one socket after smoke, and holds that socket through the remaining fixed
HTTP ladder; the release profile does not reconnect or churn sockets.

Pass thresholds:

- HTTP success at least 99.9%; p95 at most 500 ms; p99 at most one second.
- The k6 profile enforces those HTTP latency limits on the aggregate HTTP
  stream and separately on Home summary ranges. It does not apply the same
  request-latency threshold to each ladder phase or the long-lived realtime
  scenario, whose ticket/upgrade path is measured by its success and hold
  counters instead of being mixed into a phase p99.
- Unexpected 429 is zero; timeout/5xx and dropped iterations stay within the
  scripted thresholds.
- Exactly 60 ticket and 60 WebSocket attempts; connect and full-session hold
  rates are at least 99.9%; invalid envelope is zero.
- No restart/OOM; DB wait/pool headroom remains at least 80%; Redis has no
  evictions/blocked clients; CPU does not remain above 85% for two minutes.

## Separate principal semantics proof

After the capacity profile has stopped, run
`scripts/load/opshub-staging-rate-limit-semantics.js` with the same base URL,
run id and token manifest, plus
`LOAD_APPROVAL=OPSHUB_STAGING_RATE_LIMIT_SEMANTICS_APPROVED`. One synthetic user
must exceed 120 requests/minute on read-only `GET /auth/me` and receive 429 with
`Retry-After`; the control user from the same source IP must remain 200.
The fixed arrival-rate scenario reserves two VUs so one cold request cannot
create a generator-side dropped iteration and falsely fail this semantics gate.
Intentional 429 responses belong only to this semantics result and are excluded
from the capacity result.

The manual Payment Monitor proof is separate: fill the bucket for the same
staging staff and trusted IP, let the app observe 429, then press manual refresh
twice. Sanitized API/client logs must show one bypass request; the second action
is deferred locally. Keep the speaker disabled and do not exercise ready/audio
side effects.

## Mandatory cleanup

Stop k6 and every WebSocket first. Then run, even after a failed or interrupted
test:

```bash
bash deploy/staging/manage-load-users.sh revoke "$RUN_ID" PREPARE_OPSHUB_STAGING_LOAD_USERS
bash deploy/staging/manage-load-users.sh delete "$RUN_ID" PREPARE_OPSHUB_STAGING_LOAD_USERS
```

Revoke disables all 60 users, increments token versions and revokes their
sessions. Delete is fail-closed: it refuses active users/sessions or unexpected
business references, deletes only the exact run prefix, verifies zero remaining
records and removes the server token file.

If database deletion completed but the wrapper was interrupted before removing
the token file, do not rerun `delete`: zero accounts intentionally fails its
exact-60 gate. Use the idempotent recovery check instead:

```bash
bash deploy/staging/manage-load-users.sh verify-empty "$RUN_ID" PREPARE_OPSHUB_STAGING_LOAD_USERS
```

`verify-empty` succeeds only when the run prefix, tagged assignments, email
codes and known email-based audit/non-FK references are all empty; only then
does it remove the residual server token file. Delete every workstation token/k6
binary/raw-output copy and verify no k6 or test WebSocket process remains. If
cleanup cannot be proven, the release is not ready.

## Interpretation and promotion boundary

Publish only sanitized totals in the staging report: code SHA, workflow run,
k6 summary, resource metrics, Windows staging build and cleanup count. A green
15-minute hold is release proof at the stated threshold; it is not evidence for
the rolling 30-day SLO. Engineering owns the 30-day error budget and promotion
stops when less than 25% remains. RPO 24 hours and RTO 4 hours are separate
production gates; this load run does not prove either objective.
