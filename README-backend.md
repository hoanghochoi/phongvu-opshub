# PhongVu OpsHub Backend

Backend-native architecture for the OpsHub mobile app. The Flutter app talks to the NestJS API for business flows, while the Go service bridges Redis events to WebSocket clients.

## Services

- `backend-nest/`: NestJS API with Prisma, JWT auth, first-use password login, inventory sync, FIFO check/sort, FIFO logs, warranty uploads, and feedback.
- `backend-go/`: Go realtime service that subscribes to Redis, broadcasts
  legacy authenticated workflow events on `/ws`, shared versioned signals on
  `/ws/v2`, and isolates public update signals on `/ws/app-updates`.
- `docker-compose.yml`: Local PostgreSQL and Redis only.
- `n8n/`: Legacy workflow exports kept as reference, not used by runtime app code.

## Client Bootstrap, Notification Feed, And Realtime V2

All HTTP paths below are relative to the Nest API base (`/api` in the default
deployment):

- `GET /auth/bootstrap` returns one authenticated access snapshot containing
  `schemaVersion`, `generatedAt`, stable SHA-256 `version`, `user`,
  `featureAccess`, `policyAccess`, and `capabilities`. The capability object
  advertises `conditionalGet=true` and the supported realtime v2 topics. The
  API sends `Cache-Control: private, no-cache` plus `ETag: "<version>"`, accepts
  `If-None-Match`, and returns `304` when the stable snapshot is unchanged.
- `GET /notifications/feed` returns one `schemaVersion=1` aggregate with
  `generatedAt`, `statementOrderTransfers`, and `offsetAdjustments`. Each
  section contains `enabled`, `page`, `limit`, `total`, `canReview`, and `list`.
  This lets the authenticated shell load both notification sources with one
  HTTP request; compatibility clients may use the older list endpoints only
  when this aggregate route is unavailable (`404`/`501`).

Authenticated clients share one `/ws/v2` connection per session. Every message
uses `{v, kind, id, topic, seq, ts, data}`; gateway audience metadata is checked
server-side and is not forwarded. HTTP remains the source of complete state,
so reconnect/resume requests a bounded HTTP resync.

`ACCESS_CHANGED` is recipient-scoped. The gateway delivers it to the affected
socket, then closes that socket with a retryable resync reason so claims issued
before a grant/revoke cannot keep receiving later events. Sensitive events with
only a feature filter and no user/store/role/organization routing selector are
rejected fail-closed.

All-scope authorization travels in a dedicated `policyCodes` claim/audience
field. The gateway never compares policy codes with organization, department,
business, or store codes, so equal text in different namespaces cannot widen a
subscription.

| v2 topic | v2 kind | Purpose |
| --- | --- | --- |
| `access.changed` | `ACCESS_CHANGED` | User-scoped access snapshot invalidation |
| `home.summary` | `HOME_SUMMARY_UPDATED` | Home projection invalidation |
| `warranty` | `WARRANTY_EVENT` | Warranty status invalidation |
| `payment.transactions` | `PAYMENT_NOTIFICATION` | Payment-list invalidation |
| `payment.speaker` | `PAYMENT_SPEAKER_STREAM` | Minimal speaker metadata |
| `payment.delivery-metrics` | `PAYMENT_DELIVERY_METRICS_UPDATED` | Delivery-metrics invalidation |
| `notifications.statement-transfer` | `STATEMENT_ORDER_TRANSFER_REQUEST` | Statement-transfer notification |
| `notifications.offset-adjustment` | `OFFSET_ADJUSTMENT_NOTIFICATION` | Offset-adjustment notification |
| `sales-report.orders` | `SALES_REPORT_ORDERS_UPDATED` | Sales-report order invalidation |

Legacy authenticated `/ws` continues to emit `{type, payload}` during the
two-release client migration window. It is compatibility-only and must not gain
new feature contracts. Public `/ws/app-updates` remains separate so update
discovery works before login. One-time ticket authentication remains the normal
contract for both authenticated endpoints; legacy JWT WebSocket authentication
is available only behind `WS_ALLOW_LEGACY_JWT` during the measured migration.

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
  global MAP sync runs from 07:00 to before 22:00 Vietnam time and reads 100 rows
  per page. The fast lane fetches page 1 only, then waits a random 1000-2000 ms;
  tune that range with `MAP_VIETIN_SYNC_DELAY_MIN_MS` and
  `MAP_VIETIN_SYNC_DELAY_MAX_MS` (minimum accepted value: 500 ms). A deep sweep
  uses up to `MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES=2` at startup, after a MAP session
  refresh, and every random 30000-60000 ms. Persistent HTTP 429 responses back
  off for 30, 60, then 120 seconds plus jitter and honor a longer provider
  `Retry-After`; a persistent HTTP 403 after the one-time session refresh backs
  off for 5 minutes. A bounded in-memory SHA-256 fingerprint cache skips DB
  reads/writes for identical poll rows for five minutes (20,000 entries by
  default), while cache miss/restart still falls back to the durable idempotent
  DB path. The global MAP session is cached for
  `MAP_VIETIN_GLOBAL_SESSION_TTL_SECONDS` seconds, defaulting to 600.
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
  near-simultaneous provider responses. Product-facing `Mã sao kê` values use
  eFAST `trxId`, which matches the MAP statement reference; eFAST `trxRefNo`
  remains a provider-side technical reference in raw audit data. Rows with
  missing `pmtId` are still stored
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
  and realtime fallback; after realtime has been silent it checks metadata once
  per minute. It only recovers notifications newer than
  `PAYMENT_STREAM_PENDING_RECOVERY_WINDOW_SECONDS` (default `30`), whether the
  audio is `PENDING` or already `READY`. Expired pickup attempts are logged as
  `SILENCED` with `stream_recovery_window_expired`, and `/stream` rejects them
  so another client cannot replay stale audio. Delivery metrics use the
  first-ever `STREAM_STARTED` event per notification, preventing a later client
  from inflating a newer time bucket. Speaker backlog playback still goes
  through `/stream`, not `/audio`. The `Tiền vào` transaction list loads once on
  entry and after explicit filter/page/refresh actions, then refreshes from
  payment WebSocket events. It does not poll transactions on a fixed interval
  or merely because the socket reconnects. Set
  `PAYMENT_TTS_CONCURRENCY=2` to match the recommended two Piper workers on
  `hoang-n8n`.
- Keep placeholder values out of production; the Nest API validates env values on startup.
- Keep the API behind exactly one trusted Caddy hop. The sole global bucket is
  `principal` at 120 requests per 60 seconds; Nest adds HTTP method and endpoint
  to the storage key. A valid JWT uses
  `principal:user:<userId>:ip:<sha256(trustedIp)>`; public auth uses
  `principal:email:<sha256(normalizedEmail)>` when possible, then
  `principal:ip:<sha256(trustedIp)>`. There is deliberately no second global IP
  bucket. Raw IP addresses must not enter throttler keys or logs, and every 429
  must include `Retry-After`. The accepted residual risk is that anonymous
  callers can rotate email and signed-in users can change IP to receive a new
  bucket; expensive routes keep their existing endpoint-specific quotas.
- Run `npx prisma migrate deploy` before starting the Nest API.
- Start the Go service with the same Redis connection as NestJS.
- Home near-realtime is projection-first. Source-table triggers write a durable
  outbox plus a coalesced daily queue in the same PostgreSQL transaction;
  `NOTIFY` only wakes the worker, which still polls every second. Keep
  `HOME_SUMMARY_PROJECTION_ENABLED=true` and
  `HOME_SUMMARY_PROJECTION_WORKER_ENABLED=true`. The legacy synchronous GET
  refresh remains available for one release through
  `HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED`, default `false`. Enable
  `HOME_SUMMARY_ERP_BACKFILL_ENABLED` only for the checkpointed one-time
  90-day ERP cache backfill.
- Flutter Home uses `HomeSummaryRepository.summaryFreshTtl` as the only cache
  freshness source, fixed at 60 seconds. Route activation before 60 seconds
  reuses the snapshot; at or after 60 seconds it deduplicates one revalidation.
  Realtime invalidation, reconnect and app resume may force one network read,
  but there is no Home polling timer. A failed revalidation keeps the stale
  snapshot and its original `fetchedAt`, so the next eligible activation retries
  instead of extending freshness artificially.

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
