export const MAP_VIETIN_BIGQUERY_EVENT_TYPE =
  'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION';
export const MAP_VIETIN_BIGQUERY_AGGREGATE_TYPE = 'MapVietinTransaction';
export const MAP_VIETIN_BIGQUERY_BACKFILL_JOB_KEY =
  'map-vietin-bigquery-backfill-v1';

export type MapVietinBigQueryConfig = {
  enabled: boolean;
  projectId: string;
  datasetId: string;
  tableId: string;
  currentViewId: string;
  keyFilename?: string;
  batchSize: number;
  pollIntervalMs: number;
  leaseSeconds: number;
  maxAttempts: number;
  retryBaseMs: number;
  retryMaxMs: number;
  metricsIntervalMs: number;
  backfillEnabled: boolean;
  backfillPageSize: number;
  backfillLeaseSeconds: number;
};

export function resolveMapVietinBigQueryConfig(
  env: NodeJS.ProcessEnv = process.env,
): MapVietinBigQueryConfig {
  const enabled = strictBoolean(
    env.MAP_VIETIN_BIGQUERY_SYNC_ENABLED,
    'MAP_VIETIN_BIGQUERY_SYNC_ENABLED',
    false,
  );
  const backfillEnabled = strictBoolean(
    env.MAP_VIETIN_BIGQUERY_BACKFILL_ENABLED,
    'MAP_VIETIN_BIGQUERY_BACKFILL_ENABLED',
    false,
  );
  const projectId = optionalText(env.MAP_VIETIN_BIGQUERY_PROJECT_ID);
  const datasetId = optionalText(env.MAP_VIETIN_BIGQUERY_DATASET_ID);
  const tableId = optionalText(env.MAP_VIETIN_BIGQUERY_TABLE_ID);
  const currentViewId = optionalText(env.MAP_VIETIN_BIGQUERY_CURRENT_VIEW_ID);

  if (enabled) {
    assertIdentifier('MAP_VIETIN_BIGQUERY_PROJECT_ID', projectId, true);
    assertIdentifier('MAP_VIETIN_BIGQUERY_DATASET_ID', datasetId);
    assertIdentifier('MAP_VIETIN_BIGQUERY_TABLE_ID', tableId);
    assertIdentifier('MAP_VIETIN_BIGQUERY_CURRENT_VIEW_ID', currentViewId);
  }

  const retryBaseMs = boundedInteger(
    env.MAP_VIETIN_BIGQUERY_RETRY_BASE_MS,
    1000,
    100,
    60_000,
    'MAP_VIETIN_BIGQUERY_RETRY_BASE_MS',
  );
  const retryMaxMs = boundedInteger(
    env.MAP_VIETIN_BIGQUERY_RETRY_MAX_MS,
    300_000,
    1000,
    3_600_000,
    'MAP_VIETIN_BIGQUERY_RETRY_MAX_MS',
  );
  if (retryMaxMs < retryBaseMs) {
    throw new Error(
      'MAP_VIETIN_BIGQUERY_RETRY_MAX_MS must be greater than or equal to MAP_VIETIN_BIGQUERY_RETRY_BASE_MS',
    );
  }

  return {
    enabled,
    projectId,
    datasetId,
    tableId,
    currentViewId,
    keyFilename: optionalText(env.MAP_VIETIN_BIGQUERY_KEY_FILE) || undefined,
    batchSize: boundedInteger(
      env.MAP_VIETIN_BIGQUERY_BATCH_SIZE,
      100,
      1,
      1000,
      'MAP_VIETIN_BIGQUERY_BATCH_SIZE',
    ),
    pollIntervalMs: boundedInteger(
      env.MAP_VIETIN_BIGQUERY_POLL_INTERVAL_MS,
      1000,
      250,
      60_000,
      'MAP_VIETIN_BIGQUERY_POLL_INTERVAL_MS',
    ),
    leaseSeconds: boundedInteger(
      env.MAP_VIETIN_BIGQUERY_LEASE_SECONDS,
      60,
      10,
      3600,
      'MAP_VIETIN_BIGQUERY_LEASE_SECONDS',
    ),
    maxAttempts: boundedInteger(
      env.MAP_VIETIN_BIGQUERY_MAX_ATTEMPTS,
      12,
      1,
      100,
      'MAP_VIETIN_BIGQUERY_MAX_ATTEMPTS',
    ),
    retryBaseMs,
    retryMaxMs,
    metricsIntervalMs: boundedInteger(
      env.MAP_VIETIN_BIGQUERY_METRICS_INTERVAL_MS,
      60_000,
      10_000,
      3_600_000,
      'MAP_VIETIN_BIGQUERY_METRICS_INTERVAL_MS',
    ),
    backfillEnabled,
    backfillPageSize: boundedInteger(
      env.MAP_VIETIN_BIGQUERY_BACKFILL_PAGE_SIZE,
      500,
      1,
      500,
      'MAP_VIETIN_BIGQUERY_BACKFILL_PAGE_SIZE',
    ),
    backfillLeaseSeconds: boundedInteger(
      env.MAP_VIETIN_BIGQUERY_BACKFILL_LEASE_SECONDS,
      300,
      30,
      3600,
      'MAP_VIETIN_BIGQUERY_BACKFILL_LEASE_SECONDS',
    ),
  };
}

function strictBoolean(
  raw: string | undefined,
  key: string,
  fallback: boolean,
) {
  if (!optionalText(raw)) return fallback;
  const value = optionalText(raw).toLowerCase();
  if (value !== 'true' && value !== 'false') {
    throw new Error(`Invalid boolean environment variable: ${key}`);
  }
  return value === 'true';
}

function optionalText(value: string | undefined) {
  return String(value || '').trim();
}

function assertIdentifier(key: string, value: string, project = false) {
  const pattern = project
    ? /^[A-Za-z0-9][A-Za-z0-9.:-]{1,127}$/
    : /^[A-Za-z_][A-Za-z0-9_]{0,1023}$/;
  if (!value || !pattern.test(value)) {
    throw new Error(`Invalid or missing ${key}`);
  }
}

function boundedInteger(
  raw: string | undefined,
  fallback: number,
  min: number,
  max: number,
  key: string,
) {
  if (!optionalText(raw)) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new Error(`Invalid ${key} value: ${raw}`);
  }
  return value;
}
