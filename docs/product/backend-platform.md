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

## Expected Proof

- `npm run build` and Jest tests for NestJS.
- `go test ./...` for realtime service.
- Docker and health check smoke when deployment or env behavior changes.
