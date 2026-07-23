const IDENTIFIER = /^[A-Za-z_][A-Za-z0-9_]{0,1023}$/;
const PROJECT = /^[A-Za-z0-9][A-Za-z0-9.:-]{1,127}$/;

export function assertMapVietinBigQueryIdentifiers(config) {
  for (const [key, value, pattern] of [
    ['projectId', config.projectId, PROJECT],
    ['datasetId', config.datasetId, IDENTIFIER],
    ['tableId', config.tableId, IDENTIFIER],
    ['currentViewId', config.currentViewId, IDENTIFIER],
  ]) {
    if (!value || !pattern.test(value)) {
      throw new Error(`Invalid BigQuery identifier: ${key}`);
    }
  }
}

export function mapVietinBigQueryTableDdl({ projectId, datasetId, tableId }) {
  return `CREATE TABLE IF NOT EXISTS \`${projectId}.${datasetId}.${tableId}\`
(
  event_id STRING NOT NULL,
  transaction_id STRING NOT NULL,
  revision INT64 NOT NULL,
  schema_version INT64 NOT NULL,
  transaction_date DATE NOT NULL,
  store_code STRING,
  statement_number STRING,
  amount INT64 NOT NULL,
  orders ARRAY<STRING> NOT NULL,
  order_source STRING,
  status STRING,
  paid_at TIMESTAMP,
  income_type STRING NOT NULL,
  provider_source STRING,
  first_seen_at TIMESTAMP NOT NULL,
  source_created_at TIMESTAMP NOT NULL,
  source_updated_at TIMESTAMP NOT NULL,
  event_occurred_at TIMESTAMP NOT NULL,
  exported_at TIMESTAMP NOT NULL,
  is_deleted BOOL NOT NULL
)
PARTITION BY transaction_date
CLUSTER BY store_code, transaction_id`;
}

export function mapVietinBigQueryCurrentViewDdl({
  projectId,
  datasetId,
  tableId,
  currentViewId,
}) {
  return `CREATE OR REPLACE VIEW \`${projectId}.${datasetId}.${currentViewId}\` AS
SELECT * EXCEPT(row_number)
FROM (
  SELECT raw.*, ROW_NUMBER() OVER (
    PARTITION BY transaction_id
    ORDER BY revision DESC, event_occurred_at DESC, event_id DESC
  ) AS row_number
  FROM \`${projectId}.${datasetId}.${tableId}\` AS raw
)
WHERE row_number = 1 AND is_deleted = FALSE`;
}
