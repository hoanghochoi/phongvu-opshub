import { spawnSync } from 'node:child_process';

import { Client } from 'pg';

const migrationName = process.argv[2];

if (!migrationName) {
  console.error('Usage: node scripts/recover-failed-prisma-migration.mjs <migration_name>');
  process.exit(2);
}

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
  console.error('DATABASE_URL is required to inspect Prisma migration state.');
  process.exit(2);
}

const client = new Client({ connectionString: databaseUrl });
let clientClosed = false;

try {
  await client.connect();
  const result = await client.query(
    `
      SELECT "migration_name", "finished_at", "rolled_back_at"
      FROM "_prisma_migrations"
      WHERE "migration_name" = $1
      ORDER BY "started_at" DESC
      LIMIT 1
    `,
    [migrationName],
  );

  const migration = result.rows[0];
  if (!migration) {
    console.log(`Prisma migration recovery skipped: ${migrationName} has no migration record.`);
    process.exitCode = 0;
  } else if (migration.finished_at || migration.rolled_back_at) {
    console.log(`Prisma migration recovery skipped: ${migrationName} is not in failed state.`);
    process.exitCode = 0;
  } else {
    console.log(`Prisma migration recovery started: marking ${migrationName} as rolled back.`);
    await client.end();
    clientClosed = true;

    const resolved = spawnSync(
      'npx',
      ['prisma', 'migrate', 'resolve', '--rolled-back', migrationName],
      { stdio: 'inherit' },
    );

    if (resolved.error) {
      console.error(resolved.error.message);
      process.exitCode = 1;
    } else {
      process.exitCode = resolved.status ?? 1;
    }
  }
} catch (error) {
  console.error(`Prisma migration recovery failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  if (!clientClosed) {
    await client.end().catch(() => undefined);
  }
}
