# VIETQR-001 Create Transfer QR

## Scope

Add a dedicated VietQR screen that creates a manual bank-transfer QR for a
customer to scan. The QR is generated from backend-owned account configuration,
amount, order code, and the signed-in user's store code.

## Acceptance Criteria

- Home screen exposes a VietQR entry point.
- Staff can enter amount and order code.
- Store code and transfer content are read-only in the UI.
- Backend returns a VietQR EMV payload plus account display fields.
- Flutter renders the QR image from the backend payload.
- No automatic payment confirmation is introduced.

## Validation

- Flutter: `flutter analyze`, `flutter test`.
- NestJS: `npm run build`, `npm test -- --runInBand`.
