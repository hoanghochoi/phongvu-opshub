# VietQR

OpsHub supports a dedicated mobile screen for staff to create a transfer QR for
a customer to scan and pay manually.

## Contract

- Staff opens the VietQR screen from the home feature list.
- Staff enters the transfer amount and order code.
- The app reads the store code from the signed-in user session and keeps it
  read-only.
- Transfer content is generated as `{STORE_CODE}-{ORDER_CODE}` and is read-only.
- The Flutter app requests VietQR data from the NestJS API and renders the QR
  image locally from the returned EMV payload.
- The backend owns the bank BIN, account number, account name, and merchant
  city through environment configuration.
- OpsHub does not confirm payment status, poll bank transactions, or mark an
  order as paid.

## Backend Configuration

The NestJS API expects these values when `POST /vietqr` is used:

- `VIETQR_BANK_BIN`
- `VIETQR_ACCOUNT_NUMBER`
- `VIETQR_ACCOUNT_NAME`
- `VIETQR_MERCHANT_CITY`

Missing config does not block backend startup, but the VietQR endpoint returns a
clear service-unavailable error until the config is present.
