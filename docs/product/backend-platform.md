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
- Client update metadata is exposed by `GET /app-version` and remains the source
  of truth for update availability, force/minimum-build rules, and download URL.
- A full API startup publishes `APP_VERSION_UPDATED` through Redis. Go exposes
  that signal as `APP_UPDATE` on the public, updates-only `/ws/app-updates`
  endpoint. Running clients recheck `GET /app-version` after the signal,
  WebSocket reconnect, and app resume; no update decision trusts WebSocket
  payload alone.
- Staff client downloads are exposed by `GET /download`, backed by the public
  manifest at `GET /downloads/latest.json`.
- Public staff guidance is exposed by `GET /help`, backed by Markdown content
  and images deployed from `docs/help/`.

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
  `APP_UPDATE_URL`, `APP_RELEASE_NOTES`, and `APP_FORCE_UPDATE` when shipping
  a mobile APK. Clients compare `APP_BUILD_NUMBER` with their installed build
  number and open `APP_UPDATE_URL` when an update is required.
- Deploy source branches are `staging`, `main`, and `help-content`. Pushing
  `staging` runs the staging workflow. Production app deploys fast-forward
  `main` from accepted `staging` code, then push `main` to run the production
  workflow. The `help-content` branch is the production content source for
  `/help`; pushing it runs only the production static help/download deploy.
- Full production GitHub deploys build the client packages in Actions, upload the APK,
  Windows installer, Windows ZIP, and checksum directly to VPS staging, then
  promote them to `/srv/opshub/downloads/` and publish `/downloads/latest.json`
  for the download landing page. The same deploy publishes the built help site
  under `/srv/opshub/downloads/help/`. When `origin/help-content` exists, full
  production deploys load `docs/help` from that branch before building the help
  site. Pushing `help-content`, or running manual `workflow_dispatch` with
  `skip_client_build=true`, refreshes only the static download page and manifest
  plus the help site from existing live artifacts; it must not change
  app-version metadata or rebuild client packages.
- Staging deploys run on `staging` pushes or manual `Deploy OpsHub Staging`
  dispatches, target `opshub-staging.hoanghochoi.com` for API/runtime traffic,
  publish downloads under `/srv/opshub-staging/downloads/`, expose those
  downloads through `https://opshub.hoanghochoi.com/staging-download`, and build
  staging client packages with separate Android and Windows app identities.
  Staging DB refresh is a separate manual sanitized-clone operation and is not
  part of the normal staging deploy workflow.

## Expected Proof

- `npm run build` and Jest tests for NestJS.
- `go test ./...` for realtime service.
- Docker and health check smoke when deployment or env behavior changes.
