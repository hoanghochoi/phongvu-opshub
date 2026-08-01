import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mapVietinBigQueryCurrentViewDdl,
  mapVietinBigQueryTableDdl,
  mapVietinBigQueryTrackingColumnDdl,
  mapVietinBigQueryBankColumnsDdl,
} from './map-vietin-bigquery-schema.mjs';

const config = {
  projectId: 'opshub-staging',
  datasetId: 'map_vietin',
  tableId: 'transactions_raw',
  currentViewId: 'transactions_current',
};

test('raw table is partitioned and clustered for current-row queries', () => {
  const ddl = mapVietinBigQueryTableDdl(config);
  assert.match(ddl, /PARTITION BY transaction_date/);
  assert.match(ddl, /CLUSTER BY store_code, transaction_id/);
  assert.match(ddl, /orders ARRAY<STRING>/);
  assert.doesNotMatch(ddl, /orders ARRAY<STRING> NOT NULL/);
  assert.match(ddl, /order_tracking_status STRING/);
  assert.doesNotMatch(ddl, /order_tracking_status STRING NOT NULL/);
  assert.doesNotMatch(ddl, /rawData|payer|account|email|token|credential/i);
  assert.match(ddl, /bank_source STRING/);
  assert.match(ddl, /currency STRING/);
  assert.match(ddl, /direction STRING/);
  assert.match(ddl, /exact_amount NUMERIC/);
});

test('bank compatibility columns upgrade existing tables idempotently', () => {
  const ddl = mapVietinBigQueryBankColumnsDdl(config);
  assert.match(ddl, /ADD COLUMN IF NOT EXISTS bank_source STRING/);
  assert.match(ddl, /ADD COLUMN IF NOT EXISTS exact_amount NUMERIC/);
  assert.doesNotMatch(ddl, /account|payload|credential|secret/i);
});

test('tracking column upgrade is nullable and idempotent for existing raw tables', () => {
  const ddl = mapVietinBigQueryTrackingColumnDdl(config);
  assert.match(
    ddl,
    /ALTER TABLE `opshub-staging\.map_vietin\.transactions_raw`/,
  );
  assert.match(ddl, /ADD COLUMN IF NOT EXISTS order_tracking_status STRING/);
  assert.doesNotMatch(ddl, /order_tracking_status STRING NOT NULL/);
});

test('current view dedupes by transaction revision and hides tombstones', () => {
  const ddl = mapVietinBigQueryCurrentViewDdl(config);
  assert.match(ddl, /PARTITION BY transaction_id/);
  assert.match(
    ddl,
    /ORDER BY revision DESC, event_occurred_at DESC, event_id DESC/,
  );
  assert.match(
    ddl,
    /COALESCE\(order_tracking_status, 'FOLLOWING'\) AS order_tracking_status/,
  );
  assert.match(ddl, /is_deleted = FALSE/);
});
