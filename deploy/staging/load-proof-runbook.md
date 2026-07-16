# Staging Home And Realtime Release-Proof Runbook

This runbook is for the explicitly approved OpsHub staging release proof only.
It is not authorized for production. It exercises read-only authenticated HTTP
and `/ws/v2`; public/legacy sockets, Payment ready polling and write endpoints
stay disabled.

## Safety boundary

- Run only against `https://opshub-staging.hoanghochoi.com/api` and
  `wss://opshub-staging.hoanghochoi.com/ws/v2`. The scripts hard-fail for any
  other target, approval phrase, run id, user count, RPS or socket count.
- Use an official stable k6 archive downloaded to a temporary workstation
  directory. Verify its SHA-256 against the checksum published with that exact
  k6 release. Do not install it globally and do not copy the generator to the
  staging host.
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

## Capacity profile

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
days), 10% Home scopes, 10% auth bootstrap and 10% auth me, plus 60 `/ws/v2`
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
