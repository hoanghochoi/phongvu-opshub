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
const migrationDir = path.join(
  backendRoot,
  'prisma',
  'migrations',
  '20260723100000_map_vietin_bigquery_outbox',
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
     ) VALUES ('verify-map-vietin-1', 'S01', 'verify-map-vietin', 'TRX-1', 125000, 'ignored', ARRAY['ORD-1'],
       'MAP', 'PAID', '2026-07-23T02:00:00.000Z', 'Payer', 'Account', 'SALES',
       '{"source":"MAP","providerIdentifiers":{"efastTrxId":"STMT-1"}}'::jsonb, CURRENT_TIMESTAMP)
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
    !Object.keys(payload).some((key) =>
      /raw|content|payer|account|email|user|token|credential/i.test(key),
    ),
    'payload leaked a sensitive key',
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
    await readFile(path.join(migrationDir, 'rollback.sql'), 'utf8'),
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
    'MAP Vietin BigQuery migration verified: insert=ok pii_update=ignored orders_revision=ok dedupe=ok tombstone=ok rollback=ok\n',
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
