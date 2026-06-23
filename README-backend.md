# PhongVu OpsHub Backend

Backend-native architecture for the OpsHub mobile app. The Flutter app talks to the NestJS API for business flows, while the Go service bridges Redis events to WebSocket clients.

## Services

- `backend-nest/`: NestJS API with Prisma, JWT auth, first-use password login, inventory sync, FIFO check/sort, FIFO logs, warranty uploads, and feedback.
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

## Smoke Checks

After starting the services, verify liveness before testing app flows:

```bash
curl http://localhost:3000/health
curl http://localhost:8080/health
```

Expected responses:

```json
{"status":"ok","service":"backend-nest"}
{"status":"ok","service":"backend-go"}
```

## Deployment Checklist

- Set a strong `JWT_SECRET`.
- Configure SMTP so registration and password reset code emails can be sent.
  For Gmail, use an app password for `SMTP_USER`; `SMTP_FROM` can be the
  verified Gmail "Send mail as" alias `admin@hoanghochoi.com`.
- Set `DATABASE_URL` to the production PostgreSQL database.
- Set `REDIS_HOST` and `REDIS_PORT` consistently for NestJS and Go.
- Keep `data/email_domain.txt` limited to accepted root fallback domains
  (`phongvu.vn`, `acare.vn` by default). Operational subdomains should be
  managed as active organization tree nodes in OpsHub admin; `EMAIL_DOMAIN_FILE`
  is only the fallback file path when the tree is unavailable.
- Set all `BIGQUERY_*` values and place the service-account JSON outside git.
- For n8n VietQR image/status integration, set `VIETQR_EXTERNAL_API_KEY` and
  send it from n8n with `x-opshub-vietqr-key` or `Authorization: Bearer <key>`.
  `GET/POST /vietqr/n8n/status` accepts `paymentId`/`id`; `check=true` compares
  only against MAP transactions already synced into OpsHub DB, without calling
  MAP directly. The backend also reconciles all `PENDING` VietQR payment
  intents against the synced MAP transaction table every 5 seconds and marks
  intents `FAILED` once their Vietnam-local creation day has passed. Set
  `VIETQR_AUTO_RECONCILE_ENABLED=false` only when this background reconciliation
  must be paused.
- For MAP payment sync, prefer `MAP_VIETIN_GLOBAL_USERNAME` and
  `MAP_VIETIN_GLOBAL_PASSWORD` so one backend account can read all showroom
  transactions. The sync maps MAP `virtualAccount` values to
  `Store.transferAccountNumber`; unmapped rows are quarantined and do not play
  payment audio. Per-store MAP credentials remain a fallback when the global
  account is not configured or `MAP_VIETIN_GLOBAL_SYNC_ENABLED=false`. The
  global MAP sync runs from 08:00 to before 22:00 Vietnam time, reads 100 rows
  per page, and defaults to `MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES=2`. The global
  MAP session is cached for `MAP_VIETIN_GLOBAL_SESSION_TTL_SECONDS` seconds,
  defaulting to 600, and refreshes automatically after MAP auth errors.
- Set `UPLOAD_BASE_DIR` to a persistent VPS directory, for example `/data/app_images`.
- Set `IMAGE_BASE_URL` to the public image domain that serves `UPLOAD_BASE_DIR`.
- `UPLOAD_MAX_BYTES` limits each warranty/feedback image and defaults to 10 MiB.
- `AVATAR_UPLOAD_MAX_BYTES` limits each avatar image and defaults to 2 MiB.
- For payment notification audio, run the Piper sidecar from
  `deploy/home-server/tts-piper/` and point `TTS_SERVICE_URL` to
  `http://172.20.0.1:18081`. The sidecar keeps the existing `/synthesize`
  contract, returns `audio/wav`, and accepts the legacy VieNeu voice id for
  rollback-friendly deploys. Production uses `PIPER_LEADING_SILENCE_MS=0` and
  `PIPER_TAIL_SILENCE_MS=500`; combined audio applies
  `PAYMENT_CUE_GAIN=0.80` to the cue so speech starts immediately at full level
  while the final word keeps its tail padding. The Windows local-cue fallback
  also plays its MP3 cue at `80%` and keeps voice playback at `100%`. New
  clients may call
  `GET /payment-notifications/:id/audio?includeCue=true` to download one
  server-combined WAV with the cue plus TTS; the default endpoint remains
  TTS-only for older app versions.
- Keep placeholder values out of production; the Nest API validates env values on startup.
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
