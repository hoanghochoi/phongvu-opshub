# FIFO Contract

## Intent

Staff use OpsHub to check FIFO status, sort FIFO-related SKUs, and review FIFO
history where permitted.

## Current Shape

- Flutter FIFO screens live under `lib/features/fifo/`; sort widgets live under
  `lib/features/sort/`; shared FIFO check scanner/history helpers live under
  `lib/features/fifo_check/`.
- NestJS owns FIFO, sort, inventory compatibility, and FIFO log modules.
- FIFO inventory reads and export/unexport writes use the OpsHub database table
  `fifo_inventory`. The table uses BigQuery inventory column names as the
  canonical data shape and adds `opshub_*` metadata for cache state, export
  state, source, and audit payloads.
- Admin FIFO history is exposed through the app and backend service.

## Contract Notes

- FIFO behavior is operations-critical because wrong results can affect store or
  warehouse handling.
- FIFO checks are scoped by the signed-in user's `Store.storeId`, which maps to
  the inventory SR code.
- SKU checks list SR-scoped inventory from oldest to newest. Exported items and
  `BIN_type = 'Hàng trưng bày chỉ định'` items are hidden by default.
- FIFO sorting also reads from `fifo_inventory` and is scoped by
  the signed-in user's SR. Sort queries try exact SKU first, then BIN.
- FIFO inventory is refreshed from BigQuery into `fifo_inventory` every day at
  08:00 Asia/Ho_Chi_Minh. BigQuery-sourced rows are the primary stock source.
  A refresh upserts current rows and deactivates missing rows only when those
  existing rows are `opshub_source='bigquery'` for SR codes present in the
  refresh.
- Users with `FIFO_IMPORT` access can manually import an Excel inventory export from the FIFO menu
  with the physical serial inventory format as a supplemental path. Manual
  imports map their Vietnamese headers into the canonical BigQuery shape,
  upsert `opshub_source='manual'`, preserve export state, and do not deactivate
  rows missing from the uploaded file.
- Manual `Ngày nhập kho` maps to `Date_import_site`; manual `Loại hàng = Hàng
  bán` normalizes to `BIN_type = Hàng bán mới tại kho`; manual-only columns are
  stored in `opshub_manual_payload` for audit.
- FIFO order uses `Date_import_company` first and falls back to
  `Date_import_site`, then `Serial` for stable ordering.
- Serial checks return correct FIFO, wrong FIFO, display-reserved, exported, or
  not-found states. A serial is still correct if its FIFO date is no more than
  `FIFO_DATE_TOLERANCE_DAYS` days after the oldest eligible serial; production
  defaults this to 20 days.
- Production UI shows short labels only: `Đúng FIFO`, `Sai FIFO`, `Hàng trưng
  bày chỉ định`, `Đã xuất kho`, or `Không tìm thấy`.
- Marking an item exported sets `opshub_exported=true`; users can show exported
  items and unmark an item when it was exported by mistake.
- Changes to sort rules, inventory freshness, or history visibility require
  story-level validation.
- API response changes must be coordinated with Flutter repositories/models.

## Expected Proof

- Unit tests for sort/FIFO rules.
- NestJS service tests for inventory, sort, and FIFO log behavior.
- Flutter tests for validators and user-visible states where practical.
- Manual app smoke for scanner-driven or device-specific flows.
