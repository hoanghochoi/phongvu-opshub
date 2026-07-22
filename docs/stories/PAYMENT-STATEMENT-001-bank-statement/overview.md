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
When MAP/eFAST deduplication retains a MAP row, that survivor must still retain
the eFAST `trxId` and expose it as the product-facing statement number. The MAP
`transactionNumber` remains searchable technical/audit data and must not be
discarded.
eFAST showroom mapping prefers `pmtId` and falls back to the configured receiving
account. Store-account changes immediately assign matching unassigned statement
rows and must not overwrite rows that staff already assigned manually.

### Income type and visibility

Every stored statement has `incomeType`: `SALES` (`Bán hàng`) or
`PARTNER_INTERNAL` (`Đối tác/Nội bộ`). Classification is deterministic and
versioned in code. Matching only uppercases and removes whitespace. Exact
partner/internal rules are compact content starting with `BCCN`, `BCCP`,
`BCCTY`, or `BCDKKD`; containing `NHATTIN`, `VNPAYTT217344`, `SHOPEEPAYMS`,
`SHOPEEWSSSELLERWITHDRAWAL`, `GIAOHANGTIETKIEMCHUYENTIENCOD`,
`TTGDQUAVIZALOPAY`, or `DIEUTIENTUDONG`; or compact content starting with
`TNG`, independent of mapped store and subsequent wording. Payer accounts `8637988888`,
`0302607125`, `113000179095`, `110600994666`, `1011103131001`,
`0071001142275`, and `117601180666` also mark the row partner/internal. Generic
`VNPAY`, `So GD goc`, `CT DEN`, and numeric content remain `Bán hàng` unless
another exact rule matches.
Existing rows are backfilled by the same rules in the migration; later syncs
only reclassify rows whose `incomeTypeSource` is still `AUTO`.

Only users belonging to `FIN_ACC` can see both income types within their
existing organization/showroom scope. Every other user is constrained to
`SALES`, including global lookup and selected-row export. Only `FIN_ACC` can
change the type by clicking the Flutter pill. Such changes are stored as
`MANUAL` and survive later MAP/eFAST syncs. Mobile collapses the filter panel
after a successful search.

## Affected Areas

- Flutter: home entry, `bank_statement` feature, payment monitor card borders,
  AppLogger events.
- API: MAP statement list/export/update/history endpoints.
- Database: `MapVietinTransaction.orders`, `incomeType`, income-type override
  metadata, order metadata, and order audit table.
- Auth/security: MANAGER/SUPER_ADMIN feature gate and statement showroom scope.
- External systems: VietinBank MAP sync normalization.
- Deployment: Prisma migration and generated client.

## Human Confirmation Needed

None for V1. Accepted assumptions: national scope can search all/multiple SR;
showroom-scoped users search only their own SR; region/multi-store mapping is a
future phase; no selected rows means export the full filtered result.
