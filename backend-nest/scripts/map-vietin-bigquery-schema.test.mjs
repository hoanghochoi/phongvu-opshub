import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mapVietinBigQueryCurrentViewDdl,
  mapVietinBigQueryTableDdl,
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
  assert.doesNotMatch(ddl, /rawData|payer|account|email|token|credential/i);
});

test('current view dedupes by transaction revision and hides tombstones', () => {
  const ddl = mapVietinBigQueryCurrentViewDdl(config);
  assert.match(ddl, /PARTITION BY transaction_id/);
  assert.match(
    ddl,
    /ORDER BY revision DESC, event_occurred_at DESC, event_id DESC/,
  );
  assert.match(ddl, /is_deleted = FALSE/);
});
