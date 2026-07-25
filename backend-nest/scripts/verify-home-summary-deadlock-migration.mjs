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
  '20260725011500_home_projection_deadlock_lock_order',
);
const sourceUrl = process.env.DATABASE_URL?.trim();
if (!sourceUrl) throw new Error('DATABASE_URL is required');

const databaseName = `opshub_home_deadlock_test_${Date.now()}`;
if (!/^opshub_home_deadlock_test_[0-9]+$/.test(databaseName)) {
  throw new Error('Unsafe scratch database name');
}

const adminUrl = new URL(sourceUrl);
adminUrl.pathname = '/postgres';
adminUrl.searchParams.delete('schema');
const scratchUrl = new URL(sourceUrl);
scratchUrl.pathname = `/${databaseName}`;
scratchUrl.searchParams.delete('schema');

const admin = new pg.Client({ connectionString: adminUrl.toString() });
const clients = [];
let created = false;

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

async function connectScratch() {
  const client = new pg.Client({ connectionString: scratchUrl.toString() });
  await client.connect();
  clients.push(client);
  return client;
}

async function waitForLock(observer, pid, label) {
  const deadline = Date.now() + 3_000;
  while (Date.now() < deadline) {
    const result = await observer.query(
      `SELECT wait_event_type
         FROM pg_stat_activity
        WHERE pid = $1`,
      [pid],
    );
    if (result.rows[0]?.wait_event_type === 'Lock') return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error(`${label} did not enter a lock wait`);
}

async function rollbackQuietly(client) {
  await client.query('ROLLBACK').catch(() => undefined);
}

async function verifyFixedDefinition(observer) {
  const definition = await observer.query(
    `SELECT
       pg_get_functiondef(
         'opshub_enqueue_home_summary_projection_kinds(date,text,text[])'::regprocedure
       ) AS body`,
  );
  const body = definition.rows[0]?.body || '';
  const queuePosition = body.indexOf('HomeSummaryProjectionQueue');
  const statePosition = body.indexOf('HomeSummaryProjectionState');
  requireCondition(
    queuePosition >= 0 && statePosition > queuePosition,
    'Migrated enqueue function does not lock queue before projection state',
  );
  requireCondition(
    body.includes('ORDER BY normalized.kind'),
    'Migrated enqueue function does not use deterministic multi-kind order',
  );
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

  const observer = await connectScratch();
  await verifyFixedDefinition(observer);

  const dateResult = await observer.query(
    `SELECT (CURRENT_DATE + INTERVAL '500 days')::date AS summary_date`,
  );
  const summaryDate = dateResult.rows[0].summary_date;
  await observer.query(
    `SELECT opshub_enqueue_home_summary_projection($1::date, 'RECONCILIATION')`,
    [summaryDate],
  );

  // Reproduce the legacy opposing lock graph directly:
  // worker Queue -> State versus producer State -> Queue.
  const oldWorker = await connectScratch();
  const oldProducer = await connectScratch();
  await oldWorker.query(`SET deadlock_timeout = '100ms'`);
  await oldProducer.query(`SET deadlock_timeout = '100ms'`);
  await oldWorker.query('BEGIN');
  await oldProducer.query('BEGIN');
  await oldWorker.query(
    `SELECT "id"
       FROM "HomeSummaryProjectionQueue"
      WHERE "summaryDate" = $1::date AND "projectionKind" = 'SALES'
      FOR UPDATE`,
    [summaryDate],
  );
  await oldProducer.query(
    `SELECT "summaryDate"
       FROM "HomeSummaryProjectionState"
      WHERE "summaryDate" = $1::date
      FOR UPDATE`,
    [summaryDate],
  );
  const workerPid = (await oldWorker.query('SELECT pg_backend_pid() AS pid'))
    .rows[0].pid;
  const workerWait = oldWorker.query(
    `UPDATE "HomeSummaryProjectionState"
        SET "updatedAt" = CURRENT_TIMESTAMP
      WHERE "summaryDate" = $1::date`,
    [summaryDate],
  );
  await waitForLock(observer, workerPid, 'Legacy worker');
  const producerWait = oldProducer.query(
    `UPDATE "HomeSummaryProjectionQueue"
        SET "updatedAt" = CURRENT_TIMESTAMP
      WHERE "summaryDate" = $1::date AND "projectionKind" = 'SALES'`,
    [summaryDate],
  );
  const oldResults = await Promise.allSettled([workerWait, producerWait]);
  const deadlockErrors = oldResults.filter(
    (result) => result.status === 'rejected' && result.reason?.code === '40P01',
  );
  requireCondition(
    deadlockErrors.length === 1,
    `Legacy lock graph did not produce exactly one 40P01: ${oldResults
      .map((result) =>
        result.status === 'rejected' ? result.reason?.code || 'error' : 'ok',
      )
      .join(',')}`,
  );
  await rollbackQuietly(oldWorker);
  await rollbackQuietly(oldProducer);

  // With the migration, producer blocks on Queue before it can lock State.
  // The worker can therefore finish Queue -> State and release both locks.
  const generationBefore = await observer.query(
    `SELECT "dirtyGeneration"
       FROM "HomeSummaryProjectionQueue"
      WHERE "summaryDate" = $1::date AND "projectionKind" = 'SALES'`,
    [summaryDate],
  );
  const fixedWorker = await connectScratch();
  const fixedProducer = await connectScratch();
  await fixedWorker.query('BEGIN');
  await fixedProducer.query('BEGIN');
  await fixedWorker.query(
    `SELECT "id"
       FROM "HomeSummaryProjectionQueue"
      WHERE "summaryDate" = $1::date AND "projectionKind" = 'SALES'
      FOR UPDATE`,
    [summaryDate],
  );
  const producerPid = (
    await fixedProducer.query('SELECT pg_backend_pid() AS pid')
  ).rows[0].pid;
  const fixedEnqueue = fixedProducer.query(
    `SELECT opshub_enqueue_home_summary_projection_kind(
       $1::date, 'ERP_ORDER_CACHE', 'SALES'
     )`,
    [summaryDate],
  );
  await waitForLock(observer, producerPid, 'Migrated producer');
  await fixedWorker.query(
    `UPDATE "HomeSummaryProjectionState"
        SET "updatedAt" = CURRENT_TIMESTAMP
      WHERE "summaryDate" = $1::date`,
    [summaryDate],
  );
  await fixedWorker.query('COMMIT');
  await fixedEnqueue;
  await fixedProducer.query('COMMIT');

  const fixedState = await observer.query(
    `SELECT COUNT(*)::int AS jobs,
            MAX("dirtyGeneration") AS generation
       FROM "HomeSummaryProjectionQueue"
      WHERE "summaryDate" = $1::date AND "projectionKind" = 'SALES'`,
    [summaryDate],
  );
  requireCondition(
    fixedState.rows[0]?.jobs === 1 &&
      BigInt(fixedState.rows[0]?.generation) ===
        BigInt(generationBefore.rows[0]?.dirtyGeneration) + 1n,
    'Fixed contention did not preserve one coalesced job and one generation increment',
  );

  const rollbackSql = await readFile(
    path.join(migrationDir, 'rollback.sql'),
    'utf8',
  );
  await observer.query(rollbackSql);
  const rolledBack = await observer.query(
    `SELECT
       to_regprocedure(
         'opshub_enqueue_home_summary_projection_kinds(date,text,text[])'
       ) IS NULL AS helper_removed,
       pg_get_functiondef(
         'opshub_enqueue_home_summary_projection_kind(date,text,text)'::regprocedure
       ) AS body`,
  );
  const rollbackBody = rolledBack.rows[0]?.body || '';
  requireCondition(
    rolledBack.rows[0]?.helper_removed === true &&
      rollbackBody.indexOf('HomeSummaryProjectionState') <
        rollbackBody.indexOf('HomeSummaryProjectionQueue'),
    'Rollback did not restore the prior enqueue functions',
  );

  const migrationSql = await readFile(
    path.join(migrationDir, 'migration.sql'),
    'utf8',
  );
  await observer.query(migrationSql);
  await verifyFixedDefinition(observer);

  process.stdout.write(
    'Home projection deadlock migration verified: legacy=40P01 fixed=no-deadlock coalescing=ok up/down=ok\n',
  );
} finally {
  await Promise.all(
    clients.map((client) => client.end().catch(() => undefined)),
  );
  if (created) {
    await admin.query(
      `SELECT pg_terminate_backend(pid)
         FROM pg_stat_activity
        WHERE datname = $1 AND pid <> pg_backend_pid()`,
      [databaseName],
    );
    await admin.query(`DROP DATABASE "${databaseName}"`);
  }
  await admin.end().catch(() => undefined);
}
