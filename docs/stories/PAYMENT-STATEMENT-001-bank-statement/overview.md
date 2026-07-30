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

## OPS-36 ERP Order Update And Tracking

`Sao kê` and `Tiền vào` now share one existing-style `Cập nhật mã đơn` action.
New order codes are verified through ERP and must be active; replacing or
clearing existing codes is same-Vietnam-day only and requires every old code to
be `CANCELLED` or `RETURNED_FULL`. New compatibility requests are auto-approved
through ERP, while legacy pending requests retain their review lifecycle.

Statements also persist `FOLLOWING`/`UNFOLLOWED` with actor/time metadata and a
dedicated audit. ACC, FIN_ACC, and Super Admin may toggle tracking within their
showroom scope after pending requests are cleared. Filter, Home KPI, XLSX, and
BigQuery consumers use the shared tracking contract; total statement count and
amount remain inclusive, while order coverage counts only followed statements.

## OPS-41 Batch Unfollow

The existing multi-page statement selection also supports `Bỏ theo dõi đã
chọn` for ACC, FIN_ACC, and Super Admin within their existing showroom scope.
The client sends 1-100 unique transaction IDs to
`PATCH /admin/map-vietin/statements/order-tracking/batch` with status
`UNFOLLOWED` and keeps the single-row tracking endpoint unchanged.

The batch is atomic: every row must still exist in scope, have no pending order
transfer request, and match its server snapshot. A concurrent or invalid row
rolls back every tracking and audit write. Rows already `UNFOLLOWED` are logical
no-ops: they create no duplicate audit and no BigQuery revision/outbox event,
but the batch advances their `updatedAt` concurrency token beyond the locked
snapshot. The transaction locks every selected row in canonical ID order before
the final snapshot check, so a stale concurrent re-follow cannot commit after the batch
reports an unchanged success; serialization/deadlock conflicts return an
actionable reload error. The response reports processed, changed, and
unchanged counts, and the client rejects malformed or inconsistent counts.
Success clears selection and refreshes the current page; failure keeps
selection. Selected export, individual re-follow, the
`UNFOLLOWED` filter, Home KPI, XLSX, and BigQuery continue to consume the OPS-36
tracking contract without a new schema or event shape.

## OPS-41 Offset ERP store authority

Offset ERP validation intentionally does not require the referenced ERP order
to belong to the request showroom. The request showroom remains the OpsHub
authorization/reporting scope. The leading ERP store code from
`data.order.createdFromSiteDisplayName` is sanitized into Offset history and
exposed as `Cửa hàng bán`; every Offset request is explicitly labelled with
`Kênh tạo hồ sơ: Cấn trừ trên OpsHub`. The Sales Report cache also
falls back to `data.order.consultant.email` when the ERP creator email is absent
so CHAT-created orders still map to the correct SR owner.
