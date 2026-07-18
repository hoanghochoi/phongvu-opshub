# PAYMENT-STATEMENT-001 Design

## Proposed Design

- Store orders as `String[]` on `MapVietinTransaction`; an empty list means the
  transaction has no order.
- Extract orders during MAP normalization with a shared validator: independent
  14-digit tokens, valid `yymmdd` prefix, duplicate removal, stable order.
- Preserve protected rows by skipping sync order overwrite when `orderSource`
  is `MANUAL` or an approved `OFFSET`.
- Add an order audit table for manual edits and approved offset transfers,
  linked to the transaction and scoped by store code.
- De-duplicate MAP/eFAST rows by bank identifiers first. If the providers expose
  unrelated identifiers, use the exact cross-source fingerprint of mapped
  showroom, amount, bank timestamp, and stored content; never apply this
  fallback between two rows from the same source.
- Add statement endpoints under `/admin/map-vietin/statements` for list, XLSX
  export, inline order update, and order history.
- Add an ACC-reviewed order-transfer request table and endpoints so visible
  statement users can request order replacement until the Vietnam-local day of
  `paidAt ?? firstSeenAt` closes at 00:00 UTC+7; `SUPER_ADMIN`, `FIN_ACC`, and
  `ACC` reviewers can approve or reject with an optional rejection note, and
  stale pending requests expire out of the pending state.
- Build a Flutter `bank_statement` feature that reuses existing responsive
  layout, buttons, state panels, chips, and logging patterns, including a
  generic `Thông báo` bell for reviewer and requester order-transfer
  notifications.
- Persist `incomeType` as `SALES` or `PARTNER_INTERNAL`, classify only
  high-confidence partner/internal content markers, enforce the type at the
  backend query/export boundary, and show a Vietnamese income-type pill.

## Alternatives Considered

- Single `order` column: rejected because transfer content can contain multiple
  valid order codes.
- Audit all automatic extraction events: rejected for V1 because the history UI
  is intended to answer who manually changed an order.
- Auto-loading statements on screen open: rejected because statement data should
  load only after an explicit filter and Search action.

## Data And Contract Changes

- API: add statement list/export/update/history and order-transfer
  create/list/approve/reject endpoints, return `orders` plus pending/offset
  metadata on stored MAP transactions, and filter `OFFSET_PENDING` /
  `OFFSET_CONFIRMED`.
- Database: add order array/metadata columns and
  `MapVietinTransactionOrderAudit`; add
  `MapVietinStatementOrderTransferRequest` with one pending request per
  transaction.
- Redis/WebSocket: publish scoped `STATEMENT_ORDER_TRANSFER_REQUESTED` from
  NestJS and relay it as `STATEMENT_ORDER_TRANSFER_REQUEST` from Go without
  sending order contents over realtime.
- Environment: no new environment variable.

## Rollback Plan

Hide the home route/tile and block the API endpoints if a runtime rollback is
needed. A database rollback requires reversing the Prisma migration after
preserving any manual audit/order data that must not be lost.
