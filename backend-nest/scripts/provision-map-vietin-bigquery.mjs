import 'dotenv/config';
import { BigQuery } from '@google-cloud/bigquery';
import {
  assertMapVietinBigQueryIdentifiers,
  mapVietinBigQueryCurrentViewDdl,
  mapVietinBigQueryTableDdl,
} from './map-vietin-bigquery-schema.mjs';

const config = {
  projectId: required('MAP_VIETIN_BIGQUERY_PROJECT_ID'),
  datasetId: required('MAP_VIETIN_BIGQUERY_DATASET_ID'),
  tableId: required('MAP_VIETIN_BIGQUERY_TABLE_ID'),
  currentViewId: required('MAP_VIETIN_BIGQUERY_CURRENT_VIEW_ID'),
  keyFilename: process.env.MAP_VIETIN_BIGQUERY_KEY_FILE?.trim() || undefined,
};
assertMapVietinBigQueryIdentifiers(config);

const client = new BigQuery({
  projectId: config.projectId,
  ...(config.keyFilename ? { keyFilename: config.keyFilename } : {}),
});

await runDdl(mapVietinBigQueryTableDdl(config));
await runDdl(mapVietinBigQueryCurrentViewDdl(config));
console.log(
  `Provisioned MAP Vietin BigQuery raw table and current view: dataset=${config.datasetId} table=${config.tableId} view=${config.currentViewId}`,
);

async function runDdl(query) {
  const [job] = await client.createQueryJob({
    query,
    projectId: config.projectId,
    useLegacySql: false,
  });
  await job.getQueryResults();
}

function required(key) {
  const value = process.env[key]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${key}`);
  return value;
}
