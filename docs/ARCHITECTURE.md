# Architecture

PhongVu OpsHub is an internal operations hub with a Flutter client, a NestJS API,
a Go realtime bridge, PostgreSQL, Redis, and BigQuery integration.

## Runtime Map

```text
Flutter app
  -> NestJS API
      -> PostgreSQL through Prisma
      -> Redis events
      -> BigQuery sync/query integration
      -> upload storage

Redis
  -> Go realtime service
      -> WebSocket clients
```

## Code Ownership

| Area | Path | Responsibility |
| --- | --- | --- |
| Flutter app | `lib/` | UI, local state, API client, mobile workflows |
| NestJS API | `backend-nest/src/` | auth, business rules, persistence, uploads, Redis publish |
| Prisma schema | `backend-nest/prisma/schema.prisma` | database model and migrations |
| Go realtime | `backend-go/` | Redis subscribe and WebSocket broadcast |
| Deployment | `deploy/`, `docker-compose.yml` | local services and deployment notes |

## Boundary Rules

- Parse and validate unknown input at boundaries: HTTP DTOs, JWT claims,
  environment variables, uploaded files, Redis payloads, and external data.
- Keep product rules out of Flutter widgets when they belong to the API.
- Keep upload paths, service accounts, and secrets outside git.
- Keep Redis event names and payload shapes stable or document the contract
  change in `docs/product/backend-platform.md`.
- Database migrations require explicit validation and rollback notes.

## Validation Ownership

| Change area | Minimum proof |
| --- | --- |
| Flutter UI/state | `flutter analyze`, `flutter test` |
| API service/rules | `npm run build`, focused Jest tests |
| Prisma schema | migration review plus API tests |
| Redis/WebSocket | Nest publisher test plus `go test ./...` |
| Deployment/env | documented smoke checks and health endpoints |
