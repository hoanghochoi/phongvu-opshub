# VIETQR-001 Create Transfer QR

## Scope

Add a dedicated VietQR screen that creates a manual bank-transfer QR for a
customer to scan. The QR is generated from backend-owned account configuration,
optional amount, optional transfer content, and the signed-in user's store code.

## Acceptance Criteria

- Home screen exposes a VietQR entry point.
- Staff can enter amount and order content, or leave either field blank so the
  payer can fill it in inside their banking app.
- Staff can use non-order-number transfer content, not only 14-digit order
  numbers.
- Store code and transfer content are read-only in the UI.
- Backend returns a VietQR EMV payload plus account display fields.
- Backend omits amount/content EMV fields when staff leaves them blank.
- Flutter renders the QR image from the backend payload.
- n8n can call OpsHub with a dedicated VietQR API key and receive transfer
  details plus a server-rendered PNG matching the app export layout.
- Backend stores each QR as a payment intent.
- `SUPER_ADMIN` can choose any showroom from the full showroom list; other
  users remain scoped to assigned showrooms.
- The QR result screen automatically checks payment status when amount and
  transfer content are fixed; staff can also run an immediate manual check.
- Each QR expires 15 minutes after creation. Expired QRs remain in history but
  cannot be reopened.
- On desktop, the screen splits into a left creation/result column and a right
  QR history column. The history column shows status and only reopens
  still-valid QRs.
- After confirmation, the QR is replaced by a green success state that shows
  available MAP transaction details such as payer, received amount, transfer
  content, transaction number, and transaction time.
- Payment confirmation marks `PAID` only when exactly one successful MAP
  transaction matches amount, transfer content contained in MAP transaction
  content, and Vietnam-local transaction time after QR creation.
- Missing amount/content, no match, or multiple matches remain unconfirmed and
  require manual review.
- MAP payment monitoring fetches page 1 every 1-2 seconds in the fast window;
  page 2 is recovered by a 30-60-second deep sweep and immediately after backend
  startup or MAP session refresh.
- MAP HTTP 429 responses use bounded exponential backoff; a persistent HTTP 403
  after one session refresh pauses polling for 5 minutes before retrying.

## Validation

- Flutter: `flutter analyze`, `flutter test`.
- NestJS: `npm run build`, `npm test -- --runInBand`.
- Focused n8n API proof: `npm test -- --runInBand src/vietqr/vietqr.controller.spec.ts src/vietqr/vietqr.service.spec.ts`.
- Scheduler proof covers page-1 fast loops, startup/session-recovery deep sweeps,
  and 429/403 backoff timers.
