import assert from 'node:assert/strict';
import fs from 'node:fs';

const migrationPath =
  'prisma/migrations/20260730153000_ops39_bidv_h2h/migration.sql';
const rollbackPath =
  'prisma/migrations/20260730153000_ops39_bidv_h2h/rollback.sql';
const migration = fs.readFileSync(migrationPath, 'utf8');
const rollback = fs.readFileSync(rollbackPath, 'utf8');

for (const table of [
  'BankApiClient',
  'BankAccessToken',
  'BankPgpKey',
  'BankConnectionAudit',
  'BankConnectionControl',
  'BankIngressReceipt',
  'BankTransaction',
]) {
  assert.match(migration, new RegExp(`CREATE TABLE "${table}"`));
}
assert.match(migration, /DECIMAL\(24,6\)/);
assert.match(
  migration,
  /BankIngressReceipt_bankCode_requestId_key/,
  'REQUESTID idempotency constraint is required',
);
assert.match(migration, /BankTransaction_identityHash_payloadHash_key/);
assert.match(migration, /BankConnectionAudit_immutable_update/);
assert.match(migration, /BankConnectionAudit_immutable_delete/);
assert.match(migration, /opshub_map_vietin_bigquery_payload/);
assert.doesNotMatch(
  migration,
  /JWT_SECRET|MAP_VIETIN_PASSWORD|AdminSetting|PRIVATE KEY BLOCK/,
);
assert.match(rollback, /"ingressEnabled" = false/);
assert.match(rollback, /"projectionEnabled" = false/);
assert.doesNotMatch(rollback, /\bDROP\b|\bDELETE\b|\bTRUNCATE\b/i);

console.log('OPS-39 migration static/rollback contract: PASS');
