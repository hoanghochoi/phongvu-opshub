# VietQR

OpsHub supports a dedicated mobile screen for staff to create a transfer QR for
a customer to scan and pay manually.

## Contract

- Staff opens the VietQR screen from the home feature list.
- Staff may enter a fixed transfer amount, or leave the amount blank so the
  payer's banking app can fill it in.
- Staff may enter an order code or other transfer content. This field may also
  be left blank so the payer can fill in the transfer content.
- The app reads the active showroom from the signed-in user session and keeps it
  read-only. If the signed-in user has multiple assigned showrooms, the app must
  ask for one active showroom before creating a QR or running any single-SR
  payment flow.
- `SUPER_ADMIN` users can load the full showroom list and choose any SR for QR
  creation. Other users remain limited to their assigned showrooms.
- When staff enters transfer content, the final content is generated as
  `{CONTENT} {STORE_CODE} BOT` and is read-only in the preview.
- When amount or transfer content is blank, the backend omits the matching EMV
  field from the QR payload instead of encoding an empty value.
- The Flutter app requests VietQR data from the NestJS API and renders the QR
  image locally from the returned EMV payload.
- VietQR responses include `qrBrand` metadata. Stores in the ACareTek Region
  render QR images with the title `ACareTek` and the ACare logo; other stores
  render the title `Phong Vũ` and the Phong Vũ logo. The brand affects only the
  displayed/exported image, not the EMV payload or payment matching rule.
- n8n can call the secured OpsHub VietQR API to receive the same transfer
  details plus a server-rendered PNG image containing QR, brand title, logo,
  bank, account, amount, and transfer content. The endpoint requires
  `VIETQR_EXTERNAL_API_KEY` through `x-opshub-vietqr-key`, `Authorization:
  Bearer <key>`, or a query key for quick-link compatibility.
- The backend owns the bank BIN, account number, account name, and merchant
  city through environment configuration.
- Admin backend can probe VietinBank MAP payment transactions for a configured
  showroom so the next reconciliation step can match by amount, transfer
  content, success status, and time window.
- Each generated QR is stored as a payment intent so staff can run payment
  confirmation after showing the QR to the customer.
- The QR result screen automatically checks payment status while the screen is
  open when amount and transfer content are fixed. Staff can also tap
  `Kiểm tra ngay` to run the same check immediately.
- Each generated QR stores `createdAt` and expires after 15 minutes. Expired QRs
  stay in history, show an expired state, and cannot be reopened.
- On desktop, the VietQR screen uses a two-column layout: creation/result on the
  left and recent QR history on the right. The history panel shows status chips
  and lets staff reopen only still-valid QRs.
- Once payment is confirmed, the app hides the QR and shows a green success
  state with MAP transaction details when available: payer, received amount,
  transfer content, transaction number, and transaction time.
- Payment confirmation marks the intent as `PAID` only when exactly one
  VietinBank MAP transaction matches fixed amount, transfer content contained
  in the MAP transfer content, successful transaction status, and transaction
  time after QR creation. MAP transaction timestamps are interpreted as Vietnam
  local time. Missing amount/content, no match, or multiple matches remain
  unconfirmed and require manual review.
- The backend auto-reconciles every `PENDING` VietQR payment intent, including
  app-created and n8n-created intents, against already-synced
  `MapVietinTransaction` rows every 5 seconds. This job does not call MAP
  directly. If an intent is still `PENDING` after its Vietnam-local creation day
  has passed, the backend marks it `FAILED` with reason `EXPIRED_VIETNAM_DAY`.

## Payment Monitor

- Khu vực `Tài chính` trên dashboard Home dùng ngày và scope đang chọn ở
  header; khi mở `Trang chủ`, khoảng ngày mặc định là hôm nay rồi user đổi thủ
  công nếu cần. Dropdown SA trong `Tổng quan cá nhân` chỉ đổi KPI Bán hàng/Hành
  vi, không đổi số liệu Tài chính. Khu vực này tổng hợp trực tiếp từ
  `MapVietinTransaction`:
  tổng số tiền chuyển
  khoản, tổng số sao kê, tổng sao kê có/chưa có đơn hàng và
  `Tỉ lệ sao kê có đơn hàng = sao kê có đơn / tổng sao kê`. Scope toàn hệ thống
  đọc toàn bộ showroom; scope quản lý đọc các showroom thuộc node đã chọn;
  SA, Kỹ thuật, Kho và Thu ngân chỉ được chọn `Phạm vi cá nhân` hoặc từng
  showroom được gán. Ở phạm vi cá nhân, sao kê chỉ được tính khi có mã đơn
  thuộc đơn hàng cá nhân của user, không mở rộng thành toàn bộ showroom; khi
  chọn showroom được gán thì tính toàn showroom đó. Backend chỉ trả và app chỉ
  hiện khu vực khi node được bật tính năng `Dashboard - Tài chính`, độc lập với
  quyền mở màn hình `Sao kê`.
- The app exposes a `Tiền vào` home action for users with `PAYMENT_MONITOR` on
  Android, Windows, and web. Android and web show the stored transaction list
  without enabling the speaker path.
- The NestJS API is the source of truth for MAP transactions. It polls
  configured showroom MAP accounts in the background, stores successful incoming
  transactions in Postgres, and exposes the stored list to scoped clients.
- When a global MAP account is configured, the backend uses that account as the
  primary payment sync source, maps each MAP `virtualAccount` to
  `Store.transferAccountNumber`, and stores the transaction under the matched
  showroom. Per-showroom MAP credentials remain a fallback when global sync is
  disabled or not configured. Global sync reads 100 MAP rows per page. During
  the 07:00-to-before-22:00 Vietnam-time fast window, each 1000-2000ms fast loop
  fetches page 1 only. Page 2 is part of a deep sweep at startup, after a MAP
  session refresh, and every random 30000-60000ms; the deep sweep page cap is
  controlled by `MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES` and defaults to 2.
  `MAP_VIETIN_SYNC_DELAY_MIN_MS` and `MAP_VIETIN_SYNC_DELAY_MAX_MS` can tune
  this range, with a 500ms safety floor.
  HTTP 429 activates exponential 30/60/120-second backoff with jitter and a
  longer provider `Retry-After` is respected. While the cooldown is active,
  scheduled/direct sync calls stop before sending another provider request. A
  403 refreshes the cached session once; a persistent 403 then pauses MAP sync
  for 5 minutes. Successful recovery clears the backoff counter.
  Identical rows are filtered first by a bounded RAM fingerprint cache (default
  TTL 5 minutes, 20,000 entries), then by a DB no-op comparison on cache miss.
  New rows are still committed before payment notification publication; the
  cache is only a load-shedding layer, never the source of truth.
  From 22:00 to before 07:00, MAP sync still runs but uses a 30-minute cadence.
  `MAP_VIETIN_SYNC_ENABLED=false` remains the full off switch.
- Successful global MAP rows that cannot be mapped to exactly one showroom are
  quarantined for debug and do not create payment notifications or play audio.
- The monitor is independent from OpsHub-created QR/payment intents. It reads
  all successful incoming VietinBank MAP transactions stored for the selected
  showroom, not only transfers that match an OpsHub QR.
- The monitor transaction list can be filtered by assigned showroom and a
  Vietnam-local date range, for example 23-27/05, and remains paginated by the
  selected row count. List filters use dropdown/anchored menus; custom date
  entry uses `dd/mm/yyyy` with `/` separators while typing.
- Each transaction card shows the payer name/account when MAP provides it.
  Tapping a card opens a selectable detail dialog with the full available payer,
  amount, transaction time/number, content, status, showroom, and OpsHub
  first-seen timestamp. Missing MAP fields are shown explicitly as unavailable.
- Each transaction card shows an SR pill so multi-showroom views remain clear.
- The app starts the monitor after sign-in when the account has at least one
  assigned showroom. It seeds currently visible server transactions silently so
  old rows are not announced again on speaker-capable clients.
- While the app is in the foreground, a scoped realtime payment event for any
  showroom in the user's current transaction scope triggers one debounced
  refresh of the current page, even when another OpsHub route is visible.
  Changing routes keeps the cached transaction list and the realtime monitor
  active; events for showrooms outside the current scope are ignored. The app
  does not poll the transaction list on a timer. Moving the app to the
  background keeps the cache but pauses new reads until it returns to the
  foreground. The app reconnects the realtime socket after disconnects. On
  Windows speaker-capable clients, a lightweight ready-notification fallback
  and the existing shared realtime socket continue while the app process is
  inactive, hidden, or minimized and the speaker remains eligible. They drain
  only the speaker backlog after realtime silence, but only for
  notifications still inside the short recovery window. This `/ready` fallback
  is separate from transaction-list refresh and never polls that list.
  Stream-pending notifications older than 30 seconds are recorded as not read
  and are never played later as delayed speaker backlog.
- Failed transaction refreshes apply bounded backoff. Realtime/fallback refresh
  cannot bypass that backoff; only an explicit user refresh or filter/page
  action may retry immediately. This prevents socket bursts from amplifying
  backend `429 Too Many Requests` responses.
- Each newly observed successful incoming transaction can be announced through
  generated audio as `Phong Vũ đã nhận: <amount> đồng.` when the signed-in
  user has both `PAYMENT_MONITOR` and the separate node feature
  `PAYMENT_SPEAKER` (`Đọc loa`) on a supported Windows PC, and the app is
  currently scoped to exactly one active showroom. Users assigned to many
  showrooms can view many-showroom transaction lists, but speaker polling,
  audio download, and ack stay tied to the selected active showroom. Piper
  audio uses speed `0.90`, no configured leading silence, and 500 ms of tail
  silence. The
  server-combined WAV reduces only the payment cue to `80%` amplitude, then
  appends the full TTS WAV immediately so there is no configured gap before the
  first spoken word. If combined audio is unavailable, the Windows local-cue
  fallback also plays the cue at `80%` while keeping voice playback at `100%`.
  The speaker card warns Windows operators to keep the machine awake and the
  screen on while using audio, because sleep/off-screen states can interrupt
  playback. Android, web, and other unsupported platforms do not start the
  speaker path.
- Turning off `Đọc loa tiền vào` mutes only the speaker path. The PC keeps
  syncing transactions from realtime/fallback refreshes, and muted
  notifications are recorded as `SILENCED` so they are not played later as
  backlog. Users with `PAYMENT_MONITOR` but without `PAYMENT_SPEAKER` keep the
  transaction list and realtime refreshes, but they do not poll ready audio,
  download audio, or acknowledge speaker events.
- QR payment confirmation checks stored MAP transactions first. If a matching
  stored transaction exists, the QR screen moves to the paid state and the PC
  monitor also announces that transaction. If no stored match exists yet, the
  existing direct MAP check remains a fallback.
- SUPER_ADMIN users choose the showroom to monitor. Other users are scoped by
  the backend to their active assignments; all-showroom views still require the
  matching explicit policy.
- The Super Admin header shows a compact speaker-speed KPI beside the global
  notification bell. It measures the last 24 hours from MAP first-seen time to
  the completed `PLAYED` acknowledgement, then compares that average with the
  previous 24 hours so operators can see whether speaker completion is faster or
  slower. Tapping the KPI opens a dialog with the latest 10-20 speaker delivery
  rows, including SR, amount, MAP first-seen time, `PLAYED` acknowledgement time,
  first-seen-to-played duration, and any latest playback failure status/message
  available for that notification. The backend also logs each completed playback
  acknowledgement with the measured duration and logs KPI/history load
  start/success/failure with sanitized context.
- New incoming transaction audio is delivered through backend-generated payment
  notifications. The backend stores notification/audit rows, optionally calls a
  server-side TTS service, publishes a scoped realtime event, and serves audio
  only through JWT-protected endpoints. Production uses Piper `vi-vais1000`
  through `TTS_VOICE_ID=piper:vi-vais1000`; the sidecar still accepts the
  legacy `custom:suong-vo` voice id for rollback-friendly deploys. The audio
  endpoint stays backward compatible: `GET /payment-notifications/:id/audio`
  still serves older/manual clients, including `includeCue=true` for one
  server-combined WAV or `rawAmount=true` for amount-only WAV. The current
  Windows speaker flow now downloads speaker audio only through
  `GET /payment-notifications/:id/stream`, while `/payment-notifications/ready`
  returns backlog metadata such as `audioUrl` and `streamUrl` instead of
  serving the active speaker path directly. The server caches the combined WAV
  beside the generated TTS file and deletes both during audio cleanup. If
  combined audio is unavailable, for example legacy MP3 audio or a missing cue
  WAV, the Windows client falls back to downloading TTS-only audio and playing
  the local `data/ting_ting.mp3` cue. Playback then attempts `media_kit` on
  Windows, Win32 `PlaySoundW` for WAV files, and MCI as the final fallback. If
  MCI returns error `326` for WAV audio, the client normalizes only that local
  temp file to `WAV PCM 16-bit mono 44100 Hz` and retries once without
  requesting a larger server audio payload. The Windows installer also runs a
  non-blocking audio preflight for `Audiosrv`, `AudioEndpointBuilder`, and
  WinMM output devices; missing service/device checks warn the user but do not
  block installation.
- When `PAYMENT_SPEAKER_STREAMING_ENABLED=true`, the backend creates the
  notification and publishes `PAYMENT_SPEAKER_STREAM` immediately, before
  blocking on server-side TTS generation. Windows speaker clients then request
  the stream endpoint for both realtime wake-up and backlog recovery, prefer
  `rawAmount=true` amount audio plus the bundled cue-prefix asset, and
  acknowledge `STREAM_STARTED` when playback is about to begin. The stream
  endpoint is still an authenticated audio file response, not chunked audio.
  Stream audio requests include the speaker `clientId`, and the backend records
  that stream open as an in-flight delivery claim before preparing audio. If
  the same `notificationId + clientId` already has a recent
  `DELIVERED`/`STREAM_STARTED` claim, the backend returns `409` so the client
  can treat the duplicate as a no-op instead of playing over itself. Normal
  ready polling remains only as backlog fallback on startup, manual refresh,
  realtime readiness, or realtime silence; while realtime stays silent the
  client checks every 5 seconds. It no longer downloads speaker audio through
  `/audio` directly. `/ready` recovers notifications only while they are newer
  than `PAYMENT_STREAM_PENDING_RECOVERY_WINDOW_SECONDS` (default `30`), whether
  their audio is `PENDING` or was already generated as `READY` by another
  client. Older pickup attempts are marked `SILENCED` with
  `stream_recovery_window_expired`, and `/stream` also rejects them so they
  cannot play late. Delivery metrics assign a notification to the time bucket
  containing its first-ever `STREAM_STARTED`; later clients cannot move the
  same notification into a newer bucket. The Windows client advances a local
  notification checkpoint
  and skips locally terminal, queued, or in-flight notification ids before
  playback, so repeated stream events and fallback ready checks cannot overlap
  the same transaction audio on one machine.
- When a speaker attempt fails, the client uploads `PaymentSpeaker` started /
  succeeded / failed logs with sanitized context and acknowledges
  `PLAYBACK_FAILED` for attempts 1-2. The client waits 10 seconds between
  attempts, reuses the same downloaded audio bytes across all 3 attempts, and
  acknowledges terminal `FAILED` only after attempt 3 still cannot play. Audio
  logs include sanitized WAV header fields, MCI code/message, WinMM output
  device count, and whether the local MCI-326 normalized fallback was used.
- Payment notification audio is cleaned after 7 days, delivery/app logs after
  30 days, and stored MAP transactions after 90 days by default.

## Bank Statement Reconciliation

- The app exposes the `Sao ke` home action when the resolved
  `BANK_STATEMENTS` feature is allowed. The `BANK_STATEMENT_ALL_SCOPE` policy
  can widen showroom scope after the feature is enabled, but cannot reopen the
  feature or its endpoints by itself.
- MAP sync extracts every valid order code from the transfer content. A valid
  order is an independent 14-digit number whose first 6 digits are a real
  `yymmdd` date. Duplicates are removed while preserving first-seen order; no
  match is stored as an empty order list.
- Sync does not overwrite a transaction whose order source is `MANUAL`, even
  when the manual value is cleared back to an empty list.
- Statement search does not auto-load transactions. Users must choose at least
  one effective filter, then run Search.
- Primary filters are mutually exclusive: showroom, statement number, order
  code, amount, and transfer content. Order status and date range can be used
  alone or combined with one primary filter.
- Showroom filtering follows effective statement scope: national users and
  users with `BANK_STATEMENT_ALL_SCOPE` can search all or multiple showrooms;
  assigned-showroom users can search one or more of their assigned showrooms.
  Statement number, order, amount, and transfer-content searches scan all
  stored statement accounts and are not limited by the user's assigned
  showroom. Date range, order status, and showroom searches without one of
  those global lookup filters remain limited to the user's statement scope.
- Statement number filter is an exact match against the user-facing statement
  reference shown in `Sao ke`, falling back to the MAP transaction number when
  no statement reference exists. Order filter is an exact match against any
  stored order in the transaction. Amount filter is exact integer amount.
  Content filter is case-insensitive contains matching for search; cross-SR
  order editing requires the normalized content to match the transaction
  content exactly.
- When a statement search is run without a selected date range, the app sends
  the latest 30 Vietnam-local days by default. This keeps broad lookups such as
  order code, statement number, amount, and transfer content inside a recent
  window instead of scanning all stored history.
- The statement date-range control is a shared dropdown and keeps `Tất cả ngày`
  as the empty state. When no explicit range is selected, the UI shows a small
  helper note that the search/export will default to the latest 30 days. A
  custom date range must include both start and end dates; an incomplete range
  is treated as no explicit range. Manual date entry uses `dd/mm/yyyy` with
  `/` inserted while typing.
- `Đã có đơn hàng` means the stored order list is not empty.
  `Chưa có đơn hàng` means the order list is empty.
  `Chờ xác nhận` means the transaction has a pending ACC order-transfer
  request. `Giao dịch cấn trừ` means ACC approved an order-transfer request and
  the transaction order source is `OFFSET`.
- From Home `Tài chính`, clicking the text of `Tổng sao kê chưa có đơn hàng`
  opens `/bank-statement?orderStatus=MISSING_ORDER&autoSearch=true`, applies
  the `Chưa có đơn hàng` filter, and searches immediately within the user's
  statement scope. The `Sao kê` screen starts directly at the filter/list
  workspace; it no longer shows the old header card titled
  `Giao dịch cần rà soát`.
- Statement rows show transaction details beside a compact order area. The row
  summary uses short readable pills for payment source, SR code, amount, and
  successful transfer status, not the raw MAP API status; the current payment
  source label is `VietinBank`. Users can edit orders inline only while the
  stored order list is `NULL`; protected rows that already have an AUTO or
  MANUAL order can be changed by `SUPER_ADMIN`, users in the `FIN_ACC`
  organization/department, or a statement user who found that exact row through
  one primary global lookup field: statement number, order code, exact amount,
  or exact transfer content. That verified lookup also allows updating a row
  that belongs to a different SR, while date/status/showroom-only searches keep
  edit actions limited to the user's assigned statement scope. Users enter
  multiple orders one per line or separated by comma/semicolon/whitespace,
  save/cancel in place, and see a short per-row success or failure message.
- Payment Monitor and Sao ke action requests use the persisted OpsHub statement
  id as the primary identity and include the stable transaction key as a
  fallback. If MAP/eFAST deduplication replaces a row id between list load and
  submit, the backend resolves the current row by that key before re-checking
  showroom scope, cutoff, pending-request, and edit permissions.
- Users who can view a statement transaction can request an order update for
  that transaction only while it is still the same Vietnam-local calendar day
  as `paidAt ?? firstSeenAt`. After 00:00 UTC+7, the app disables the update
  action with `Quá thời hạn cập nhật trong ngày. Vui lòng dùng chức năng Cấn
  trừ.`, the backend rejects the same request, and stale pending requests are
  moved to `EXPIRED` so rows no longer show `Chờ xác nhận`. The separate
  after-day-close `Cấn trừ` flow is handled by the dedicated offset adjustment
  contract.
- Only one order-transfer request may be pending for a transaction. Pending
  rows use a yellow border and show the requested order codes as `Chờ ACC xác
  nhận`. ACC approval is available to `SUPER_ADMIN` and users in `FIN_ACC` or
  `ACC` through department or organization-node code/businessCode. Approval
  replaces the transaction orders with the requested orders, sets order source
  `OFFSET`, writes the order audit, and shows a small `Đã cấn trừ` tag beside
  `Đơn hàng`; rejection leaves the current orders unchanged and may include an
  optional reviewer note.
- Statement users see a generic `Thông báo` bell. Reviewers see pending
  order-transfer requests in their statement scope; requesters see their own
  pending/rejected requests. Each notification names the notification type and
  shows transaction time, request time, current/requested orders, and rejection
  reason/instructions when rejected. The realtime event carries sanitized ids,
  showroom/status/timestamp, and recipient id for requester notifications; the
  client reloads details through the scoped API before showing actions.
- Statement rows include the MAP payer name/account when available. Tapping the
  transaction summary opens a selectable detail dialog with payer, payment,
  showroom, order, manual-edit metadata, and OpsHub first-seen information;
  checkbox selection and inline order actions remain separate controls.
- Manual order edits write an audit row with old orders, new orders, editor id,
  editor email, source, and timestamp. The history icon opens these audit rows;
  automatic MAP extraction is not shown as a manual edit.
- XLSX export exports MAP `rawData.txnReference` under the `Sao kê` column,
  preserves long numeric identifiers such as statement references, transaction
  numbers, order codes, and payer accounts as text, and formats transaction
  timestamps in Vietnam local time. It includes `Loại giao dịch` and `Tài khoản
  nhận`; when a transaction has multiple orders, the order-code cell exports
  one code per line. Statement
  search uses server-side paging, while selected transaction ids stay selected
  when users move between pages and take precedence during export. If nothing is
  selected, export includes every row matching the current filter/date/status,
  not just the visible page. XLSX export is limited to a date span of 31 days; a
  longer selected range is blocked before the export request is sent.
- `Sao ke` keeps header, filters, selection bar, and export controls fixed while
  only the transaction list scrolls. The page allows selecting and copying text.
- `Sao ke` and `Tien vao` cards use a yellow border while an order-transfer
  request is pending, otherwise green when the transaction has at least one
  stored order and red when the order list is empty. In `Tien vao`, users who
  also have `Sao ke` permission can edit empty orders, request Kế toán
  confirmation for protected rows, review pending requests when eligible, and
  open the order history directly from the row.

## Payment Confirmation Research

Bank-web confirmation is possible only as a separate reconciliation feature
after the bank portal is identified and approved for automation. Current
research against VietinBank MAP merchant transaction payment page shows a
searchable transaction list with filters for amount, transaction code, date
range, status, and a `Tải kết quả` export action.

Preferred paths, from safest to riskiest:

1. Manual confirmation after staff checks the bank portal.
2. Backend MAP transaction search for configured showroom credentials, matching
   by amount, transfer content, success status, and transaction time window.
3. Bank-web export reconciliation from the MAP page, matching by amount,
   transfer content, success status, and transaction time window.
4. Controlled browser automation against the bank portal, with no plaintext
   credential storage, audit logging, and a fallback manual flow because bank
   UI, OTP, or session rules can break automation.

## Backend Configuration

The NestJS API expects these values when `POST /vietqr` is used:

- `VIETQR_BANK_BIN`
- `VIETQR_ACCOUNT_NUMBER`
- `VIETQR_ACCOUNT_NAME`
- `VIETQR_MERCHANT_CITY`
- `VIETQR_EXTERNAL_API_KEY` for `/vietqr/n8n` and `/vietqr/n8n/image`
- `VIETQR_AUTO_RECONCILE_ENABLED=false` optionally pauses the background
  DB-only VietQR reconciliation job.
- `VIETQR_AUTO_RECONCILE_BATCH_SIZE` optionally overrides the default 100
  pending intents processed per 5-second reconcile tick.
- `VIETQR_LOGO_PATH` optionally points image rendering to a logo file when the
  backend process cannot see the repo app icon path.
- `VIETQR_ACARE_LOGO_PATH` optionally points ACareTek image rendering to a logo
  file when the backend process cannot see `assets/icon/acare_logo.png`.

Missing config does not block backend startup, but the VietQR endpoint returns a
clear service-unavailable error until the config is present.

## n8n VietQR API

- `GET /vietqr/n8n` or `POST /vietqr/n8n` returns JSON fields for n8n,
  including `paymentId`, bank/account fields, `amount`, `transferContent`,
  `qrPayload`, `qrBrand`, `imageMimeType`, `imageFileName`, `imageBase64`, and
  `imageDataUrl`.
- `GET /vietqr/n8n/image` returns the PNG directly and includes the transfer
  details plus `X-OpsHub-Brand-Key` and `X-OpsHub-Brand-Title` in `X-OpsHub-*`
  response headers.
- Inputs may use app-style fields (`amount`, `orderCode`, `storeCode`) or the
  current n8n quick-link content field (`addInfo`). When `addInfo` or
  `transferContent` is sent, OpsHub uses that exact normalized content instead
  of appending `{STORE_CODE} BOT` again.
- n8n should prefer the header key path. Query keys are accepted only to keep
  quick-link style calls possible, and request logs strip query strings.
- n8n does not need to poll MAP. It can read `/vietqr/n8n/status` for the stored
  payment intent status, while the backend background job keeps `PENDING`,
  `PAID`, `AMBIGUOUS`, and `FAILED` current from OpsHub's synced MAP DB table.

## MAP Reconciliation Configuration

Showroom MAP username and password are configured in admin store management.
The backend encrypts the password and exposes only `hasMapVietinPassword`.
Optional MAP endpoint overrides are available through:

- `MAP_VIETIN_CREDENTIAL_SECRET`
- `MAP_VIETIN_GLOBAL_USERNAME`
- `MAP_VIETIN_GLOBAL_PASSWORD`
- `MAP_VIETIN_GLOBAL_SYNC_ENABLED`
- `MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES` (deep-sweep cap, default `2`)
- `MAP_VIETIN_GLOBAL_SESSION_TTL_SECONDS`
- `MAP_VIETIN_SYNC_DELAY_MIN_MS` (default `1000`, minimum `500`)
- `MAP_VIETIN_SYNC_DELAY_MAX_MS` (default `2000`, clamped to the minimum)
- `MAP_VIETIN_DEEP_SWEEP_DELAY_MIN_MS` (default/minimum `30000`)
- `MAP_VIETIN_DEEP_SWEEP_DELAY_MAX_MS` (default `60000`)
- `MAP_VIETIN_RATE_LIMIT_BACKOFF_BASE_MS` (default/minimum `30000`)
- `MAP_VIETIN_RATE_LIMIT_BACKOFF_MAX_MS` (default `120000`, at least the base)
- `MAP_VIETIN_FORBIDDEN_BACKOFF_MS` (default/minimum `300000`)
- `MAP_VIETIN_SYNC_FINGERPRINT_CACHE_TTL_MS` (default `300000`)
- `MAP_VIETIN_SYNC_FINGERPRINT_CACHE_MAX_ENTRIES` (default `20000`, max `100000`)
- `MAP_VIETIN_CLIENT_ID`
- `MAP_VIETIN_SIGNATURE_KEY`
- `MAP_VIETIN_NO_AUTH_BASE_URL`
- `MAP_VIETIN_TRANSACTION_BASE_URL`
- `MAP_VIETIN_LOGIN_IP`
- `VIETIN_EFAST_SYNC_ENABLED` (default `false`; optional secondary eFAST source)
- `VIETIN_EFAST_USERNAME`
- `VIETIN_EFAST_PASSWORD`
- `VIETIN_EFAST_BANK_ACCOUNTS` (comma-separated account numbers, currently two)
- `VIETIN_EFAST_CIFNO` (optional when the login can choose multiple enterprises)
- `VIETIN_EFAST_DEVICE_ID` (optional stable device id for eFAST login)
- `VIETIN_EFAST_BASE_URL`
- `VIETIN_EFAST_ACCOUNT_DETAIL_PATH`
- `VIETIN_EFAST_PAGE_SIZE` (default `150`)
- `VIETIN_EFAST_SYNC_MAX_PAGES` (default and maximum `1`)
- `VIETIN_EFAST_SESSION_TTL_SECONDS` (default `600`)

When enabled, the eFAST adapter logs in through `/api/v1/account/login`, reads
`/api/v1/account/history` for credit rows only, and maps each row `pmtId` to
`Store.transferAccountNumber`. If `pmtId` is missing or unmapped, the configured
eFAST history account is the fallback receiving-account identity. eFAST history
queries use the Vietnam business date (UTC+7). MAP and eFAST first check all
stored statement identifiers before inserting. When the providers expose
unrelated identifiers for the same bank row, ingestion falls back to an exact
cross-source fingerprint: same mapped showroom, amount, bank timestamp, and
stored transfer content. The fallback never merges two rows from the same
source. This prevents duplicate rows and payment notifications whether MAP or
eFAST arrives first, including near-simultaneous responses. For user-facing
`Mã sao kê` fields, API responses, XLSX exports, and stored VietQR confirmations
use eFAST `trxId`, even when the retained database row originally came from
MAP. The survivor stores MAP `transactionNumber`, eFAST `trxId`, and eFAST
`trxRefNo` under namespaced provider identifiers; search accepts all three,
while only `trxId` is product-facing. The numeric
eFAST `trxRefNo` remains technical raw/audit data. Rows with a
missing `pmtId` are stored with `storeCode=null` only when neither the virtual
account nor source account identifies a unique showroom;
Super Admin, Finance-node users, and `phongvu.vn` users can review them. A
scoped user who finds one of these rows by statement number, order, amount, or
transfer content can update the order code, and the backend assigns that
transaction to the user's showroom. Creating or changing a showroom receiving
account immediately backfills matching unassigned eFAST rows without
overwriting rows already assigned manually. Every eFAST sync reloads the store
account index, repairs any remaining unassigned matches, and applies the same
fallback to new transactions. Rows with an unmapped or ambiguous account stay
in the unmapped-transaction quarantine and do not trigger payment audio.

The one-time production cleanup for rows created before the symmetric de-dupe
keeps MAP, preserves protected order audit and notification delivery evidence
on the retained transaction, then removes the duplicate eFAST transaction and
notification. Subsequent syncs must not overwrite orders whose `orderSource` is
`MANUAL` or an approved `OFFSET`.
The eFAST scheduler is separate from the MAP scheduler: it runs once every
random 50-60 seconds from 08:00 through 22:00 Vietnam time (UTC+7), and every
30 minutes from 22:01 through 07:59 the next day. Production should keep two
configured eFAST bank accounts, `VIETIN_EFAST_PAGE_SIZE=150`, and
`VIETIN_EFAST_SYNC_MAX_PAGES=1`.

## Sao kê income type

Sao kê exports use `.xlsx` and include both `Loại giao dịch` and `Tài khoản
nhận`. The backend stores `incomeType` as `SALES` (`Bán hàng`) or
`PARTNER_INTERNAL` (`Đối tác/Nội bộ`). Before matching, the classifier only
uppercases the content and removes whitespace. A row is automatically marked
`Đối tác/Nội bộ` when the compact content starts with `BCCN`, `BCCP`, `BCCTY`,
or `BCDKKD`; contains one of `NHATTIN`, `VNPAYTT217344`, `SHOPEEPAYMS`,
`SHOPEEWSSSELLERWITHDRAWAL`, `GIAOHANGTIETKIEMCHUYENTIENCOD`,
`TTGDQUAVIZALOPAY`, or `DIEUTIENTUDONG`; or its compact content starts with
`TNG`. The TNG rule does not depend on the mapped store or subsequent wording.
The row is also
`Đối tác/Nội bộ` when its normalized payer account is `8637988888`,
`0302607125`, `113000179095`, `110600994666`, `1011103131001`,
`0071001142275`, or `117601180666`. No accent, punctuation, or other broad
content normalization is applied. Generic `VNPAY`, `So GD goc`, `CT DEN`, and
numeric-only content remain sales unless another exact rule matches. The
migration backfills existing rows with this same rule set.

Income type is an additional backend visibility boundary after the existing
organization/showroom scope. Only users belonging to `FIN_ACC` can list, search,
or export both types; every other user is constrained to `SALES`, including
global lookup and selected-row export. Only `FIN_ACC` can change the type from
the Vietnamese pill. A manual choice is stored with `incomeTypeSource=MANUAL`
and must survive later MAP/eFAST syncs; automatic rows remain `AUTO`. On mobile,
a successful `Tìm` action closes the filter panel so the result list is visible.
