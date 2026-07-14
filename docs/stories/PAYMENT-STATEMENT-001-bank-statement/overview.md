# PAYMENT-STATEMENT-001 Bank Statement Reconciliation

## Status

implemented

## Risk Reason

This is high-risk because it changes Prisma schema and migrations, MAP sync
normalization, admin API contracts, role/scope enforcement, CSV export, audit
history, and two Flutter payment screens.

## Product Contract

Add a `Sao ke` workflow for MAP transactions where the transfer content may not
contain an order code. The feature stores every valid extracted order code,
allows manual inline order correction with audit history, supports scoped search
and CSV export, and marks transactions visually by whether an order is present.
User-facing statement numbers use the MAP statement reference; stored eFAST rows
must expose their matching `trxId`, while `trxRefNo` stays technical audit data.

## Affected Areas

- Flutter: home entry, `bank_statement` feature, payment monitor card borders,
  AppLogger events.
- API: MAP statement list/export/update/history endpoints.
- Database: `MapVietinTransaction.orders`, order metadata, and order audit
  table.
- Auth/security: MANAGER/SUPER_ADMIN feature gate and statement showroom scope.
- External systems: VietinBank MAP sync normalization.
- Deployment: Prisma migration and generated client.

## Human Confirmation Needed

None for V1. Accepted assumptions: national scope can search all/multiple SR;
showroom-scoped users search only their own SR; region/multi-store mapping is a
future phase; no selected rows means export the full filtered result.
