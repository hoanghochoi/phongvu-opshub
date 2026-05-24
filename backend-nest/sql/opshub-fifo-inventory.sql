-- Run this on the OpsHub database, or let OpsHub create it lazily
-- before the first FIFO lookup/import.

CREATE TABLE IF NOT EXISTS fifo_inventory (
  id text PRIMARY KEY,
  sr_code text NOT NULL,
  sr_name text,
  sku text NOT NULL,
  sku_name text NOT NULL DEFAULT '',
  serial_number text,
  serial_type text,
  serial_type_changed_at timestamptz,
  brand text,
  category_id text,
  category_name text,
  subcategory_id text,
  subcategory_name text,
  part_number text,
  unit text,
  bin text,
  bin_name text,
  zone text,
  bin_type text,
  import_date timestamptz,
  count integer NOT NULL DEFAULT 1,
  stock_type text,
  purchase_status text,
  source text NOT NULL DEFAULT 'manual',
  source_updated_at timestamptz,
  exported boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS fifo_inventory_sr_sku_active_exported_import_date_idx
  ON fifo_inventory (sr_code, sku, active, exported, import_date);

CREATE INDEX IF NOT EXISTS fifo_inventory_sr_serial_active_idx
  ON fifo_inventory (sr_code, serial_number, active);

CREATE INDEX IF NOT EXISTS fifo_inventory_sr_bin_active_idx
  ON fifo_inventory (sr_code, bin, active);
