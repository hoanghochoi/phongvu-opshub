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
- Backend stores each QR as a payment intent.
- The QR result screen automatically checks payment status when amount and
  transfer content are fixed; staff can also run an immediate manual check.
- After confirmation, the QR is replaced by a green success state that shows
  available MAP transaction details such as payer, received amount, transfer
  content, transaction number, and transaction time.
- Payment confirmation marks `PAID` only when exactly one successful MAP
  transaction matches amount, transfer content contained in MAP transaction
  content, and Vietnam-local transaction time after QR creation.
- Missing amount/content, no match, or multiple matches remain unconfirmed and
  require manual review.

## Validation

- Flutter: `flutter analyze`, `flutter test`.
- NestJS: `npm run build`, `npm test -- --runInBand`.
