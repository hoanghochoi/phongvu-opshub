# PhongVu OpsHub

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
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

If `API_BASE_URL` is not provided, the app falls back to the LAN development URL in `ApiConstants`.

## Backend

```bash
docker compose up -d

cd backend-nest
copy .env.example .env
npm install
npm run build
npm run start:dev
```

The NestJS service needs PostgreSQL, Redis, auth, and BigQuery environment variables. Do not commit real `.env` files or service-account JSON.

## Realtime Service

```bash
cd backend-go
go test ./...
go run .
```

The Go service listens for Redis events, exposes authenticated workflow events
on `/ws`, and exposes public app-update-only signals on `/ws/app-updates`.

## Current Backend Status

Runtime app flows now use the NestJS/Go backend. Auth, FIFO check, sort, feedback submission, warranty upload, and FIFO history are wired through backend services. The `n8n/` folder remains only as legacy reference material.
