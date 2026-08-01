-- Scratch/staging rollback rehearsal only. Production rollback is feature-off.
DROP INDEX IF EXISTS "DomainOutboxEvent_support_chat_claim_idx";
DELETE FROM "DomainOutboxEvent" WHERE "eventType" = 'SUPPORT_CHAT_UPDATED';
DROP TABLE IF EXISTS "SupportAuditEvent";
DROP TABLE IF EXISTS "SupportReadReceipt";
DROP TABLE IF EXISTS "SupportMessage";
DROP TABLE IF EXISTS "SupportConversation";
