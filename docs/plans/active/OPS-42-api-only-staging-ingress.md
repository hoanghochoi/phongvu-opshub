# Execution Plan: OPS-42 API-only Staging Ingress

Date: 2026-07-30

## Status

Active

## Outcome

Expose the existing staging Nest API through
`api-opshub-staging.hoanghochoi.com` on a separate Cloudflare named tunnel,
without opening an origin port or changing the current staging hostname. The
new tunnel must forward only `/api/*`; every other path must fail closed. A
public health burst must reach p95 below 300 ms before the unchanged OPS-31
fixed Home profile may consume another synthetic-user run.

## Context

- Linear OPS-42 owns the infrastructure transaction and blocks OPS-31.
- Canonical start checkpoint:
  `staging = origin/staging = 4ba6e5915c5d04063700a1083c573a4f54f0f618`;
  the canonical worktree was clean.
- Task branch/worktree:
  `codex/ops-42-api-only-ingress` and `../opshub-ops-42-api-ingress`, created
  through `scripts/task-lifecycle.mjs start --execute` at the exact checkpoint.
- Current staging connector: `cloudflared-opshub-staging`, named tunnel
  `opshub-staging`, loopback origin `http://127.0.0.1:8090`, loopback metrics
  `127.0.0.1:20242`, origin keepalive pool 300 and four active connectors.
- OPS-31 proof already isolated client/Caddy p95 near three seconds while Nest
  p95 remained about 200 ms. A validated HTTPS/H2 origin experiment did not
  materially improve the public tail.
- Relevant authority: `deploy/staging/README.md`,
  `deploy/staging/load-proof-runbook.md`,
  `deploy/home-server/Caddyfile`, `docs/FEATURE_INTAKE.md`, and the OPS-31 SLO
  contract.

## Intake And Protected Behavior

Lane: high-risk maintenance. The work touches a runtime artifact, public
routing, shared staging ingress, the trusted-proxy boundary and load-proof
verification.

Protected existing consumers:

- the current `opshub-staging.hoanghochoi.com` API, web, download, Help and
  realtime routes through `cloudflared-opshub-staging`;
- Caddy's loopback-only origin, strict trusted-proxy normalization, security
  headers and staging Home telemetry;
- authenticated Home 1/7/30/90-day contract/parity and principal rate limits;
- staging deploy health and exact-SHA release evidence.

The new behavior is a second connector and DNS name. It does not alter API,
database, migration, permission, rate-limit or Flutter contracts. No Harness
write is authorized or required on this branch.

## Scope

In scope:

- Add a fail-closed installer for one locally managed API-only named tunnel.
- Keep tunnel credentials/config root-owned and metrics on loopback.
- Match only the approved hostname plus `/api/*`; return `http_status:404` for
  every fallback rule.
- Override the origin Host to the existing staging domain so the current Caddy
  site and synchronized Home telemetry remain authoritative.
- Provision the new staging tunnel and DNS route with an isolated systemd unit,
  without stopping the current connector.
- Verify old and new ingress, API-only rejection, connector state and rollback.
- Run the health gate and, only if green, the unchanged fixed Home proof.

Out of scope:

- Production, `main`, public origin ports or weakened Access/proxy/rate-limit
  controls.
- OPS-26 and `deploy_download_static`.
- OPS-34.
- Further Nest/DB optimization, schema changes or migrations.
- The 100-QPS capacity ladder unless the fixed OPS-31 gate first passes and a
  later explicit plan step authorizes it.

## Approach

1. Add and test a dedicated installer rather than generalizing or restarting
   the current tunnel service.
2. Validate inputs, locate/create exactly one named tunnel, route the new DNS
   name, install a root-only local tunnel credential and config, run
   `cloudflared tunnel ingress validate`, then start an isolated systemd unit.
3. Check the new tunnel has four HA connections, the old service stayed healthy,
   `/api/health` succeeds, and non-API paths return 404.
4. Publish through a reviewed PR to `staging`, deploy the exact merge SHA, then
   repeat runtime proof against the durable version.
5. Run a fixed public health burst. Stop before synthetic-user creation unless
   it returns 100% expected responses, zero 429/5xx/timeout and p95 below 300 ms.
6. If the health gate passes, run the unchanged 250-VU/2,000-request Home proof
   with synchronized Caddy/Nest telemetry and mandatory cleanup.

## Risks And Recovery

- A wrong DNS route could expose the wrong origin. Mitigation: require exact
  approved hostname/service names, exact tunnel identity, local ingress
  validation and a 404 catch-all before starting the unit.
- Reusing the old tunnel or metrics port could invalidate isolation. Mitigation:
  fail if the new tunnel ID equals the current tunnel ID or if the metrics
  address is not the dedicated loopback port.
- The origin Host override could bypass the intended route. Mitigation: the
  tunnel itself admits only `/api/*`; Caddy still enforces its existing route,
  proxy normalization, API auth and throttling.
- Credentials could leak through CLI/process output. Mitigation: copy the local
  credentials file into a root-only directory, never print/tokenize it, and
  keep commands/reports secret-free.
- Recovery: stop and disable only `cloudflared-opshub-staging-api`, restore its
  checkpointed unit/config if it existed, or remove the new unit files after
  verifying their exact paths. Restart and verify the original connector. A
  failed new DNS name may remain routed to an inactive tunnel until deliberate
  Cloudflare cleanup; the existing hostname is unaffected.

## Progress

- [x] Create OPS-42 and verify it blocks OPS-31.
- [x] Record Git and live staging baseline.
- [x] Implement installer, documentation and focused tests.
- [ ] Run local syntax, behavior, security and affected-consumer proof. The
      initial fingerprint passes 25 Node tests, Prettier, diff check, k6 inspect,
      live cloudflared ingress validation/rule selection and remote
      `systemd-analyze verify`; final proof remains after review.
- [ ] Open/merge a reviewed PR into staging and deploy its exact SHA.
- [ ] Provision and verify the new hostname/tunnel with rollback evidence.
- [ ] Run the public health gate.
- [ ] If allowed by the gate, run fixed Home proof, telemetry analysis and
      mandatory cleanup.
- [ ] Record proof in Linear and close or retain the measured blocker.

## Decisions

- 2026-07-30: Use a separate OPS-42 infrastructure transaction linked as the
  blocker of OPS-31.
- 2026-07-30: Use `api-opshub-staging.hoanghochoi.com`, tunnel
  `opshub-staging-api`, systemd unit `cloudflared-opshub-staging-api`, and
  loopback metrics `127.0.0.1:20243`.
- 2026-07-30: Use a locally managed ingress config so API-only routing and the
  catch-all denial are versioned and validated on the host. A second token-only
  `--url` connector cannot by itself prove that non-API paths are rejected.
- 2026-07-30: Preserve the origin HTTP path and set `httpHostHeader` to
  `opshub-staging.hoanghochoi.com`; the earlier verified HTTPS/H2 experiment was
  not retained because it did not remove the tail.
- 2026-07-30: Health p95 below 300 ms is the mandatory spend gate for another
  synthetic Home run.

## Validation

- Focused proof: shell syntax; installer contract tests with fake
  `cloudflared`, `sudo` and `systemctl`; `cloudflared tunnel ingress validate`.
- Integration proof: old/new public `/api/health`, new-host non-API 404,
  current/new connector HA and error metrics, origin listener remains loopback.
- Performance proof: fixed public health burst; unchanged OPS-31 fixed profile
  only after the health gate.
- Security proof: no public port, no credential output, root-only credential and
  config files, unchanged old unit, trusted-proxy and rate-limit controls.
- Repository-required checks: exact diff review, `git diff --check`, staging
  deploy and affected-consumer smoke.

Initial local proof on 2026-07-30:

- 25 focused analyzer, Home contract, exact-target, health-gate and installer
  tests passed.
- k6 v2.1.0 loaded the fixed 100-VU/100-request health profile with the exact
  thresholds and API-only target gate.
- The staging host's installed cloudflared 2026.3.0 accepted the exact ingress
  schema. Rule inspection selected the origin only for the new hostname plus
  `/api/health`; the same hostname `/download` and the old hostname
  `/api/health` both selected the 404 catch-all.
- The staging host's `systemd-analyze verify` accepted the hardened unit.
- Prettier and `git diff --check` passed. These results precede final review and
  will be rerun for the publication fingerprint.

## Result

Pending implementation and runtime proof.
