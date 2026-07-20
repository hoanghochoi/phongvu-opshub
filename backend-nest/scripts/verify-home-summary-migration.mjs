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
const closureMigrationDir = path.join(
  backendRoot,
  'prisma',
  'migrations',
  '20260720143000_home_projection_phase1_closure',
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
    const detail =
      migration.error?.message ||
      migration.stderr ||
      migration.stdout ||
      'unknown';
    throw new Error(`Prisma migrate deploy failed: ${String(detail).trim()}`);
  }

  scratch = new pg.Client({ connectionString: scratchUrl.toString() });
  await scratch.connect();

  const requiredColumns = [
    ['HomeSummaryDailyAggregate', 'projectionKind'],
    ['HomeSummaryDailyAggregate', 'metrics'],
    ['HomeSummaryProjectionState', 'salesStatus'],
    ['HomeSummaryProjectionState', 'financeStatus'],
    ['HomeSummaryProjectionQueue', 'claimToken'],
    ['HomeSummaryProjectionQueue', 'dirtyGeneration'],
    ['DomainOutboxEvent', 'leaseExpiresAt'],
  ];
  const columns = await scratch.query(
    `SELECT table_name, column_name
       FROM information_schema.columns
      WHERE table_schema = 'public'
        AND (table_name || '.' || column_name) = ANY($1::text[])`,
    [requiredColumns.map(([table, column]) => `${table}.${column}`)],
  );
  requireCondition(
    columns.rowCount === requiredColumns.length,
    'Phase 1 closure did not install every required column',
  );

  const triggers = await scratch.query(
    `SELECT COUNT(*)::int AS count
       FROM pg_trigger
      WHERE tgname IN (
        'SalesReport_home_summary_projection_insert',
        'SalesReport_home_summary_projection_update',
        'SalesReport_home_summary_projection_delete',
        'SalesReportErpOrderCache_home_summary_projection_insert',
        'SalesReportErpOrderCache_home_summary_projection_update',
        'SalesReportErpOrderCache_home_summary_projection_delete',
        'MapVietinTransaction_home_summary_projection_insert',
        'MapVietinTransaction_home_summary_projection_update',
        'MapVietinTransaction_home_summary_projection_delete'
      )
        AND NOT tgisinternal`,
  );
  requireCondition(
    triggers.rows[0]?.count === 9,
    'Phase 1 closure did not install all statement-level source triggers',
  );

  const functions = await scratch.query(
    `SELECT
       pg_get_functiondef('opshub_enqueue_home_summary_projection_kind(date,text,text)'::regprocedure) AS enqueue_kind_definition,
       pg_get_functiondef('opshub_home_summary_statement_trigger()'::regprocedure) AS statement_trigger_definition`,
  );
  const enqueueKindDefinition =
    functions.rows[0]?.enqueue_kind_definition || '';
  const statementTriggerDefinition =
    functions.rows[0]?.statement_trigger_definition || '';
  requireCondition(
    enqueueKindDefinition.includes('dirtyGeneration') &&
      enqueueKindDefinition.includes('claimToken') &&
      enqueueKindDefinition.includes('pg_notify') &&
      statementTriggerDefinition.includes('new_rows') &&
      statementTriggerDefinition.includes('old_rows'),
    'Phase 1 closure functions are missing coalescing or statement trigger logic',
  );

  const hotIndexes = await scratch.query(
    `SELECT COUNT(*)::int AS count
       FROM pg_indexes
      WHERE schemaname = 'public'
        AND indexname IN (
          'HomeSummaryDailyAggregate_summaryDate_projectionKind_dimensionType_dimensionKey_storeCode_key',
          'HomeSummaryProjectionQueue_ready_lease_idx',
          'HomeSummaryProjectionQueue_availableAt_leaseExpiresAt_idx',
          'DomainOutboxEvent_publish_lease_idx'
        )`,
  );
  requireCondition(
    hotIndexes.rows[0]?.count === 4,
    'Phase 1 closure did not install every hot-path index',
  );

  const seed = await scratch.query(
    `SELECT
       (SELECT COUNT(*)::int FROM "HomeSummaryProjectionState") AS states,
       (SELECT COUNT(*)::int FROM "HomeSummaryProjectionQueue") AS jobs,
       (SELECT COUNT(*)::int FROM "HomeSummaryProjectionQueue"
         WHERE "projectionKind" = 'SALES') AS sales_jobs,
       (SELECT COUNT(*)::int FROM "HomeSummaryProjectionQueue"
         WHERE "projectionKind" = 'FINANCE') AS finance_jobs,
       (SELECT COUNT(*)::int FROM "DomainOutboxEvent"
         WHERE "eventType" = 'HOME_SUMMARY_SOURCE_CHANGED') AS events`,
  );
  const counts = seed.rows[0];
  requireCondition(
    counts.states >= 90 &&
      counts.sales_jobs >= 90 &&
      counts.finance_jobs >= 90 &&
      counts.jobs >= 180 &&
      counts.events >= 180,
    `90-day dual projection seed is incomplete: ${JSON.stringify(counts)}`,
  );

  const beforeMap = await scratch.query(
    `SELECT "dirtyGeneration" FROM "HomeSummaryProjectionQueue"
      WHERE "summaryDate" = CURRENT_DATE AND "projectionKind" = 'SALES'`,
  );
  await scratch.query(
    `SELECT opshub_enqueue_home_summary_projection(CURRENT_DATE, 'MAP_VIETIN')`,
  );
  const afterMap = await scratch.query(
    `SELECT "dirtyGeneration" FROM "HomeSummaryProjectionQueue"
      WHERE "summaryDate" = CURRENT_DATE AND "projectionKind" = 'SALES'`,
  );
  requireCondition(
    beforeMap.rows[0]?.dirtyGeneration === afterMap.rows[0]?.dirtyGeneration,
    'MAP enqueue unexpectedly dirtied the SALES projection',
  );

  const firstDate = await scratch.query(
    `SELECT (CURRENT_DATE + INTERVAL '400 days')::date AS summary_date`,
  );
  await scratch.query(
    `SELECT opshub_enqueue_home_summary_projection($1::date, 'SALES_REPORT')`,
    [firstDate.rows[0].summary_date],
  );
  const firstDateJobs = await scratch.query(
    `SELECT COUNT(*)::int AS jobs,
            COUNT(*) FILTER (WHERE "projectionKind" = 'SALES')::int AS sales_jobs,
            COUNT(*) FILTER (WHERE "projectionKind" = 'FINANCE')::int AS finance_jobs
       FROM "HomeSummaryProjectionQueue"
      WHERE "summaryDate" = $1::date`,
    [firstDate.rows[0].summary_date],
  );
  requireCondition(
    firstDateJobs.rows[0]?.jobs === 2 &&
      firstDateJobs.rows[0]?.sales_jobs === 1 &&
      firstDateJobs.rows[0]?.finance_jobs === 1,
    'The first source commit for a new date did not enqueue both projection kinds',
  );

  await scratch.query(
    `SELECT opshub_enqueue_home_summary_projection_kind(
       CURRENT_DATE, 'BURST_TEST', 'SALES'
     ) FROM generate_series(1, 5000)`,
  );
  const burst = await scratch.query(
    `SELECT COUNT(*)::int AS jobs, MAX("dirtyGeneration") AS generation
       FROM "HomeSummaryProjectionQueue"
      WHERE "summaryDate" = CURRENT_DATE AND "projectionKind" = 'SALES'`,
  );
  requireCondition(
    burst.rows[0]?.jobs === 1 && Number(burst.rows[0]?.generation) >= 5000,
    '5,000 source signals created a projection job storm',
  );

  const rollbackSql = await readFile(
    path.join(closureMigrationDir, 'rollback.sql'),
    'utf8',
  );
  await scratch.query(rollbackSql);
  const rolledBack = await scratch.query(
    `SELECT
       NOT EXISTS (
         SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'HomeSummaryDailyAggregate'
            AND column_name = 'projectionKind'
       ) AS aggregate_kind_removed,
       NOT EXISTS (
         SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'HomeSummaryProjectionQueue'
            AND column_name = 'claimToken'
       ) AS queue_claim_removed,
       to_regprocedure('opshub_enqueue_home_summary_projection_kind(date,text,text)') IS NULL AS kind_function_removed,
       to_regprocedure('opshub_home_summary_statement_trigger()') IS NULL AS statement_function_removed,
       to_regprocedure('opshub_enqueue_home_summary_projection(date,text)') IS NOT NULL AS legacy_function_restored`,
  );
  requireCondition(
    Object.values(rolledBack.rows[0]).every((value) => value === true),
    'Phase 1 closure rollback left incompatible schema objects behind',
  );
  const legacyTriggers = await scratch.query(
    `SELECT COUNT(*)::int AS count
       FROM pg_trigger
      WHERE tgname IN (
        'SalesReport_home_summary_projection',
        'SalesReportErpOrderCache_home_summary_projection',
        'MapVietinTransaction_home_summary_projection'
      )
        AND NOT tgisinternal`,
  );
  requireCondition(
    legacyTriggers.rows[0]?.count === 3,
    'Phase 1 closure rollback did not restore legacy row triggers',
  );

  process.stdout.write(
    `Home summary Phase 1 closure verified: up=ok seed=${counts.states}/${counts.jobs}/${counts.events} burst=5000->1 down=ok\n`,
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
