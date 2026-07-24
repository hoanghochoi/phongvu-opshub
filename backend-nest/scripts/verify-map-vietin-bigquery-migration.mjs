import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import pg from 'pg';
import 'dotenv/config';

const backendRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);
const baseMigrationDir = path.join(
  backendRoot,
  'prisma',
  'migrations',
  '20260723100000_map_vietin_bigquery_outbox',
);
const hotfixMigrationDir = path.join(
  backendRoot,
  'prisma',
  'migrations',
  '20260724113000_map_vietin_bigquery_canonical_revision',
);
const snapshotHotfixMigrationDir = path.join(
  backendRoot,
  'prisma',
  'migrations',
  '20260724133000_map_vietin_bigquery_export_snapshot_revision',
);
const sourceUrl = process.env.DATABASE_URL?.trim();
if (!sourceUrl) throw new Error('DATABASE_URL is required');

const databaseName = `opshub_map_vietin_test_${Date.now()}`;
if (!/^opshub_map_vietin_test_[0-9]+$/.test(databaseName)) {
  throw new Error('Unsafe scratch database name');
}
const adminUrl = new URL(sourceUrl);
adminUrl.pathname = '/postgres';
adminUrl.searchParams.delete('schema');
const scratchUrl = new URL(sourceUrl);
scratchUrl.pathname = `/${databaseName}`;
scratchUrl.searchParams.delete('schema');
const admin = new pg.Client({ connectionString: adminUrl.toString() });
let scratch;
let created = false;

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

try {
  await admin.connect();
  await admin.query(`CREATE DATABASE "${databaseName}"`);
  created = true;
  const prismaCli = path.join(
    backendRoot,
    'node_modules',
    'prisma',
    'build',
    'index.js',
  );
  const migration = spawnSync(
    process.execPath,
    [prismaCli, 'migrate', 'deploy'],
    {
      cwd: backendRoot,
      env: { ...process.env, DATABASE_URL: scratchUrl.toString() },
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
  if (migration.status !== 0) {
    throw new Error(
      `Prisma migrate deploy failed: ${migration.stderr || migration.stdout || 'unknown'}`,
    );
  }
  scratch = new pg.Client({ connectionString: scratchUrl.toString() });
  await scratch.connect();

  const inserted = await scratch.query(
    `INSERT INTO "MapVietinTransaction" (
       "id", "storeCode", "transactionKey", "transactionNumber", "amount", "content", "orders",
       "orderSource", "status", "paidAt", "payerName", "payerAccount", "incomeType", "rawData", "updatedAt"
     ) VALUES ('verify-map-vietin-1', 'S01', 'verify-map-vietin', 'MAP-TRX-1', 125000, 'ignored', ARRAY['ORD-1'],
       'MAP', 'Thành công', '2026-07-23T02:00:00.000Z', 'Payer', 'Account', 'SALES',
       '{"source":"MAP","providerIdentifiers":{"mapTransactionNumber":"MAP-TRX-1","efastTrxId":"STMT-1"}}'::jsonb, CURRENT_TIMESTAMP)
     RETURNING "id", "bigQueryRevision"`,
  );
  const id = inserted.rows[0].id;
  requireCondition(
    Number(inserted.rows[0].bigQueryRevision) === 1,
    'insert revision was not 1',
  );
  const initialEvent = await scratch.query(
    `SELECT "payload" FROM "DomainOutboxEvent"
      WHERE "eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION' AND "aggregateId" = $1`,
    [id],
  );
  requireCondition(
    initialEvent.rowCount === 1,
    'insert did not enqueue one event',
  );
  const payload = initialEvent.rows[0].payload;
  requireCondition(
    payload.statement_number === 'STMT-1',
    'statement identifier was not sanitized',
  );
  requireCondition(
    payload.status === 'SUCCESS',
    'successful MAP status was not canonicalized',
  );
  requireCondition(
    payload.provider_source === 'VIETIN_EFAST',
    'provider source was not derived from stable identifiers',
  );
  requireCondition(
    !Object.keys(payload).some((key) =>
      /raw|content|payer|account|email|user|token|credential/i.test(key),
    ),
    'payload leaked a sensitive key',
  );

  for (let index = 0; index < 100; index += 1) {
    const efastReplay = index % 2 === 0;
    await scratch.query(
      `UPDATE "MapVietinTransaction"
       SET "transactionNumber" = $2,
           "status" = $3,
           "rawData" = jsonb_set("rawData", '{source}', to_jsonb($4::text)),
           "updatedAt" = CURRENT_TIMESTAMP
       WHERE "id" = $1`,
      [
        id,
        efastReplay ? 'HIDDEN-EFAST-TRX' : 'HIDDEN-MAP-TRX',
        efastReplay ? 'SUCCESS' : 'Thành công',
        efastReplay ? 'VIETIN_EFAST' : 'MAP',
      ],
    );
  }
  const afterEquivalentReplay = await scratch.query(
    `SELECT transaction."bigQueryRevision",
            COUNT(event."id")::int AS event_count
     FROM "MapVietinTransaction" AS transaction
     LEFT JOIN "DomainOutboxEvent" AS event
       ON event."aggregateId" = transaction."id"
      AND event."eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION'
     WHERE transaction."id" = $1
     GROUP BY transaction."bigQueryRevision"`,
    [id],
  );
  requireCondition(
    Number(afterEquivalentReplay.rows[0].bigQueryRevision) === 1 &&
      afterEquivalentReplay.rows[0].event_count === 1,
    'hidden transaction number or equivalent MAP/eFAST replay emitted duplicate revisions',
  );

  await scratch.query(
    `UPDATE "MapVietinTransaction" SET "payerName" = 'Changed' WHERE "id" = $1`,
    [id],
  );
  const afterPii = await scratch.query(
    `SELECT COUNT(*)::int AS count FROM "DomainOutboxEvent"
      WHERE "eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION' AND "aggregateId" = $1`,
    [id],
  );
  requireCondition(
    afterPii.rows[0].count === 1,
    'PII-only update emitted an event',
  );

  await scratch.query(
    `UPDATE "MapVietinTransaction" SET "orders" = ARRAY['ORD-2'] WHERE "id" = $1`,
    [id],
  );
  const afterOrders = await scratch.query(
    `SELECT "bigQueryRevision" FROM "MapVietinTransaction" WHERE "id" = $1`,
    [id],
  );
  requireCondition(
    Number(afterOrders.rows[0].bigQueryRevision) === 2,
    'orders update did not increment revision',
  );
  await scratch.query(
    `SELECT opshub_enqueue_map_vietin_bigquery_transaction($1)`,
    [id],
  );
  const duplicate = await scratch.query(
    `SELECT COUNT(*)::int AS count FROM "DomainOutboxEvent"
      WHERE "eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION' AND "aggregateId" = $1`,
    [id],
  );
  requireCondition(
    duplicate.rows[0].count === 2,
    'dedupe key was not idempotent',
  );

  await scratch.query(
    `UPDATE "MapVietinTransaction" SET "status" = 'FAILED' WHERE "id" = $1`,
    [id],
  );
  const afterMeaningfulStatus = await scratch.query(
    `SELECT transaction."bigQueryRevision",
            COUNT(event."id")::int AS event_count
     FROM "MapVietinTransaction" AS transaction
     LEFT JOIN "DomainOutboxEvent" AS event
       ON event."aggregateId" = transaction."id"
      AND event."eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION'
     WHERE transaction."id" = $1
     GROUP BY transaction."bigQueryRevision"`,
    [id],
  );
  requireCondition(
    Number(afterMeaningfulStatus.rows[0].bigQueryRevision) === 3 &&
      afterMeaningfulStatus.rows[0].event_count === 3,
    'meaningful status update did not emit exactly one revision',
  );

  const enrichmentId = 'verify-map-vietin-enrichment';
  await scratch.query(
    `INSERT INTO "MapVietinTransaction" (
       "id", "storeCode", "transactionKey", "transactionNumber", "amount", "content", "orders",
       "orderSource", "status", "paidAt", "incomeType", "rawData", "updatedAt"
     ) VALUES ($1, 'S01', 'verify-map-vietin-enrichment', 'MAP-TRX-2', 250000, 'ignored', ARRAY[]::text[],
       'MAP', 'Thành công', '2026-07-23T03:00:00.000Z', 'SALES',
       '{"source":"MAP","providerIdentifiers":{"mapTransactionNumber":"MAP-TRX-2"}}'::jsonb,
       CURRENT_TIMESTAMP)`,
    [enrichmentId],
  );
  await scratch.query(
    `UPDATE "MapVietinTransaction"
     SET "status" = 'SUCCESS',
         "rawData" = '{"source":"VIETIN_EFAST","providerIdentifiers":{"mapTransactionNumber":"MAP-TRX-2","efastTrxId":"EFAST-TRX-2"}}'::jsonb,
         "updatedAt" = CURRENT_TIMESTAMP
     WHERE "id" = $1`,
    [enrichmentId],
  );
  for (let index = 0; index < 20; index += 1) {
    const efastReplay = index % 2 === 0;
    await scratch.query(
      `UPDATE "MapVietinTransaction"
       SET "status" = $2,
           "rawData" = jsonb_set("rawData", '{source}', to_jsonb($3::text)),
           "updatedAt" = CURRENT_TIMESTAMP
       WHERE "id" = $1`,
      [
        enrichmentId,
        efastReplay ? 'SUCCESS' : 'Thành công',
        efastReplay ? 'VIETIN_EFAST' : 'MAP',
      ],
    );
  }
  const afterIdentifierEnrichment = await scratch.query(
    `SELECT transaction."bigQueryRevision",
            COUNT(event."id")::int AS event_count,
            (array_agg(event."payload" ORDER BY event."occurredAt" DESC))[1] AS latest_payload
     FROM "MapVietinTransaction" AS transaction
     LEFT JOIN "DomainOutboxEvent" AS event
       ON event."aggregateId" = transaction."id"
      AND event."eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION'
     WHERE transaction."id" = $1
     GROUP BY transaction."bigQueryRevision"`,
    [enrichmentId],
  );
  requireCondition(
    Number(afterIdentifierEnrichment.rows[0].bigQueryRevision) === 2 &&
      afterIdentifierEnrichment.rows[0].event_count === 2,
    'identifier enrichment or replay produced the wrong revision count',
  );
  requireCondition(
    afterIdentifierEnrichment.rows[0].latest_payload.statement_number ===
      'EFAST-TRX-2' &&
      afterIdentifierEnrichment.rows[0].latest_payload.status === 'SUCCESS' &&
      afterIdentifierEnrichment.rows[0].latest_payload.provider_source ===
        'VIETIN_EFAST',
    'identifier enrichment did not produce the canonical BigQuery payload',
  );

  await scratch.query(`DELETE FROM "MapVietinTransaction" WHERE "id" = $1`, [
    id,
  ]);
  const tombstone = await scratch.query(
    `SELECT "payload" FROM "DomainOutboxEvent"
      WHERE "eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION' AND "aggregateId" = $1
      ORDER BY "occurredAt" DESC LIMIT 1`,
    [id],
  );
  requireCondition(
    tombstone.rows[0]?.payload?.is_deleted === true,
    'delete did not enqueue tombstone',
  );

  const rollbackId = '00000000-0000-0000-0000-000000000099';
  await scratch.query('BEGIN');
  await scratch.query(
    `INSERT INTO "MapVietinTransaction" (
       "id", "transactionKey", "amount", "content", "orders", "incomeType", "rawData", "updatedAt"
     ) VALUES ($1, 'verify-rollback', 1, 'rollback', ARRAY[]::text[], 'SALES', '{}'::jsonb, CURRENT_TIMESTAMP)`,
    [rollbackId],
  );
  await scratch.query('ROLLBACK');
  const rolledBack = await scratch.query(
    `SELECT COUNT(*)::int AS count FROM "DomainOutboxEvent" WHERE "aggregateId" = $1`,
    [rollbackId],
  );
  requireCondition(
    rolledBack.rows[0].count === 0,
    'rolled-back insert left an outbox event',
  );

  await scratch.query(
    await readFile(
      path.join(snapshotHotfixMigrationDir, 'rollback.sql'),
      'utf8',
    ),
  );
  const snapshotHotfixDown = await scratch.query(
    `SELECT
       to_regprocedure('opshub_map_vietin_bigquery_revision_snapshot("MapVietinTransaction")') IS NULL AS snapshot_helper_removed,
       to_regprocedure('opshub_map_vietin_bigquery_canonical_status(text)') IS NOT NULL AS v1_status_helper_restored`,
  );
  requireCondition(
    Object.values(snapshotHotfixDown.rows[0]).every(Boolean),
    'snapshot hotfix rollback did not restore v1 cleanly',
  );

  const snapshotRollbackId = 'verify-map-vietin-snapshot-rollback';
  await scratch.query(
    `INSERT INTO "MapVietinTransaction" (
       "id", "transactionKey", "transactionNumber", "amount", "content", "orders",
       "status", "incomeType", "rawData", "updatedAt"
     ) VALUES ($1, 'verify-snapshot-rollback', 'RAW-A', 1, 'rollback', ARRAY[]::text[],
       'SUCCESS', 'SALES',
       '{"source":"VIETIN_EFAST","providerIdentifiers":{"efastTrxId":"STABLE-ID"}}'::jsonb,
       CURRENT_TIMESTAMP)`,
    [snapshotRollbackId],
  );
  await scratch.query(
    `UPDATE "MapVietinTransaction"
     SET "transactionNumber" = 'RAW-B', "updatedAt" = CURRENT_TIMESTAMP
     WHERE "id" = $1`,
    [snapshotRollbackId],
  );
  const snapshotRollbackBehavior = await scratch.query(
    `SELECT transaction."bigQueryRevision",
            COUNT(event."id")::int AS event_count
     FROM "MapVietinTransaction" AS transaction
     LEFT JOIN "DomainOutboxEvent" AS event
       ON event."aggregateId" = transaction."id"
      AND event."eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION'
     WHERE transaction."id" = $1
     GROUP BY transaction."bigQueryRevision"`,
    [snapshotRollbackId],
  );
  requireCondition(
    Number(snapshotRollbackBehavior.rows[0].bigQueryRevision) === 2 &&
      snapshotRollbackBehavior.rows[0].event_count === 2,
    'snapshot hotfix rollback did not restore v1 raw transaction behavior',
  );

  await scratch.query(
    await readFile(path.join(hotfixMigrationDir, 'rollback.sql'), 'utf8'),
  );
  const hotfixDown = await scratch.query(
    `SELECT
       to_regprocedure('opshub_map_vietin_bigquery_canonical_status(text)') IS NULL AS status_helper_removed,
       to_regprocedure('opshub_map_vietin_bigquery_provider_source(jsonb)') IS NULL AS source_helper_removed`,
  );
  requireCondition(
    Object.values(hotfixDown.rows[0]).every(Boolean),
    'hotfix rollback left canonicalization helpers behind',
  );

  const legacyBehaviorId = 'verify-map-vietin-hotfix-rollback';
  await scratch.query(
    `INSERT INTO "MapVietinTransaction" (
       "id", "transactionKey", "transactionNumber", "amount", "content", "orders",
       "status", "incomeType", "rawData", "updatedAt"
     ) VALUES ($1, 'verify-hotfix-rollback', 'MAP-ROLLBACK', 1, 'rollback', ARRAY[]::text[],
       'Thành công', 'SALES',
       '{"source":"MAP","providerIdentifiers":{"mapTransactionNumber":"MAP-ROLLBACK","efastTrxId":"EFAST-ROLLBACK"}}'::jsonb,
       CURRENT_TIMESTAMP)`,
    [legacyBehaviorId],
  );
  await scratch.query(
    `UPDATE "MapVietinTransaction"
     SET "status" = 'SUCCESS',
         "rawData" = jsonb_set("rawData", '{source}', '"VIETIN_EFAST"'::jsonb),
         "updatedAt" = CURRENT_TIMESTAMP
     WHERE "id" = $1`,
    [legacyBehaviorId],
  );
  const legacyBehavior = await scratch.query(
    `SELECT transaction."bigQueryRevision",
            COUNT(event."id")::int AS event_count
     FROM "MapVietinTransaction" AS transaction
     LEFT JOIN "DomainOutboxEvent" AS event
       ON event."aggregateId" = transaction."id"
      AND event."eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION'
     WHERE transaction."id" = $1
     GROUP BY transaction."bigQueryRevision"`,
    [legacyBehaviorId],
  );
  requireCondition(
    Number(legacyBehavior.rows[0].bigQueryRevision) === 2 &&
      legacyBehavior.rows[0].event_count === 2,
    'hotfix rollback did not restore the previous revision behavior',
  );

  await scratch.query(
    await readFile(path.join(baseMigrationDir, 'rollback.sql'), 'utf8'),
  );
  const down = await scratch.query(
    `SELECT
       to_regclass('"MapVietinBigQueryBackfillCheckpoint"') IS NULL AS checkpoint_removed,
       to_regprocedure('opshub_enqueue_map_vietin_bigquery_transaction(text)') IS NULL AS function_removed,
       NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'MapVietinTransaction' AND column_name = 'bigQueryRevision') AS revision_removed`,
  );
  requireCondition(
    Object.values(down.rows[0]).every(Boolean),
    'rollback left MAP BigQuery objects behind',
  );
  process.stdout.write(
    'MAP Vietin BigQuery migration verified: insert=ok export_snapshot_replay=stable identifier_enrichment=ok pii_update=ignored orders_revision=ok status_revision=ok dedupe=ok tombstone=ok layered_rollback=ok\n',
  );
} finally {
  if (scratch) await scratch.end().catch(() => undefined);
  if (created) {
    await admin.query(
      `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()`,
      [databaseName],
    );
    await admin.query(`DROP DATABASE "${databaseName}"`);
  }
  await admin.end().catch(() => undefined);
}
