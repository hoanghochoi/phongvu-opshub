# PAYMENT-STATEMENT-001 Bank Statement Reconciliation

## Status

implemented

## Risk Reason

This is high-risk because it changes Prisma schema and migrations, MAP sync
normalization, admin API contracts, role/scope enforcement, XLSX export, audit
history, and two Flutter payment screens.

## Product Contract

Add a `Sao ke` workflow for MAP transactions where the transfer content may not
contain an order code. The feature stores every valid extracted order code,
allows manual inline order correction with audit history, supports scoped search
and XLSX export, and marks transactions visually by whether an order is present.
User-facing statement numbers use the MAP statement reference; stored eFAST rows
must expose their matching `trxId`, while `trxRefNo` stays technical audit data.
eFAST showroom mapping prefers `pmtId` and falls back to the configured receiving
account. Store-account changes immediately assign matching unassigned statement
rows and must not overwrite rows that staff already assigned manually.

### Income type and visibility

Every stored statement has `incomeType`: `SALES` (`Bán hàng`) or
`PARTNER_INTERNAL` (`Đối tác/Nội bộ`). Classification is deterministic and
versioned in code: high-confidence partner/internal markers include internal
reconciliation prefixes (`BC CN...`, `BC CP...`, `BC CTY...`, `BC DKKD...`),
`So GD goc`, and known partner/payment rails (`VNSHOP`, `RECESS`, `ShopeePay`,
`ZaloPay`, `VNPAY`, `Nhat Tin`, `GiaoHangTietKiem`, `Theo lo EMB`, `KHDN`).
Generic `CT DEN` and generic numeric content remain `Bán hàng` so customer
payments are not hidden by an over-broad rule. Existing rows are backfilled by
the same marker set in the migration; later syncs reclassify the row from its
current content.

SR-scoped users are always constrained to `SALES` at the backend query boundary,
including statement-number/order/amount/content global lookup and selected-row
export. FIN_ACC and existing national statement-scope users can see both types.
The Flutter card shows a Vietnamese income-type pill, and mobile collapses the
filter panel after a successful search.

## Affected Areas

- Flutter: home entry, `bank_statement` feature, payment monitor card borders,
  AppLogger events.
- API: MAP statement list/export/update/history endpoints.
- Database: `MapVietinTransaction.orders`, `incomeType`, order metadata, and order audit
  table.
- Auth/security: MANAGER/SUPER_ADMIN feature gate and statement showroom scope.
- External systems: VietinBank MAP sync normalization.
- Deployment: Prisma migration and generated client.

## Human Confirmation Needed

None for V1. Accepted assumptions: national scope can search all/multiple SR;
showroom-scoped users search only their own SR; region/multi-store mapping is a
future phase; no selected rows means export the full filtered result.
