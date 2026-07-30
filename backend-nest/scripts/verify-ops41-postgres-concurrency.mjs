import assert from 'node:assert/strict';
import process from 'node:process';

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

const schemaName = `ops41_proof_${process.pid}_${Date.now()}`;
const schema = `"${schemaName}"`;
const pool = new Pool({ connectionString, max: 5 });

const offsetTable = `${schema}.offset_adjustment`;
const offsetHistoryTable = `${schema}.offset_history`;
const statementTable = `${schema}.statement_transaction`;
const statementAuditTable = `${schema}.statement_audit`;

const t0 = new Date('2026-07-30T03:00:00.000Z');
const t1 = new Date('2026-07-30T03:01:00.000Z');
const t2 = new Date('2026-07-30T03:02:00.000Z');

async function setup() {
  await pool.query(`CREATE SCHEMA ${schema}`);
  await pool.query(`
    CREATE TABLE ${offsetTable} (
      id TEXT PRIMARY KEY,
      status TEXT NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE ${offsetHistoryTable} (
      id BIGSERIAL PRIMARY KEY,
      adjustment_id TEXT NOT NULL,
      action TEXT NOT NULL
    );
    CREATE TABLE ${statementTable} (
      id TEXT PRIMARY KEY,
      tracking_status TEXT NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE ${statementAuditTable} (
      id BIGSERIAL PRIMARY KEY,
      transaction_id TEXT NOT NULL,
      old_status TEXT NOT NULL,
      new_status TEXT NOT NULL
    );
  `);
}

async function resetOffsetRows(rows) {
  await pool.query(`TRUNCATE ${offsetHistoryTable}, ${offsetTable}`);
  for (const row of rows) {
    await pool.query(
      `INSERT INTO ${offsetTable} (id, status, updated_at) VALUES ($1, $2, $3)`,
      [row.id, row.status, row.updatedAt],
    );
  }
}

async function resetStatementRows(rows) {
  await pool.query(`TRUNCATE ${statementAuditTable}, ${statementTable}`);
  for (const row of rows) {
    await pool.query(
      `INSERT INTO ${statementTable} (id, tracking_status, updated_at) VALUES ($1, $2, $3)`,
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
       SET status = 'APPROVED', updated_at = $2
       WHERE id = $1 AND status = 'PENDING_ACC' AND updated_at = $3
       RETURNING id`,
      ['offset-race', t1, t0],
    );
    assert.equal(approved.rowCount, 1);
    await batch.query(
      `INSERT INTO ${offsetHistoryTable} (adjustment_id, action)
       VALUES ($1, 'COMPLETED')`,
      ['offset-race'],
    );

    await single.query('BEGIN');
    const singleAttempt = (async () => {
      const result = await single.query(
        `UPDATE ${offsetTable}
         SET status = $2, updated_at = $3
         WHERE id = $1 AND status = 'PENDING_ACC' AND updated_at = $4
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
        `INSERT INTO ${offsetHistoryTable} (adjustment_id, action)
         VALUES ($1, $2)`,
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
        `SELECT action FROM ${offsetHistoryTable} WHERE adjustment_id = $1`,
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

async function statementRefollowAfterBatch() {
  await resetStatementRows([
    { id: 'statement-race', status: 'FOLLOWING', updatedAt: t0 },
  ]);
  const batch = await pool.connect();
  const refollow = await pool.connect();
  try {
    await batch.query('BEGIN');
    await batch.query(
      `SELECT id FROM ${statementTable} WHERE id = $1 FOR UPDATE`,
      ['statement-race'],
    );
    const unfollowed = await batch.query(
      `UPDATE ${statementTable}
       SET tracking_status = 'UNFOLLOWED', updated_at = $2
       WHERE id = $1 AND tracking_status = 'FOLLOWING' AND updated_at = $3
       RETURNING id`,
      ['statement-race', t1, t0],
    );
    assert.equal(unfollowed.rowCount, 1);
    await batch.query(
      `INSERT INTO ${statementAuditTable}
       (transaction_id, old_status, new_status)
       VALUES ($1, 'FOLLOWING', 'UNFOLLOWED')`,
      ['statement-race'],
    );

    await refollow.query('BEGIN');
    const refollowAttempt = (async () => {
      const result = await refollow.query(
        `UPDATE ${statementTable}
         SET tracking_status = 'FOLLOWING', updated_at = $2
         WHERE id = $1 AND tracking_status = 'FOLLOWING' AND updated_at = $3
         RETURNING id`,
        ['statement-race', t2, t0],
      );
      await refollow.query(result.rowCount === 1 ? 'COMMIT' : 'ROLLBACK');
      return result.rowCount === 1 ? 'updated' : 'conflict';
    })();

    await assertStillBlocked(refollowAttempt, 'statement re-follow');
    await batch.query('COMMIT');
    assert.equal(await refollowAttempt, 'conflict');

    const [row, audit] = await Promise.all([
      pool.query(
        `SELECT tracking_status FROM ${statementTable} WHERE id = $1`,
        ['statement-race'],
      ),
      pool.query(
        `SELECT old_status, new_status FROM ${statementAuditTable}
         WHERE transaction_id = $1`,
        ['statement-race'],
      ),
    ]);
    assert.equal(row.rows[0].tracking_status, 'UNFOLLOWED');
    assert.deepEqual(audit.rows, [
      { old_status: 'FOLLOWING', new_status: 'UNFOLLOWED' },
    ]);
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
         SET status = 'APPROVED', updated_at = $2
         WHERE id = $1 AND status = 'PENDING_ACC' AND updated_at = $3
         RETURNING id`,
        [id, t2, t0],
      );
      if (updated.rowCount !== 1) throw new Error('stale offset snapshot');
      await client.query(
        `INSERT INTO ${offsetHistoryTable} (adjustment_id, action)
         VALUES ($1, 'COMPLETED')`,
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
         SET tracking_status = 'UNFOLLOWED', updated_at = $2
         WHERE id = $1 AND tracking_status = 'FOLLOWING' AND updated_at = $3
         RETURNING id`,
        [id, t2, t0],
      );
      if (updated.rowCount !== 1) throw new Error('stale statement snapshot');
      await client.query(
        `INSERT INTO ${statementAuditTable}
         (transaction_id, old_status, new_status)
         VALUES ($1, 'FOLLOWING', 'UNFOLLOWED')`,
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
    pool.query(`SELECT tracking_status FROM ${statementTable} ORDER BY id`),
    pool.query(`SELECT old_status, new_status FROM ${statementAuditTable}`),
  ]);
  assert.deepEqual(
    rows.rows.map((row) => row.tracking_status),
    ['FOLLOWING', 'FOLLOWING'],
  );
  assert.equal(audit.rowCount, 0);
}

try {
  await setup();
  await offsetSingleAfterBatch('complete');
  await offsetSingleAfterBatch('reject');
  await statementRefollowAfterBatch();
  await offsetBatchRollback();
  await statementBatchRollback();
  process.stdout.write(
    `${JSON.stringify({
      ok: true,
      database: databaseName,
      independentClients: true,
      offsetSingleBatchRaces: 2,
      statementRefollowBatchRaces: 1,
      atomicRollbackScenarios: 2,
      durationMs: Date.now() - startedAt,
    })}\n`,
  );
} finally {
  await pool
    .query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`)
    .catch(() => undefined);
  await pool.end();
}
