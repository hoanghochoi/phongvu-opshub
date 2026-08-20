# OPS-210 — OpsHub domain migration

## Scope

Move the public OpsHub contract to `phongvu.work` while preserving a bounded
legacy bridge for installed clients. Production uses `phongvu.work` and
`api.phongvu.work/v1`; staging uses `staging.phongvu.work` and
`api-staging.phongvu.work/v1`. BIDV is isolated under `/v1/bidv/*` on each API
hostname and realtime uses `/v1/ws`.

## Intake and checkpoint

- Linear issue: OPS-210.
- Lane: high-risk infrastructure/auth/session/realtime/BIDV/CORS migration.
- Task branch: `codex/ops-210-infra-migrate-opshub-domains-to-phongvu-work`.
- Base SHA: `430e1ffd2c8b3a2385aa72fc30502234ddb9932c` from `origin/staging`.
- Cloudflare zone: `phongvu.work` is active in the configured account.
- Cloudflare records created (proxied): `phongvu.work`, `api.phongvu.work`,
  `staging.phongvu.work`, `api-staging.phongvu.work`.
- Staging web and API hostnames now share the `opshub-staging` tunnel, as
  required by the migration contract. The former `opshub-staging-api` tunnel
  remains only as an unreferenced rollback/performance-isolation artifact until
  its separate OPS-42 lifecycle is explicitly retired.
- New tunnel ingress is intentionally `http_status:404` until the code is
  deployed and validated; this is the pre-code fail-closed gate.
- API cache bypass ruleset is active for `/v1/*` on both API hostnames.

## Ordered implementation

1. Keep Cloudflare DNS/TLS/Tunnel/cache protection fail-closed.
2. Add exact-host Caddy routing for new web/API contracts and a legacy web
   bridge that redirects UI paths while proxying only machine paths.
3. Update runtime env validation, CORS, BIDV public URL, and deployment env
   publication.
4. Update Flutter API/public/realtime URL defines, storage environment
   namespace detection, and self-update host allowlists.
5. Update only the staging and production workflows. The MSIX build workflow is
   retired from this release and is deleted; Windows distribution remains the
   signed EXE/ZIP path. During the bridge, app-version package URLs remain on
   the old download host so installed clients can fetch their bridge release;
   a later cleanup changes that metadata to the new web host. Android checkout
   skips LFS; Windows restores the scoped payment-audio cache keyed by all
   locale `manifest.json` files and pulls only that LFS subtree on a miss.
6. Validate Caddy, NestJS, Go, Flutter, workflow/config contracts and affected
   consumers. Do not open the new tunnel origins or perform production deploy
   from this branch without the release gate.

## Cutover and cleanup policy

- Staging and production old web host UI paths use `308` redirects to the new
  web host, preserving path/query. Legacy machine paths remain transparent
  until the environment has 24 continuous hours with zero valid old-client
  traffic.
- Valid traffic excludes bots, probes, 4xx noise, operator tests and browser
  UI redirects. If valid traffic returns, the counter resets.
- At cleanup: remove old proxy/CORS/package allowlists, return legacy API/WS
  paths as `410`, redirect old downloads/help/media to the new web host, and
  keep the UI redirect/DNS for the separately approved retention period.
- `bankapis-staging.hoanghochoi.com` is disabled at staging cutover; no new
  compatibility route is created for it.

## Rollback

Rollback keeps the new DNS and exact-host foundation available, restores the
previous application release/env snapshot, and re-enables the legacy machine
bridge only as needed. It does not return to a code release that cannot parse
the new domain contract.

## Verification record (before status transition)

- [x] `git diff --check` and exact worktree/SHA re-check.
- [x] Caddy structural validator and config/route contract tests. Live Caddy
      binary validation passes for both production and staging env bindings
      with `caddy:2.8.4`.
- [x] Cloudflare shared staging topology re-checked: both staging CNAMEs
      target `opshub-staging`; both new ingress entries remain
      `http_status:404` until the staging release opens the origin.
- [x] NestJS build/tests including BIDV path validation and CORS.
- [x] Go realtime tests.
- [x] Flutter analyze and full Flutter tests pass (`896` passed, `3` skipped),
      plus focused URL, storage, realtime, self-update and admin-endpoint
      coverage including the `/v1/ws/v2` ticket URI regression.
- [x] Workflow/config and affected-consumer proof (`verify-task --full`) passes
      at exact HEAD `6ff4c470078c4bd4e9fc9551ec8e4c605b731886`, with stable
      fingerprint
      `5743c4246e9ef2fc5f1d5ae3cd2229968c62c77625e6ce57749326f383ed8699`.
- [x] Confirm the retired MSIX workflow is absent and no active release job or
      package metadata points to MSIX. The direct EXE/ZIP path remains the only
      supported Windows release path.
- [ ] Staging deploy/QA and Cloudflare origin unblocking evidence.
- [ ] Production promotion/release-lock evidence.
