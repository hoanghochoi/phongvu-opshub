# PAYMENT-STATEMENT-001 Design

## Proposed Design

- Store orders as `String[]` on `MapVietinTransaction`; an empty list means the
  transaction has no order.
- Extract orders during MAP normalization with a shared validator: independent
  14-digit tokens, valid `yymmdd` prefix, duplicate removal, stable order.
- Preserve manually edited rows by skipping order overwrite when
  `orderSource = MANUAL`.
- Add an order audit table for manual edits only, linked to the transaction and
  scoped by store code.
- Add statement endpoints under `/admin/map-vietin/statements` for list, CSV
  export, inline order update, and order history.
- Build a Flutter `bank_statement` feature that reuses existing responsive
  layout, buttons, state panels, chips, and logging patterns.

## Alternatives Considered

- Single `order` column: rejected because transfer content can contain multiple
  valid order codes.
- Audit all automatic extraction events: rejected for V1 because the history UI
  is intended to answer who manually changed an order.
- Auto-loading statements on screen open: rejected because statement data should
  load only after an explicit filter and Search action.

## Data And Contract Changes

- API: add statement list/export/update/history endpoints and return `orders`
  metadata on stored MAP transactions.
- Database: add order array/metadata columns and
  `MapVietinTransactionOrderAudit`.
- Redis/WebSocket: no contract change.
- Environment: no new environment variable.

## Rollback Plan

Hide the home route/tile and block the API endpoints if a runtime rollback is
needed. A database rollback requires reversing the Prisma migration after
preserving any manual audit/order data that must not be lost.
