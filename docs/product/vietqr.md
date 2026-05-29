# VietQR

OpsHub supports a dedicated mobile screen for staff to create a transfer QR for
a customer to scan and pay manually.

## Contract

- Staff opens the VietQR screen from the home feature list.
- Staff may enter a fixed transfer amount, or leave the amount blank so the
  payer's banking app can fill it in.
- Staff may enter an order code or other transfer content. This field may also
  be left blank so the payer can fill in the transfer content.
- The app reads the store code from the signed-in user session and keeps it
  read-only.
- When staff enters transfer content, the final content is generated as
  `{CONTENT} {STORE_CODE} BOT` and is read-only in the preview.
- When amount or transfer content is blank, the backend omits the matching EMV
  field from the QR payload instead of encoding an empty value.
- The Flutter app requests VietQR data from the NestJS API and renders the QR
  image locally from the returned EMV payload.
- The backend owns the bank BIN, account number, account name, and merchant
  city through environment configuration.
- Admin backend can probe VietinBank MAP payment transactions for a configured
  showroom so the next reconciliation step can match by amount, transfer
  content, success status, and time window.
- Each generated QR is stored as a payment intent so staff can run payment
  confirmation after showing the QR to the customer.
- The QR result screen automatically checks payment status while the screen is
  open when amount and transfer content are fixed. Staff can also tap `Kiểm tra
  ngay` to run the same check immediately.
- Once payment is confirmed, the app hides the QR and shows a green success
  state with MAP transaction details when available: payer, received amount,
  transfer content, transaction number, and transaction time.
- Payment confirmation marks the intent as `PAID` only when exactly one
  VietinBank MAP transaction matches fixed amount, transfer content contained
  in the MAP transfer content, successful transaction status, and transaction
  time after QR creation. MAP transaction timestamps are interpreted as Vietnam
  local time. Missing amount/content, no match, or multiple matches remain
  unconfirmed and require manual review.

## PC Payment Monitor

- The Windows PC app exposes a `Tiền vào` home action.
- The NestJS API is the source of truth for MAP transactions. It polls
  configured showroom MAP accounts in the background, stores successful incoming
  transactions in Postgres, and exposes the stored list to scoped clients.
- When a global MAP account is configured, the backend uses that account as the
  primary payment sync source, maps each MAP `virtualAccount` to
  `Store.transferAccountNumber`, and stores the transaction under the matched
  showroom. Per-showroom MAP credentials remain a fallback when global sync is
  disabled or not configured. Global sync reads 100 MAP rows per page and
  defaults to 2 pages per sync loop. Background MAP sync runs only from
  08:00 to before 22:00 Vietnam time each day.
- Successful global MAP rows that cannot be mapped to exactly one showroom are
  quarantined for debug and do not create payment notifications or play audio.
- The monitor is independent from OpsHub-created QR/payment intents. It reads
  all successful incoming VietinBank MAP transactions stored for the selected
  showroom, not only transfers that match an OpsHub QR.
- The monitor transaction list can be filtered by a Vietnam-local date range,
  for example 23-27/05, and remains paginated by the selected row count.
- The Windows app starts the monitor after sign-in when the account has a
  showroom scope. It seeds currently visible server transactions silently so old
  rows are not announced again.
- While the app is running, the PC polls OpsHub every 5 seconds. Each newly
  observed successful incoming transaction is announced through generated audio
  as `Phong Vũ đã nhận: <amount> đồng`.
- Turning off `Đọc thông báo tiền vào` mutes only the speaker path. The PC keeps
  polling/syncing transactions every 5 seconds, and muted notifications are
  recorded as `SILENCED` so they are not played later as backlog.
- QR payment confirmation checks stored MAP transactions first. If a matching
  stored transaction exists, the QR screen moves to the paid state and the PC
  monitor also announces that transaction. If no stored match exists yet, the
  existing direct MAP check remains a fallback.
- SUPER_ADMIN users choose the showroom to monitor. Other users are scoped by
  the backend to their assigned showroom.
- New incoming transaction audio is delivered through backend-generated payment
  notifications. The backend stores notification/audit rows, optionally calls a
  server-side TTS service, publishes a scoped realtime event, and serves audio
  only through JWT-protected endpoints. Production uses Piper `vi-vais1000`
  through `TTS_VOICE_ID=piper:vi-vais1000`; the sidecar still accepts the
  legacy `custom:suong-vo` voice id for rollback-friendly deploys. The Windows
  app plays `data/ting ting.mp3` before the generated audio, then falls back to
  local Windows speech if the server audio is unavailable.
- Payment notification audio is cleaned after 7 days, delivery/app logs after
  30 days, and stored MAP transactions after 90 days by default.

## Bank Statement Reconciliation

- The Windows PC app exposes a `Sao ke` home action for MANAGER and
  SUPER_ADMIN users. The NestJS API enforces the same role gate on statement
  list, export, inline order update, and order-history endpoints.
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
- Showroom filtering follows V1 scope: national users can search all or
  multiple showrooms; showroom-scoped users can search only their own showroom.
  Order, amount, and content filters are allowed across the user's statement
  scope.
- Order filter is an exact match against any stored order in the transaction.
  Amount filter is exact integer amount. Content filter is case-insensitive
  contains matching.
- `Da co don hang` means the stored order list is not empty. `Chua co don hang`
  means the order list is empty.
- Statement rows show transaction details beside a compact order area. Users can
  edit orders inline, enter multiple orders separated by whitespace, comma, or
  semicolon, save/cancel in place, and see a short per-row success or failure
  message.
- Manual order edits write an audit row with old orders, new orders, editor id,
  editor email, source, and timestamp. The history icon opens these audit rows;
  automatic MAP extraction is not shown as a manual edit.
- CSV export returns UTF-8 with BOM. Selected transaction ids take precedence;
  if nothing is selected, export includes every row matching the current
  filter/date/status, not just the visible page.
- `Sao ke` keeps header, filters, selection bar, and export controls fixed while
  only the transaction list scrolls. The page allows selecting and copying text.
- `Sao ke` and `Tien vao` cards use a green border when the transaction has at
  least one stored order and a red border when the order list is empty. `Tien
  vao` uses the order list only for the border and does not display order codes.

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

Missing config does not block backend startup, but the VietQR endpoint returns a
clear service-unavailable error until the config is present.

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
