import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import process from 'node:process';
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
  '20260714200000_home_summary_near_realtime',
);
const sourceUrl = process.env.DATABASE_URL?.trim();
if (!sourceUrl) throw new Error('DATABASE_URL is required');

const databaseName = `opshub_home_projection_test_${Date.now()}`;
if (!/^opshub_home_projection_test_[0-9]+$/.test(databaseName)) {
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
    const detail =
      migration.error?.message ||
      migration.stderr ||
      migration.stdout ||
      'unknown';
    throw new Error(`Prisma migrate deploy failed: ${String(detail).trim()}`);
  }

  scratch = new pg.Client({ connectionString: scratchUrl.toString() });
  await scratch.connect();
  const tableNames = [
    'HomeSummaryDailyAggregate',
    'HomeSummaryProjectionState',
    'HomeSummaryProjectionQueue',
    'DomainOutboxEvent',
    'ErpOrderCacheBackfillCheckpoint',
  ];
  const tables = await scratch.query(
    `SELECT name, to_regclass('public.' || quote_ident(name)) IS NOT NULL AS present
       FROM unnest($1::text[]) AS names(name)`,
    [tableNames],
  );
  if (tables.rows.some((row) => !row.present)) {
    throw new Error('Home projection migration did not create every table');
  }

  const triggers = await scratch.query(
    `SELECT COUNT(*)::int AS count
       FROM pg_trigger
      WHERE tgname IN (
        'SalesReport_home_summary_projection',
        'SalesReportErpOrderCache_home_summary_projection',
        'MapVietinTransaction_home_summary_projection'
      )
        AND NOT tgisinternal`,
  );
  if (triggers.rows[0]?.count !== 3) {
    throw new Error(
      'Home projection migration did not install all source triggers',
    );
  }

  const hotIndexes = await scratch.query(
    `SELECT COUNT(*)::int AS count
       FROM pg_indexes
      WHERE schemaname = 'public'
        AND indexname IN (
          'HomeSummaryProjectionQueue_ready_claim_idx',
          'DomainOutboxEvent_home_summary_pending_idx'
        )`,
  );
  if (hotIndexes.rows[0]?.count !== 2) {
    throw new Error(
      'Home projection migration did not install hot-path indexes',
    );
  }

  const seed = await scratch.query(
    `SELECT
       (SELECT COUNT(*)::int FROM "HomeSummaryProjectionState") AS states,
       (SELECT COUNT(*)::int FROM "HomeSummaryProjectionQueue") AS jobs,
       (SELECT COUNT(*)::int FROM "DomainOutboxEvent"
         WHERE "eventType" = 'HOME_SUMMARY_SOURCE_CHANGED') AS events`,
  );
  const counts = seed.rows[0];
  if (counts.states < 90 || counts.jobs < 90 || counts.events < 90) {
    throw new Error(`90-day seed is incomplete: ${JSON.stringify(counts)}`);
  }

  const rollbackSql = await readFile(
    path.join(migrationDir, 'rollback.sql'),
    'utf8',
  );
  await scratch.query(rollbackSql);
  const rolledBack = await scratch.query(
    `SELECT
       to_regclass('public."HomeSummaryDailyAggregate"') IS NULL AS aggregate_removed,
       to_regclass('public."HomeSummaryProjectionState"') IS NULL AS state_removed,
       to_regclass('public."HomeSummaryProjectionQueue"') IS NULL AS queue_removed,
       to_regclass('public."DomainOutboxEvent"') IS NULL AS outbox_removed,
       to_regclass('public."ErpOrderCacheBackfillCheckpoint"') IS NULL AS checkpoint_removed,
       to_regprocedure('opshub_enqueue_home_summary_projection(date,text)') IS NULL AS function_removed`,
  );
  if (Object.values(rolledBack.rows[0]).some((value) => value !== true)) {
    throw new Error('Home projection rollback left database objects behind');
  }

  process.stdout.write(
    `Home summary migration verified: up=ok seed=${counts.states}/${counts.jobs}/${counts.events} down=ok\n`,
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
