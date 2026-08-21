import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const connectionString = process.env.OPS39_POSTGRES_URL?.trim();
if (!connectionString)
  throw new Error(
    'Set OPS39_POSTGRES_URL to a disposable loopback PostgreSQL database.',
  );
const parsed = new URL(connectionString);
const database = decodeURIComponent(parsed.pathname.replace(/^\//, ''));
if (!new Set(['127.0.0.1', 'localhost', '::1']).has(parsed.hostname)) {
  throw new Error('OPS-39 PostgreSQL proof accepts loopback only.');
}
if (!/^opshub_ops39_proof(?:_|$)/i.test(database)) {
  throw new Error('OPS39_POSTGRES_URL must target opshub_ops39_proof*.');
}

const backendRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);
const migration = spawnSync(
  process.execPath,
  [path.join(backendRoot, 'scripts', 'run-prisma-migrate-deploy.mjs')],
  {
    cwd: backendRoot,
    env: { ...process.env, DATABASE_URL: connectionString },
    encoding: 'utf8',
  },
);
if (migration.status !== 0)
  throw new Error(
    migration.stderr || migration.stdout || 'Prisma migration failed',
  );

const pool = new pg.Pool({ connectionString, max: 2 });
try {
  const initial = await pool.query(
    `SELECT "operatingMode"::text, "ingressEnabled", "projectionEnabled"
     FROM "BankConnectionControl" WHERE "bankCode" = 'BIDV'`,
  );
  assert.deepEqual(initial.rows[0], {
    operatingMode: 'STOPPED',
    ingressEnabled: false,
    projectionEnabled: false,
  });

  const uat = await pool.query(
    `UPDATE "BankConnectionControl" SET "operatingMode" = 'UAT_INGEST_ONLY'
     WHERE "bankCode" = 'BIDV'
     RETURNING "operatingMode"::text, "ingressEnabled", "projectionEnabled"`,
  );
  assert.deepEqual(uat.rows[0], {
    operatingMode: 'UAT_INGEST_ONLY',
    ingressEnabled: true,
    projectionEnabled: false,
  });

  const legacyLive = await pool.query(
    `UPDATE "BankConnectionControl" SET "ingressEnabled" = true, "projectionEnabled" = true
     WHERE "bankCode" = 'BIDV' RETURNING "operatingMode"::text`,
  );
  assert.equal(legacyLive.rows[0].operatingMode, 'LIVE');
  await assert.rejects(
    pool.query(
      `UPDATE "BankConnectionControl" SET "ingressEnabled" = false, "projectionEnabled" = true
       WHERE "bankCode" = 'BIDV'`,
    ),
    /Projection cannot be enabled while ingress is disabled/,
  );
  console.log('OPS-39 PostgreSQL operating-mode trigger PASS');
} finally {
  await pool
    .query(
      `UPDATE "BankConnectionControl" SET "operatingMode" = 'STOPPED',
       "ingressEnabled" = false, "projectionEnabled" = false WHERE "bankCode" = 'BIDV'`,
    )
    .catch(() => undefined);
  await pool.end();
}
