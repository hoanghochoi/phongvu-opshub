-- Run this on the price_watchdog database before enabling OpsHub FIFO export.
-- Adjust table/column names if PRICE_WATCHDOG_INVENTORY_* env vars point to a view/table with different names.

ALTER TABLE inventory
  ADD COLUMN IF NOT EXISTS exported boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS inventory_sr_sku_exported_import_date_idx
  ON inventory (sr_code, sku, exported, import_date);

CREATE INDEX IF NOT EXISTS inventory_sr_serial_exported_idx
  ON inventory (sr_code, serial_number, exported);
