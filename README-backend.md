# PhongVu OpsHub Backend

Backend-native architecture for the OpsHub mobile app. The Flutter app talks to the NestJS API for business flows, while the Go service bridges Redis events to WebSocket clients.

## Services

- `backend-nest/`: NestJS API with Prisma, JWT auth, Google login, inventory sync, FIFO check/sort, FIFO logs, warranty uploads, and feedback.
- `backend-go/`: Go realtime service that subscribes to Redis and broadcasts warranty status updates on `/ws`.
- `docker-compose.yml`: Local PostgreSQL and Redis only.
- `n8n/`: Legacy workflow exports kept as reference, not used by runtime app code.

## Local Quick Start

Start infrastructure from the repository root:

```bash
docker compose up -d
```

Run the Nest API:

```bash
cd backend-nest
copy .env.example .env
npm install
npx prisma generate
npx prisma migrate deploy
npm run start:dev
```

Run the realtime service in another terminal:

```bash
cd backend-go
go test ./...
go run .
```

Run the Flutter app against the local API:

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

## Deployment Checklist

- Set a strong `JWT_SECRET`.
- Set `DATABASE_URL` to the production PostgreSQL database.
- Set `REDIS_HOST` and `REDIS_PORT` consistently for NestJS and Go.
- Set `GOOGLE_CLIENT_ID` and `ALLOWED_DOMAIN`.
- Set all `BIGQUERY_*` values and place the service-account JSON outside git.
- Set `UPLOAD_BASE_DIR` to a persistent VPS directory, for example `/data/app_images`.
- Set `IMAGE_BASE_URL` to the public image domain that serves `UPLOAD_BASE_DIR`.
- Run `npx prisma migrate deploy` before starting the Nest API.
- Start the Go service with the same Redis connection as NestJS.

## Verification

From the repository root:

```bash
flutter analyze
flutter test
```

From `backend-nest/`:

```bash
npm run build
npm test -- --runInBand
```

From `backend-go/`:

```bash
go test ./...
```
