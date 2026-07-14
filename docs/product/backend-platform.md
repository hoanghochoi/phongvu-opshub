# Backend Platform Contract

## Intent

The backend stack provides stable APIs, persistence, realtime updates, and local
development services for OpsHub.

## Current Shape

- NestJS API runs on port 3000 by default.
- Go realtime service runs on port 8080 by default.
- PostgreSQL and Redis are started with `docker-compose.yml`.
- Prisma owns the database schema.
- BigQuery configuration is required for inventory-related backend behavior.
- Home Summary near-realtime uses a PostgreSQL outbox plus daily projection.
  Source transactions only persist source data and durable work; a worker
  rebuilds additive `GLOBAL`, `STORE`, and `USER_STORE` grains asynchronously.
  PostgreSQL `NOTIFY` is a wake-up hint and one-second outbox polling is the
  loss-safe fallback. Redis carries only the post-commit realtime signal.
- The authenticated `/ws/v2` endpoint carries versioned topic events. Home uses
  `HOME_SUMMARY_UPDATED` on `home.summary`; its payload has affected dates and
  a projection version but never KPI values. Flutter re-reads
  `GET /home/summary` after a relevant event. Existing `/ws` feature clients
  remain compatible during the Phase 2 migration window.
- Client update metadata is exposed by `GET /app-version` and remains the source
  of truth for update availability, force/minimum-build rules, legacy download
  URL, and in-app self-update package metadata.
- Android and Windows metadata must include `packageUrl`, `packageSha256`,
  `packageSizeBytes`, and `packageType` when a release should update inside the
  app. Windows also publishes `installerArgs` so the client can launch the Inno
  Setup installer silently. `updateUrl` stays for older clients and must keep
  pointing at the same package unless a deliberate migration says otherwise.
- A full API startup publishes `APP_VERSION_UPDATED` through Redis. Go exposes
  that signal as `APP_UPDATE` on the public, updates-only `/ws/app-updates`
  endpoint. Running clients recheck `GET /app-version` after the signal,
  WebSocket reconnect, and app resume; no update decision trusts WebSocket
  payload alone.
- 2026-07-03 staging proof: publishing `APP_VERSION_UPDATED` through staging
  Redis reached both a raw public WebSocket client and the deployed Flutter web
  client; the web client then re-read `/api/app-version?platform=web` before any
  UI decision. The smoke used current metadata to avoid forcing staff updates.
- Staff client downloads are exposed by `GET /download`, backed by the public
  manifest at `GET /downloads/latest.json`.
- Public staff guidance is exposed by the public Flutter `/help` route, backed
  by `GET /api/help-content/public`.
- Runtime help content is managed by Super Admin through
  `/api/admin/help-content/*`. The production API container mounts
  `docs/help/*` read-only so runtime help can seed, auto-sync docs-managed
  pages, and restore from docs in deployed environments.
- Flutter web is served as the SPA root at `GET /` in production and staging.
  Caddy must route `/api`, `/ws`, `/download`, `/help/assets`, `/uploads`,
  `/downloads`, `/staging-download`, and `/health` before the SPA fallback, and
  let `/help` itself fall through to the SPA route.

## Health Checks

Expected local liveness checks:

```bash
curl http://localhost:3000/health
curl http://localhost:8080/health
curl http://localhost:3000/app-version
```

## Deployment Notes

- Run Prisma migrations before starting production NestJS.
- Use a strong `JWT_SECRET`.
- Keep service-account JSON outside git.
- Configure Redis consistently for NestJS and Go.
- Configure upload storage as persistent production storage.
- Configure `APP_VERSION`, `APP_BUILD_NUMBER`, `APP_MIN_SUPPORTED_BUILD`,
  `APP_UPDATE_URL`, `APP_PACKAGE_URL`, `APP_PACKAGE_SHA256`,
  `APP_PACKAGE_SIZE_BYTES`, `APP_PACKAGE_TYPE`, `APP_RELEASE_NOTES`, and
  `APP_FORCE_UPDATE` when shipping a mobile APK. Platform-specific
  `APP_ANDROID_*` and `APP_WINDOWS_*` values override the shared values.
  Clients compare `APP_BUILD_NUMBER` with their installed build number; Android
  and Windows clients automatically start downloading `packageUrl` inside the
  app when a newer build is detected, verify SHA-256 and package size, then hand
  off to the OS installer. Android still shows the system install-confirmation
  screen for self-hosted APKs. Windows uses the published silent Inno Setup args
  and exits after launching the installer.
- Deploy source branches are `staging`, `main`, and `help-content`. Pushing
  `staging` runs the staging workflow. Production app deploys fast-forward
  `main` from accepted `staging` code, then push `main` to run the production
  workflow. The `help-content` branch remains the production source branch for
  `docs/help/*` plus `/help/assets/*`; pushing it runs only the production
  static help/download deploy. That deploy syncs the latest `docs/help/*` onto
  the live release so docs-managed runtime help can auto-sync on the next load,
  while admin-edited runtime pages can be realigned manually through
  `Khôi phục từ docs`.
- Full production GitHub deploys build the client packages in Actions, upload
  the APK, Windows installer, Windows ZIP, and checksum directly to VPS staging,
  then promote them to `/srv/opshub/downloads/` and publish
  `/downloads/latest.json` for the download landing page. The same deploy
  builds Flutter web with
  `API_BASE_URL=https://opshub.hoanghochoi.com/api`, syncs it to
  `/srv/opshub/web/`, and publishes the built help asset bundle under
  `/srv/opshub/downloads/help/`. When `origin/help-content` exists, full
  production deploys load `docs/help` from that branch before building the help
  asset bundle and before shipping the release source mounted into the API
  container. Pushing `help-content`, or running manual `workflow_dispatch` with
  `skip_client_build=true`, refreshes only the static download page, help
  assets, and mounted `docs/help/*` source from existing live artifacts; it
  must not change app-version metadata or rebuild client packages.
- Staging deploys run on `staging` pushes or manual `Deploy OpsHub Staging`
  dispatches, target `opshub-staging.hoanghochoi.com` for API/runtime traffic,
  build Flutter web with
  `API_BASE_URL=https://opshub-staging.hoanghochoi.com/api`, publish it under
  `/srv/opshub-staging/web/`, publish downloads under
  `/srv/opshub-staging/downloads/`, expose those downloads through
  `https://opshub-staging.hoanghochoi.com/downloads/`, expose the protected
  download page at `https://opshub-staging.hoanghochoi.com/download`, and build
  staging client packages with separate Android and Windows app identities. The
  production `/staging-download` route is compatibility-only and must not be
  published in new app-version metadata.
  Staging DB refresh is a separate manual sanitized-clone operation and is not
  part of the normal staging deploy workflow.

## Expected Proof

- `npm run build` and Jest tests for NestJS.
- `go test ./...` for realtime service.
- Docker and health check smoke when deployment or env behavior changes.
- Home projection changes additionally require migration up/down proof,
  outbox/retry/reconciliation tests, KPI parity for 1/7/30/90-day ranges,
  freshness/stale behavior, and separate latency measurements for source commit
  to projection, projection to event, and event to repaint.
