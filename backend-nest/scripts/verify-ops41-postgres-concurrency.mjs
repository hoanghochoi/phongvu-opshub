import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import pg from 'pg';

const { Pool } = pg;
const startedAt = Date.now();
const connectionString = process.env.OPS41_POSTGRES_URL?.trim();

if (!connectionString) {
  throw new Error(
    'Set OPS41_POSTGRES_URL to a disposable loopback PostgreSQL database.',
  );
}

const parsedUrl = new URL(connectionString);
const databaseName = decodeURIComponent(parsedUrl.pathname.replace(/^\//, ''));
const loopbackHosts = new Set(['127.0.0.1', 'localhost', '::1']);
if (!loopbackHosts.has(parsedUrl.hostname)) {
  throw new Error('OPS-41 PostgreSQL proof only accepts a loopback host.');
}
if (!/^opshub_ops41_proof(?:_|$)/i.test(databaseName)) {
  throw new Error(
    'OPS41_POSTGRES_URL must target a disposable opshub_ops41_proof* database.',
  );
}

const backendRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);
const pool = new Pool({ connectionString, max: 5 });

const offsetTable = '"OffsetAdjustment"';
const offsetHistoryTable = '"OffsetAdjustmentHistory"';
const statementTable = '"MapVietinTransaction"';
const statementAuditTable = '"MapVietinTransactionOrderTrackingAudit"';

const t0 = new Date('2026-07-30T03:00:00.000Z');
const t1 = new Date('2026-07-30T03:01:00.000Z');
const t2 = new Date('2026-07-30T03:02:00.000Z');

async function setup() {
  const prismaMigrationRunner = path.join(
    backendRoot,
    'scripts',
    'run-prisma-migrate-deploy.mjs',
  );
  const migration = spawnSync(
    process.execPath,
    [prismaMigrationRunner],
    {
      cwd: backendRoot,
      env: { ...process.env, DATABASE_URL: connectionString },
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
  if (migration.status !== 0) {
    throw new Error(
      `Prisma migrate deploy failed: ${migration.stderr || migration.stdout || 'unknown'}`,
    );
  }
}

async function resetOffsetRows(rows) {
  await pool.query(`TRUNCATE ${offsetHistoryTable}, ${offsetTable}`);
  for (const row of rows) {
    await pool.query(
      `INSERT INTO ${offsetTable}
       (id, type, status, "storeCode", amount, "updatedAt")
       VALUES ($1, 'ZALOPAY', $2, 'CP01', 1000, $3)`,
      [row.id, row.status, row.updatedAt],
    );
  }
}

async function resetStatementRows(rows) {
  await pool.query(
    `DELETE FROM ${statementAuditTable}
     WHERE "transactionId" LIKE 'statement-%'`,
  );
  await pool.query(
    `DELETE FROM "MapVietinStatementOrderTransferRequest"
     WHERE "transactionId" LIKE 'statement-%'`,
  );
  await pool.query(
    `DELETE FROM "MapVietinTransactionOrderAudit"
     WHERE "transactionId" LIKE 'statement-%'`,
  );
  await pool.query(`DELETE FROM ${statementTable} WHERE id LIKE 'statement-%'`);
  for (const row of rows) {
    await pool.query(
      `INSERT INTO ${statementTable}
       (id, "transactionKey", amount, content, orders,
        "orderTrackingStatus", "rawData", "updatedAt")
       VALUES ($1, $1, 1000, 'OPS-41 proof', ARRAY[]::text[],
        $2, '{}'::jsonb, $3)`,
      [row.id, row.status, row.updatedAt],
    );
  }
}

async function assertStillBlocked(promise, label) {
  let settled = false;
  promise.then(
    () => {
      settled = true;
    },
    () => {
      settled = true;
    },
  );
  await new Promise((resolve) => setTimeout(resolve, 100));
  assert.equal(settled, false, `${label} should wait for the row lock`);
}

async function offsetSingleAfterBatch(action) {
  await resetOffsetRows([
    { id: 'offset-race', status: 'PENDING_ACC', updatedAt: t0 },
  ]);
  const events = [];
  const batch = await pool.connect();
  const single = await pool.connect();
  try {
    await batch.query('BEGIN');
    await batch.query(
      `SELECT id FROM ${offsetTable} WHERE id = $1 FOR UPDATE`,
      ['offset-race'],
    );
    const approved = await batch.query(
      `UPDATE ${offsetTable}
       SET status = 'APPROVED', "updatedAt" = $2
       WHERE id = $1 AND status = 'PENDING_ACC' AND "updatedAt" = $3
       RETURNING id`,
      ['offset-race', t1, t0],
    );
    assert.equal(approved.rowCount, 1);
    await batch.query(
      `INSERT INTO ${offsetHistoryTable} (id, "adjustmentId", action)
       VALUES ($1 || '-batch-history', $1, 'COMPLETED')`,
      ['offset-race'],
    );

    await single.query('BEGIN');
    const singleAttempt = (async () => {
      const result = await single.query(
        `UPDATE ${offsetTable}
         SET status = $2, "updatedAt" = $3
         WHERE id = $1 AND status = 'PENDING_ACC' AND "updatedAt" = $4
         RETURNING id`,
        [
          'offset-race',
          action === 'complete' ? 'APPROVED' : 'REJECTED_NEEDS_FIX',
          t2,
          t0,
        ],
      );
      if (result.rowCount !== 1) {
        await single.query('ROLLBACK');
        return 'conflict';
      }
      await single.query(
        `INSERT INTO ${offsetHistoryTable} (id, "adjustmentId", action)
         VALUES ($1 || '-single-history', $1, $2)`,
        ['offset-race', action === 'complete' ? 'COMPLETED' : 'REJECTED'],
      );
      await single.query('COMMIT');
      events.push(`single_${action}`);
      return 'updated';
    })();

    await assertStillBlocked(singleAttempt, `stale single ${action}`);
    await batch.query('COMMIT');
    events.push('batch_complete');
    assert.equal(await singleAttempt, 'conflict');

    const [row, history] = await Promise.all([
      pool.query(`SELECT status FROM ${offsetTable} WHERE id = $1`, [
        'offset-race',
      ]),
      pool.query(
        `SELECT action FROM ${offsetHistoryTable} WHERE "adjustmentId" = $1`,
        ['offset-race'],
      ),
    ]);
    assert.equal(row.rows[0].status, 'APPROVED');
    assert.deepEqual(
      history.rows.map((item) => item.action),
      ['COMPLETED'],
    );
    assert.deepEqual(events, ['batch_complete']);
  } finally {
    if (!batch.released) await batch.query('ROLLBACK').catch(() => undefined);
    if (!single.released) await single.query('ROLLBACK').catch(() => undefined);
    batch.release();
    single.release();
  }
}

async function statementRefollowAfterNoopBatch() {
  await resetStatementRows([
    { id: 'statement-race', status: 'UNFOLLOWED', updatedAt: t0 },
  ]);
  const before = await pool.query(
    `SELECT t."bigQueryRevision"::text AS revision,
            COUNT(event.id)::int AS event_count
     FROM ${statementTable} AS t
     LEFT JOIN "DomainOutboxEvent" AS event
       ON event."aggregateId" = t.id
      AND event."eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION'
     WHERE t.id = $1
     GROUP BY t."bigQueryRevision"`,
    ['statement-race'],
  );
  assert.equal(before.rowCount, 1);
  const batch = await pool.connect();
  const refollow = await pool.connect();
  try {
    await batch.query('BEGIN');
    await batch.query(
      `SELECT id FROM ${statementTable} WHERE id = $1 FOR UPDATE`,
      ['statement-race'],
    );
    const tokenBump = await batch.query(
      `UPDATE ${statementTable}
       SET "updatedAt" = $2
       WHERE id = $1 AND "orderTrackingStatus" = 'UNFOLLOWED'
         AND "updatedAt" = $3
       RETURNING id`,
      ['statement-race', t1, t0],
    );
    assert.equal(tokenBump.rowCount, 1);

    await refollow.query('BEGIN');
    const refollowAttempt = (async () => {
      const result = await refollow.query(
        `UPDATE ${statementTable}
         SET "orderTrackingStatus" = 'FOLLOWING', "updatedAt" = $2
         WHERE id = $1 AND "orderTrackingStatus" = 'UNFOLLOWED'
           AND "updatedAt" = $3
         RETURNING id`,
        ['statement-race', t2, t0],
      );
      await refollow.query(result.rowCount === 1 ? 'COMMIT' : 'ROLLBACK');
      return result.rowCount === 1 ? 'updated' : 'conflict';
    })();

    await assertStillBlocked(refollowAttempt, 'statement re-follow');
    await batch.query('COMMIT');
    assert.equal(await refollowAttempt, 'conflict');

    const [row, audit, after] = await Promise.all([
      pool.query(
        `SELECT "orderTrackingStatus", "updatedAt"
         FROM ${statementTable} WHERE id = $1`,
        ['statement-race'],
      ),
      pool.query(
        `SELECT "oldStatus", "newStatus" FROM ${statementAuditTable}
         WHERE "transactionId" = $1`,
        ['statement-race'],
      ),
      pool.query(
        `SELECT t."bigQueryRevision"::text AS revision,
                COUNT(event.id)::int AS event_count
         FROM ${statementTable} AS t
         LEFT JOIN "DomainOutboxEvent" AS event
           ON event."aggregateId" = t.id
          AND event."eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION'
         WHERE t.id = $1
         GROUP BY t."bigQueryRevision"`,
        ['statement-race'],
      ),
    ]);
    assert.equal(row.rows[0].orderTrackingStatus, 'UNFOLLOWED');
    assert.equal(new Date(row.rows[0].updatedAt).getTime(), t1.getTime());
    assert.deepEqual(audit.rows, []);
    assert.deepEqual(after.rows, before.rows);
  } finally {
    await batch.query('ROLLBACK').catch(() => undefined);
    await refollow.query('ROLLBACK').catch(() => undefined);
    batch.release();
    refollow.release();
  }
}

async function offsetBatchRollback() {
  await resetOffsetRows([
    { id: 'offset-a', status: 'PENDING_ACC', updatedAt: t0 },
    { id: 'offset-b', status: 'PENDING_ACC', updatedAt: t1 },
  ]);
  const client = await pool.connect();
  const events = [];
  try {
    await client.query('BEGIN');
    await client.query(
      `SELECT id FROM ${offsetTable}
       WHERE id = ANY($1::text[]) ORDER BY id FOR UPDATE`,
      [['offset-a', 'offset-b']],
    );
    for (const id of ['offset-a', 'offset-b']) {
      const updated = await client.query(
        `UPDATE ${offsetTable}
         SET status = 'APPROVED', "updatedAt" = $2
         WHERE id = $1 AND status = 'PENDING_ACC' AND "updatedAt" = $3
         RETURNING id`,
        [id, t2, t0],
      );
      if (updated.rowCount !== 1) throw new Error('stale offset snapshot');
      await client.query(
        `INSERT INTO ${offsetHistoryTable} (id, "adjustmentId", action)
         VALUES ($1 || '-history', $1, 'COMPLETED')`,
        [id],
      );
    }
    await client.query('COMMIT');
    events.push('offset-a', 'offset-b');
    assert.fail('mixed stale offset batch should not commit');
  } catch (error) {
    await client.query('ROLLBACK');
    assert.match(String(error), /stale offset snapshot/);
  } finally {
    client.release();
  }

  const [rows, history] = await Promise.all([
    pool.query(`SELECT status FROM ${offsetTable} ORDER BY id`),
    pool.query(`SELECT action FROM ${offsetHistoryTable}`),
  ]);
  assert.deepEqual(
    rows.rows.map((row) => row.status),
    ['PENDING_ACC', 'PENDING_ACC'],
  );
  assert.equal(history.rowCount, 0);
  assert.deepEqual(events, []);
}

async function statementBatchRollback() {
  await resetStatementRows([
    { id: 'statement-a', status: 'FOLLOWING', updatedAt: t0 },
    { id: 'statement-b', status: 'FOLLOWING', updatedAt: t1 },
  ]);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `SELECT id FROM ${statementTable}
       WHERE id = ANY($1::text[]) ORDER BY id FOR UPDATE`,
      [['statement-a', 'statement-b']],
    );
    for (const id of ['statement-a', 'statement-b']) {
      const updated = await client.query(
        `UPDATE ${statementTable}
         SET "orderTrackingStatus" = 'UNFOLLOWED', "updatedAt" = $2
         WHERE id = $1 AND "orderTrackingStatus" = 'FOLLOWING'
           AND "updatedAt" = $3
         RETURNING id`,
        [id, t2, t0],
      );
      if (updated.rowCount !== 1) throw new Error('stale statement snapshot');
      await client.query(
        `INSERT INTO ${statementAuditTable}
         (id, "transactionId", "oldStatus", "newStatus")
         VALUES ($1 || '-audit', $1, 'FOLLOWING', 'UNFOLLOWED')`,
        [id],
      );
    }
    await client.query('COMMIT');
    assert.fail('mixed stale statement batch should not commit');
  } catch (error) {
    await client.query('ROLLBACK');
    assert.match(String(error), /stale statement snapshot/);
  } finally {
    client.release();
  }

  const [rows, audit] = await Promise.all([
    pool.query(
      `SELECT "orderTrackingStatus" FROM ${statementTable} ORDER BY id`,
    ),
    pool.query(`SELECT "oldStatus", "newStatus" FROM ${statementAuditTable}`),
  ]);
  assert.deepEqual(
    rows.rows.map((row) => row.orderTrackingStatus),
    ['FOLLOWING', 'FOLLOWING'],
  );
  assert.equal(audit.rowCount, 0);
}

try {
  await setup();
  await offsetSingleAfterBatch('complete');
  await offsetSingleAfterBatch('reject');
  await statementRefollowAfterNoopBatch();
  await offsetBatchRollback();
  await statementBatchRollback();
  process.stdout.write(
    `${JSON.stringify({
      ok: true,
      database: databaseName,
      independentClients: true,
      offsetSingleBatchRaces: 2,
      statementNoopRefollowBatchRaces: 1,
      atomicRollbackScenarios: 2,
      durationMs: Date.now() - startedAt,
    })}\n`,
  );
} finally {
  await pool.end();
}
