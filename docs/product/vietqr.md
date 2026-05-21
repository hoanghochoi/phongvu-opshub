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
- The monitor is independent from OpsHub-created QR/payment intents. It reads
  all successful incoming VietinBank MAP transactions stored for the selected
  showroom, not only transfers that match an OpsHub QR.
- The Windows app starts the monitor after sign-in when the account has a
  showroom scope. It seeds currently visible server transactions silently so old
  rows are not announced again.
- While the app is running, the PC polls OpsHub every 5 seconds. Each newly
  observed successful incoming transaction is announced through the Windows
  speech engine as `Đã nhận <amount> đồng`.
- QR payment confirmation checks stored MAP transactions first. If a matching
  stored transaction exists, the QR screen moves to the paid state and the PC
  monitor also announces that transaction. If no stored match exists yet, the
  existing direct MAP check remains a fallback.
- SUPER_ADMIN users choose the showroom to monitor. Other users are scoped by
  the backend to their assigned showroom.

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
- `MAP_VIETIN_CLIENT_ID`
- `MAP_VIETIN_SIGNATURE_KEY`
- `MAP_VIETIN_NO_AUTH_BASE_URL`
- `MAP_VIETIN_TRANSACTION_BASE_URL`
- `MAP_VIETIN_LOGIN_IP`
