# 0002 VietQR Payment Confirmation

## Status

Accepted, first backend probe implemented

## Context

OpsHub can generate VietQR payloads, but the bank does not provide a confirmed
transaction API for the app yet. Staff may still need a way to confirm payment
after showing a QR to the customer.

## Decision

Do not store bank credentials or automate bank-web login in the mobile app.
Treat automatic bank-web checking as a separate backend reconciliation service,
not part of QR generation.

The current MAP payment transaction page supports search filters and a
`Tải kết quả` export action. The Codex in-app browser cannot download files, so
future implementation should verify the export endpoint with a normal browser
or Playwright-driven browser context that can run headless on the VPS.

Opening the observed search URL directly returns `401 - Unauthorized` with an
invalid client id/secret message, so cookie login alone is not enough. A
headless worker must either replay the same headers/client credentials produced
by the MAP web app or drive the web UI in a browser context and capture the
authorized request.

Current research shows MAP login can be replayed through
`POST /vtb/public/map/api/ma/no-auth/login` with a SHA-256 password, `ClientId`,
and request `Signature`. After login, the default `merchant_id` and
`access_token` can be used to call:

```text
POST /vtb/public/map/api/rpt-txnmng/api/ma/payment-transaction/search?page=0&size=20&sort=txnDate,desc
```

Required search headers are `Authorization: Bearer <token>`, `ClientId`,
`merchantId`, and `x-lang: vi`. OpsHub stores MAP credentials encrypted per
showroom and never returns the password or token through its API.

## Options

- Manual confirmation: staff checks the bank portal and marks the QR as paid.
- MAP export reconciliation: staff signs in to VietinBank MAP, uses the
  transaction payment page search/export flow, then OpsHub matches by amount,
  account, transfer content, success status, and time window.
- Browser automation: a server-side worker signs in to the bank portal and
  reads or exports transactions. This needs encrypted secrets, audit logs,
  manual fallback, and explicit approval because bank UIs can change or block
  automation.
- Direct MAP replay: the backend signs in through the same public API used by
  the MAP web app and searches transactions with the returned token. This is
  lower overhead than browser automation but still depends on VietinBank's
  private web contract.

## Consequences

QR generation remains low-risk and usable without bank credentials. The backend
stores each generated QR as a payment intent and can mark it `PAID` only when
exactly one successful MAP transaction matches fixed amount, transfer
content contained in MAP transaction content, and transaction time after QR
creation. MAP `dd/MM/yyyy HH:mm:ss` timestamps are interpreted as Vietnam local
time before comparing with the UTC payment intent timestamp. The Flutter QR
result screen polls this backend confirmation while it is open so staff do not
have to tap manually. Once confirmed, OpsHub persists and returns non-secret
matched transaction display details from MAP, including payer, amount, transfer
content, transaction number, and transaction time when those fields are present.
Missing amount/content, no match, or multiple matches remain unconfirmed and
require manual review.
