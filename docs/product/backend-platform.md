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
- Mobile update metadata is exposed by `GET /app-version`.
- Staff client downloads are exposed by `GET /download`, backed by the public
  manifest at `GET /downloads/latest.json`.

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
- Deploy source branches are `staging` and `main` only. Pushing `staging` runs
  the staging workflow. Production deploys fast-forward `main` from accepted
  `staging` code, then push `main` to run the production workflow.
- Full production GitHub deploys build the client packages in Actions, upload the APK,
  Windows installer, Windows ZIP, and checksum directly to VPS staging, then
  promote them to `/srv/opshub/downloads/` and publish `/downloads/latest.json`
  for the download landing page. Manual `workflow_dispatch` with
  `skip_client_build=true` refreshes only the static download page and manifest
  from existing live artifacts; it must not change app-version metadata or
  rebuild client packages.
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
