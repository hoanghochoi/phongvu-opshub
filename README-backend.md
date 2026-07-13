# PhongVu OpsHub Backend

Backend-native architecture for the OpsHub mobile app. The Flutter app talks to the NestJS API for business flows, while the Go service bridges Redis events to WebSocket clients.

## Services

- `backend-nest/`: NestJS API with Prisma, JWT auth, first-use password login, inventory sync, FIFO check/sort, FIFO logs, warranty uploads, and feedback.
- `backend-go/`: Go realtime service that subscribes to Redis, broadcasts
  authenticated workflow events on `/ws`, and isolates public update signals on
  `/ws/app-updates`.
- `docker-compose.yml`: Local PostgreSQL and Redis only.
- `n8n/`: Legacy workflow exports kept as reference, not used by runtime app code.

## Local Quick Start

Start infrastructure from the repository root:

```bash
copy .env.example .env
# Replace both local password placeholders in .env before continuing.
docker compose up -d
```

PostgreSQL and Redis bind to `127.0.0.1` only. Copy the same local PostgreSQL
password into `backend-nest/.env`'s `DATABASE_URL`, and the same Redis password
into `REDIS_PASSWORD` for both Nest and Go local env files. Do not reuse a
staging or production secret.

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
- For sales-report analytics in Looker Studio, set
  `SALES_REPORT_BIGQUERY_SYNC_ENABLED=true`,
  `SALES_REPORT_BIGQUERY_PROJECT_ID`,
  `SALES_REPORT_BIGQUERY_DATASET_ID`, and optionally
  `SALES_REPORT_BIGQUERY_KEY_FILE` plus table ids/prefix. OpsHub full-refreshes
  four BigQuery tables from the runtime DB: reports, revenue-by-store, order
  items, and payments. The revenue table keeps one summary row per store instead
  of one all-store total row.
  The dataset must already exist and the service account must be allowed to run
  load jobs and create/replace tables in that dataset. Scheduled sync runs once
  per day at 07:00 Vietnam time (UTC+7) when sync is enabled.
  Admins with `ADMIN_SALES_REPORTS` can manually trigger the same sync with
  `POST /api/sales-reports/admin/bigquery-sync`.
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
  global MAP sync runs from 07:00 to before 22:00 Vietnam time, reads 100 rows
  per page, and defaults to `MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES=2`. The global
  MAP session is cached for `MAP_VIETIN_GLOBAL_SESSION_TTL_SECONDS` seconds,
  defaulting to 600, and refreshes automatically after MAP auth errors.
- VietinBank eFAST account-detail sync is an optional secondary source behind
  `VIETIN_EFAST_SYNC_ENABLED=false` by default. Configure
  `VIETIN_EFAST_USERNAME`, `VIETIN_EFAST_PASSWORD`, and
  `VIETIN_EFAST_BANK_ACCOUNTS` as a comma-separated list such as
  `account-1,account-2` in the server `.env`; never commit real credentials.
  If the eFAST login account can choose more than one enterprise, also set
  `VIETIN_EFAST_CIFNO`. The adapter logs in through `/api/v1/account/login`,
  reads `/api/v1/account/history` for credit rows only, uses each row `pmtId`
  as the showroom virtual account to match `Store.transferAccountNumber`, and
  keeps the configured bank account only as the eFAST history source/audit
  field. eFAST sync uses the Vietnam business date (UTC+7) for provider
  history queries. MAP and eFAST derive the same source-agnostic transaction
  key from the bank statement reference, and both ingestion directions check
  all stored statement identifiers before insert. This prevents duplicate rows
  and payment notifications whether MAP or eFAST arrives first, including
  near-simultaneous provider responses. Rows with missing `pmtId` are still stored
  with `storeCode=null` so
  Super Admin, Finance-node users, and `phongvu.vn` users can review them; a
  user who finds that row by statement number, order, amount, or transfer
  content can update the order code, and the row is then assigned to that
  user's showroom. Rows with an unmapped or ambiguous `pmtId` are quarantined
  without creating payment audio. eFAST runs on its own scheduler: random
  50-60 seconds between 08:00 and 22:00 Vietnam time (UTC+7), then every
  30 minutes from 22:01 through 07:59 the next day. Keep
  `VIETIN_EFAST_PAGE_SIZE=150` and `VIETIN_EFAST_SYNC_MAX_PAGES=1`; the
  runtime caps eFAST at one page per configured bank account to stay below the
  provider's 20-query/5-minute limit. `VIETIN_EFAST_SESSION_TTL_SECONDS`
  defaults to 600 seconds.
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
  TTS-only for older app versions. To trial shorter TTS generation, set
  `PAYMENT_TTS_AUDIO_MODE=amount_only_with_prefix` and provide a compatible
  `PAYMENT_PREFIX_WAV_PATH` such as `/data/import/payment-prefix.wav`; the
  backend then sends only the amount text to TTS and joins the fixed prefix back
  into both combined and fallback audio. For the fastest server-combined path,
  also provide `PAYMENT_CUE_PREFIX_WAV_PATH` such as
  `/data/import/payment-cue-prefix.wav`; this file should be the prejoined cue
  plus prefix WAV generated with the configured `PAYMENT_CUE_GAIN`. Amount-only
  WAVs are cached by text/voice/speed/pitch under
  `PAYMENT_AUDIO_DIR/amount-cache` by default, retained for
  `PAYMENT_AMOUNT_AUDIO_CACHE_RETENTION_DAYS` (default `90`), and can be served
  to newer clients through
  `GET /payment-notifications/:id/audio?rawAmount=true`. The Windows client
  trims zero padding, joins its bundled `payment-cue-prefix.wav` to the amount
  with an 80 ms gap, and plays one WAV to avoid player-switch latency. Older
  or manual clients may still download through `/audio`, but the current
  Windows speaker flow now downloads speaker audio only through
  `GET /payment-notifications/:id/stream`; `/payment-notifications/ready`
  remains a metadata-only backlog endpoint that returns `audioUrl` plus
  `streamUrl`. The client falls back to sequential playback when the two PCM
  WAV formats are incompatible.
  Low-latency speaker streaming should run with
  `PAYMENT_SPEAKER_STREAMING_ENABLED=true`: the API creates the notification
  immediately, publishes `PAYMENT_SPEAKER_STREAM` up to
  `PAYMENT_STREAM_EVENT_REPEAT_COUNT` times, and only calls Piper when a
  speaker client requests `GET /payment-notifications/:id/stream`. The client
  records `STREAM_STARTED` when playback begins; delivery metrics then measure
  `paidAt -> streamStartedAt`. Stream requests include `clientId`, and the API
  now claims `DELIVERED` before preparing audio, guarded by an advisory lock on
  `notificationId + clientId`; a second in-flight request for the same pair
  returns HTTP `409` so the client can suppress duplicate same-machine
  playback. Ready polling is limited to speaker-enabled startup/manual recovery
  and `PAYMENT_NOTIFICATION` realtime events; it only recovers stream-pending
  notifications newer than `PAYMENT_STREAM_PENDING_RECOVERY_WINDOW_SECONDS`
  (default `30`). Older stream-pending notifications are logged as `SILENCED`
  with `stream_recovery_window_expired`, and `/stream` rejects them so no client
  plays stale audio after reconnect. Speaker backlog playback still goes
  through `/stream`, not `/audio`. The `Tiền vào` transaction list loads once on
  entry and after explicit filter/page/refresh actions, then refreshes from
  payment WebSocket events. It does not poll transactions on a fixed interval
  or merely because the socket reconnects. Set
  `PAYMENT_TTS_CONCURRENCY=2` to match the recommended two Piper workers on
  `hoang-n8n`.
- Keep placeholder values out of production; the Nest API validates env values on startup.
- Keep the API behind exactly one trusted Caddy hop. Rate limits use the
  verified JWT user id first, then stable request identifiers such as
  `clientId`/`deviceId`, then a hashed auth email for public auth requests. The
  resolved client IP is only a last-resort bucket, so normal clients do not
  share Caddy's container IP.
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
