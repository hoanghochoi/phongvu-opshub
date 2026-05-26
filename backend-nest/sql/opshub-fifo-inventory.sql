-- Run this on the OpsHub database, or let OpsHub create it lazily
-- before the first FIFO lookup/import/sync.
-- BigQuery columns keep their canonical names; OpsHub metadata uses opshub_*.

CREATE TABLE IF NOT EXISTS fifo_inventory (
  "id" text PRIMARY KEY,
  "Serial" text,
  "SKU" text,
  "SKU_name" text,
  "Branch_ID" text,
  "Branch_name" text,
  "Brand" text,
  "Category_ID" text,
  "Category_name" text,
  "SubCategory_ID" text,
  "SubCategory_name" text,
  "Subcat_ID_lowest_level" text,
  "Subcat_name_lowest_level" text,
  "Location" text,
  "BIN_type" text,
  "BIN_zone" text,
  "Date_import_company" date,
  "Aging_company" integer,
  "Bad_stock_company" text,
  "Date_import_site" date,
  "Aging_site" integer,
  "Stock_day_site" integer,
  "Bad_stock_site" text,
  "Stock_day_company" integer,
  "Purchase_status" text,
  "Inventory" double precision NOT NULL DEFAULT 0,
  "Inventory_amount" double precision,
  "opshub_item_key" text UNIQUE,
  "opshub_source" text NOT NULL DEFAULT 'manual',
  "opshub_active" boolean NOT NULL DEFAULT true,
  "opshub_exported" boolean NOT NULL DEFAULT false,
  "opshub_synced_at" timestamptz,
  "opshub_manual_payload" jsonb,
  "opshub_created_at" timestamptz NOT NULL DEFAULT now(),
  "opshub_updated_at" timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS fifo_inventory_opshub_item_key_uidx
  ON fifo_inventory ("opshub_item_key");

CREATE INDEX IF NOT EXISTS fifo_inventory_branch_sku_active_fifo_date_idx
  ON fifo_inventory (
    "Branch_ID",
    "SKU",
    "opshub_active",
    "opshub_exported",
    "Date_import_company",
    "Date_import_site"
  );

CREATE INDEX IF NOT EXISTS fifo_inventory_branch_serial_active_idx
  ON fifo_inventory ("Branch_ID", "Serial", "opshub_active");

CREATE INDEX IF NOT EXISTS fifo_inventory_branch_location_active_idx
  ON fifo_inventory ("Branch_ID", "Location", "opshub_active");
