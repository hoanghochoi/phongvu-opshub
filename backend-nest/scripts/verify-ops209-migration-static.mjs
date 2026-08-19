import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migrationDir = resolve(
  'prisma',
  'migrations',
  '20260819090000_contract_appendix_multi_order',
);
const forward = readFileSync(resolve(migrationDir, 'migration.sql'), 'utf8');
const rollback = readFileSync(resolve(migrationDir, 'rollback.sql'), 'utf8');

for (const fragment of [
  'ADD COLUMN "orderCodes" TEXT[]',
  'ADD COLUMN "erpRowTotal" BIGINT',
  'ADD COLUMN "sourceOrderCodes" TEXT[]',
  'ADD COLUMN "sourceLineIdentities" TEXT[]',
  'CREATE TABLE "contract_appendix_source_orders"',
  'contract_appendix_source_orders_contractAppendixId_fkey',
  'contract_appendix_source_orders_contractAppendixId_position_key',
  'UPDATE "contract_appendices"',
  'ARRAY["orderCode"]',
  '"erpRowTotal" = i."lineAfterVat"',
  '"sourceLineIdentities" = ARRAY[i."sourceLineKey"]',
]) {
  assert.ok(forward.includes(fragment), `forward migration missing ${fragment}`);
}

assert.match(
  forward,
  /FOREIGN KEY \("contractAppendixId"\) REFERENCES "contract_appendices"\("id"\)\s+ON DELETE CASCADE ON UPDATE CASCADE/,
);
assert.match(
  forward,
  /"erpRowTotal" IS NULL OR "erpRowTotal" >= 0/,
  'ERP row total must be non-negative when present',
);
assert.ok(
  rollback.indexOf('DROP TABLE IF EXISTS "contract_appendix_source_orders"') >= 0,
  'rollback must remove only the additive source-order table',
);
for (const column of [
  '"sourceLineIdentities"',
  '"sourceOrderCodes"',
  '"erpRowTotal"',
  '"orderCodes"',
]) {
  assert.ok(rollback.includes(`DROP COLUMN IF EXISTS ${column}`), `rollback missing ${column}`);
}
assert.doesNotMatch(
  rollback,
  /DROP TABLE IF EXISTS "(?:User|contract_appendices|contract_appendix_items)"/,
  'rollback must preserve legacy snapshots and shared tables',
);

console.log('OPS-209 migration static/rollback contract: PASS');
