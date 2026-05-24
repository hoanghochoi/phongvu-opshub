# FIFO Contract

## Intent

Staff use OpsHub to check FIFO status, sort FIFO-related SKUs, and review FIFO
history where permitted.

## Current Shape

- Flutter screens live under `lib/features/fifo/`, `lib/features/sort/`, and
- related sort widgets.
- NestJS owns FIFO, sort, inventory compatibility, and FIFO log modules.
- FIFO inventory reads and export/unexport writes use the OpsHub database table
  `fifo_inventory`. It is intentionally separate from the legacy `inventory`
  table and from the price_watchdog database.
- Admin FIFO history is exposed through the app and backend service.

## Contract Notes

- FIFO behavior is operations-critical because wrong results can affect store or
  warehouse handling.
- FIFO checks are scoped by the signed-in user's `Store.storeId`, which maps to
  the inventory SR code.
- SKU checks list SR-scoped inventory from oldest to newest. Exported items are
  hidden by default and visible only when the user enables the exported toggle.
- FIFO sorting also reads from `fifo_inventory` and is scoped by
  the signed-in user's SR. Sort queries try exact SKU first, then BIN.
- Admin and super admin users can manually import an Excel inventory export
  with the physical serial inventory format. Manual imports upsert into the
  same OpsHub FIFO inventory table, preserve `exported`, and deactivate
  rows missing from the uploaded file for the SR codes present in that file.
- Serial checks return correct FIFO, wrong FIFO, exported, or not-found states.
- Marking an item exported sets `exported=true`; users can show exported items
  and unmark an item when it was exported by mistake.
- Changes to sort rules, inventory freshness, or history visibility require
  story-level validation.
- API response changes must be coordinated with Flutter repositories/models.

## Expected Proof

- Unit tests for sort/FIFO rules.
- NestJS service tests for inventory, sort, and FIFO log behavior.
- Flutter tests for validators and user-visible states where practical.
- Manual app smoke for scanner-driven or device-specific flows.
