import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migrationDir = resolve(
  'prisma',
  'migrations',
  '20260801090000_support_chat_phase1',
);
const forward = readFileSync(resolve(migrationDir, 'migration.sql'), 'utf8');
const rollback = readFileSync(resolve(migrationDir, 'rollback.sql'), 'utf8');

for (const fragment of [
  'CREATE TABLE "SupportConversation"',
  'CREATE TABLE "SupportMessage"',
  'CREATE TABLE "SupportReadReceipt"',
  'CREATE TABLE "SupportAuditEvent"',
  'SupportConversation_requesterId_key',
  'SupportConversation_status_assigneeId_unassignedSince_id_idx',
  'SupportConversation_status_resolvedAt_id_idx',
  'SupportMessage_conversationId_sequence_key',
  'SupportMessage_conversationId_senderId_clientMessageId_key',
  'DomainOutboxEvent_support_chat_claim_idx',
  'WHERE "eventType" = \'SUPPORT_CHAT_UPDATED\'',
  'ON DELETE CASCADE',
  'ON DELETE SET NULL',
]) {
  assert.ok(
    forward.includes(fragment),
    `forward migration missing ${fragment}`,
  );
}
assert.match(
  forward,
  /"requesterId" TEXT,[\s\S]*?SupportConversation_requesterId_fkey[\s\S]*?ON DELETE SET NULL ON UPDATE CASCADE/,
  'requester deletion must preserve the retained conversation',
);

assert.ok(
  rollback.indexOf('DELETE FROM "DomainOutboxEvent"') <
    rollback.indexOf('DROP TABLE IF EXISTS "SupportConversation"'),
  'rollback must remove support outbox rows before the aggregate tables',
);
for (const table of [
  'SupportAuditEvent',
  'SupportReadReceipt',
  'SupportMessage',
  'SupportConversation',
]) {
  assert.ok(
    rollback.includes(`DROP TABLE IF EXISTS "${table}"`),
    `rollback missing ${table}`,
  );
}
assert.ok(
  !/DROP TABLE IF EXISTS "(?:User|MediaObject|DomainOutboxEvent)"/.test(
    rollback,
  ),
  'rollback must preserve shared tables',
);

console.log('OPS-40 migration static contract PASS');
