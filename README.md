# PhongVu OpsHub

The default path requires no local database.
Repository guidance and validation state are kept in Git, while any legacy
`harness.db` is archive-only.

PhongVu OpsHub is an internal operations app for Phong Vu staff. The Flutter app covers daily store and warehouse workflows: email/password registration and sign-in, FIFO check, FIFO sorting, warranty/repair image capture, staff suggestions, and admin FIFO history.

## Project Layout

- `lib/` - Flutter application.
- `backend-nest/` - NestJS API service with Prisma, JWT auth, BigQuery sync, warranty, feedback, inventory, sort, and FIFO log modules.
- `backend-go/` - Go realtime service for Redis-to-WebSocket broadcasts.
- `docker-compose.yml` - Local PostgreSQL and Redis.
- `n8n/` - Legacy workflow exports kept for reference only.
- `screen_mockups/` - UI mockups for the current mobile flows.

## Flutter

```bash
node scripts/run-with-toolchain.mjs --profile flutter -- flutter analyze
node scripts/run-with-toolchain.mjs --profile flutter -- flutter test
node scripts/run-with-toolchain.mjs --profile flutter -- flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

For an existing or resumed worktree, repair ignored dependencies before the
first build/test command:

```bash
node scripts/toolchain-doctor.mjs --root ..\opshub-ops-123 --profile all
```

The GitHub Actions Flutter setup also runs the repository preflight after cache
restore, so a cache hit is not mistaken for a ready worktree. Resumed or IDE
worktrees must use the doctor command and the shared wrapper before the first
build/test; direct raw Flutter commands are not a supported dependency
boundary.

If `API_BASE_URL` is not provided, the app falls back to the LAN development URL in `ApiConstants`.

## Backend

```bash
copy .env.example .env
# Replace both local password placeholders in .env before continuing.
docker compose up -d

copy backend-nest/.env.example backend-nest/.env
node scripts/run-with-toolchain.mjs --profile nestjs --preflight-only
node scripts/run-with-toolchain.mjs --profile nestjs --cwd backend-nest -- npm run build
node scripts/run-with-toolchain.mjs --profile nestjs --cwd backend-nest -- npm run start:dev
```

The local database and Redis ports bind only to `127.0.0.1`. Keep the
PostgreSQL/Redis passwords in the ignored local `.env` files synchronized with
the values used by the Nest and Go processes; never reuse staging or production
credentials.

The NestJS service needs PostgreSQL, Redis, auth, and BigQuery environment variables. Do not commit real `.env` files or service-account JSON.

## Realtime Service

```bash
cd backend-go
go test ./...
go run .
```

The Go service listens for Redis events, exposes legacy authenticated workflow
events on `/ws`, shared versioned signals such as Home refresh on `/ws/v2`, and
public app-update-only signals on `/ws/app-updates`.

## Current Backend Status

Runtime app flows now use the NestJS/Go backend. Auth, FIFO check, sort, feedback submission, warranty upload, and FIFO history are wired through backend services. The `n8n/` folder remains only as legacy reference material.
