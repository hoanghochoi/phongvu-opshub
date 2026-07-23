import { resolveMapVietinBigQueryConfig } from './map-vietin-bigquery.config';

describe('resolveMapVietinBigQueryConfig', () => {
  it('keeps BigQuery identifiers optional while disabled', () => {
    expect(resolveMapVietinBigQueryConfig({})).toMatchObject({
      enabled: false,
      backfillEnabled: false,
      batchSize: 100,
      backfillPageSize: 500,
    });
  });

  it('requires identifiers only when the worker is enabled', () => {
    expect(() =>
      resolveMapVietinBigQueryConfig({
        MAP_VIETIN_BIGQUERY_SYNC_ENABLED: 'true',
      }),
    ).toThrow('MAP_VIETIN_BIGQUERY_PROJECT_ID');
    expect(
      resolveMapVietinBigQueryConfig({
        MAP_VIETIN_BIGQUERY_SYNC_ENABLED: 'true',
        MAP_VIETIN_BIGQUERY_PROJECT_ID: 'opshub-staging',
        MAP_VIETIN_BIGQUERY_DATASET_ID: 'map_vietin',
        MAP_VIETIN_BIGQUERY_TABLE_ID: 'transactions_raw',
        MAP_VIETIN_BIGQUERY_CURRENT_VIEW_ID: 'transactions_current',
      }).enabled,
    ).toBe(true);
  });

  it('rejects invalid booleans, tuning bounds, and retry order', () => {
    expect(() =>
      resolveMapVietinBigQueryConfig({
        MAP_VIETIN_BIGQUERY_SYNC_ENABLED: 'yes',
      }),
    ).toThrow('Invalid boolean');
    expect(() =>
      resolveMapVietinBigQueryConfig({
        MAP_VIETIN_BIGQUERY_BATCH_SIZE: '1001',
      }),
    ).toThrow('MAP_VIETIN_BIGQUERY_BATCH_SIZE');
    expect(() =>
      resolveMapVietinBigQueryConfig({
        MAP_VIETIN_BIGQUERY_RETRY_BASE_MS: '5000',
        MAP_VIETIN_BIGQUERY_RETRY_MAX_MS: '1000',
      }),
    ).toThrow('RETRY_MAX_MS');
  });
});
