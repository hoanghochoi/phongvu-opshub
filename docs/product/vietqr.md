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

- The app exposes a `Tiền vào` home action for users with `PAYMENT_MONITOR` on
  supported non-web clients, including Android and Windows. Mobile clients show
  the stored transaction list without enabling the speaker path.
- The NestJS API is the source of truth for MAP transactions. It polls
  configured showroom MAP accounts in the background, stores successful incoming
  transactions in Postgres, and exposes the stored list to scoped clients.
- When a global MAP account is configured, the backend uses that account as the
  primary payment sync source, maps each MAP `virtualAccount` to
  `Store.transferAccountNumber`, and stores the transaction under the matched
  showroom. Per-showroom MAP credentials remain a fallback when global sync is
  disabled or not configured. Global sync reads 100 MAP rows per page and
  defaults to 2 pages per sync loop. After each backend MAP-history fetch
  finishes, the backend waits a random 3000-5000ms before starting the next
  scheduled fetch during the 07:00-to-before-22:00 Vietnam-time fast window.
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
- While the app is running, the PC listens for scoped realtime payment events
  and refreshes stored transactions when a new notification arrives. A
  30-second fallback refresh remains active so the list can recover from missed
  socket events.
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
  Mobile and other unsupported platforms do not start the speaker path by
  default.
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
  returns TTS-only audio for older clients, while new clients request
  `includeCue=true` to receive one server-combined WAV containing the payment
  cue followed by the full TTS WAV, including Piper's leading and tail silence.
  The server caches the combined WAV beside the generated TTS file and deletes
  both during audio cleanup. If combined audio is
  unavailable, for example legacy MP3 audio or a missing cue WAV, the Windows
  client falls back to downloading TTS-only audio and playing the local
  `data/ting_ting.mp3` cue. Playback then attempts `media_kit` on Windows,
  Win32 `PlaySoundW` for WAV files, and MCI as the final fallback. If MCI
  returns error `326` for WAV audio, the client normalizes only that local temp
  file to `WAV PCM 16-bit mono 44100 Hz` and retries once without requesting a
  larger server audio payload. The Windows installer also runs a non-blocking
  audio preflight for `Audiosrv`, `AudioEndpointBuilder`, and WinMM output
  devices; missing service/device checks warn the user but do not block
  installation.
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
  `BANK_STATEMENTS` feature is allowed or the user has the
  `BANK_STATEMENT_ALL_SCOPE` policy. The NestJS feature guard and statement
  endpoints apply the same fallback, so a finance user can receive national
  statement access without also receiving unrelated manager capabilities.
- MAP sync extracts every valid order code from the transfer content. A valid
  order is an independent 14-digit number whose first 6 digits are a real
  `yymmdd` date. Duplicates are removed while preserving first-seen order; no
  match is stored as an empty order list.
- Sync does not overwrite a transaction whose order source is `MANUAL`, even
  when the manual value is cleared back to an empty list.
- Statement search does not auto-load transactions. Users must choose at least
  one effective filter, then run Search.
- Primary filters are mutually exclusive: showroom, order code, amount, and
  transfer content. Order status and date range can be used alone or combined
  with one primary filter.
- Showroom filtering follows effective statement scope: national users and
  users with `BANK_STATEMENT_ALL_SCOPE` can search all or multiple showrooms;
  assigned-showroom users can search one or more of their assigned showrooms.
  Order, amount, and content filters are allowed across the user's statement
  scope.
- Order filter is an exact match against any stored order in the transaction.
  Amount filter is exact integer amount. Content filter is case-insensitive
  contains matching.
- When a statement search is run without a selected date range, the app sends
  today's Vietnam-local date as both start and end date. SR searches therefore
  load the full snapshot for the current day instead of scanning all stored
  history.
- The statement date-range control is a shared dropdown and shows `Hôm nay`
  when no explicit range is selected. A custom date range must include both
  start and end dates; an incomplete range is treated as no explicit range.
  Manual date entry uses `dd/mm/yyyy` with `/` inserted while typing.
- `Đã có đơn hàng` means the stored order list is not empty.
  `Chưa có đơn hàng` means the order list is empty.
  `Chờ xác nhận` means the transaction has a pending ACC order-transfer
  request. `Giao dịch cấn trừ` means ACC approved an order-transfer request and
  the transaction order source is `OFFSET`.
- Statement rows show transaction details beside a compact order area. The row
  summary uses short readable pills for payment source, SR code, amount, and
  successful transfer status, not the raw MAP API status; the current payment
  source label is `VietinBank`. Users can edit orders inline only while the
  stored order list is `NULL`; protected rows that already have an AUTO or
  MANUAL order can be changed only by `SUPER_ADMIN` or users in the `FIN_ACC`
  organization/department. Users enter multiple orders one per line or
  separated by comma/semicolon/whitespace, save/cancel in place, and see a
  short per-row success or failure message.
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
- CSV export returns UTF-8 with BOM for Excel, exports MAP
  `rawData.txnReference` under the `Sao kê` column, preserves long numeric
  identifiers such as statement references, transaction numbers, order codes,
  and payer accounts as text, and formats transaction timestamps in Vietnam
  local time. When a transaction has multiple orders, the order-code CSV cell
  exports one code per line. Statement
  search uses server-side paging, while selected transaction ids stay selected
  when users move between pages and take precedence during export. If nothing is
  selected, export includes every row matching the current filter/date/status,
  not just the visible page. CSV export is limited to a date span of 31 days; a
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
- `MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES` (default `2`)
- `MAP_VIETIN_GLOBAL_SESSION_TTL_SECONDS`
- `MAP_VIETIN_CLIENT_ID`
- `MAP_VIETIN_SIGNATURE_KEY`
- `MAP_VIETIN_NO_AUTH_BASE_URL`
- `MAP_VIETIN_TRANSACTION_BASE_URL`
- `MAP_VIETIN_LOGIN_IP`
