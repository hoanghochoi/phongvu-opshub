-- OPS-40 expand-only Support Chat Phase 1 persistence.
CREATE TABLE "SupportConversation" (
  "id" TEXT NOT NULL,
  "requesterId" TEXT,
  "assigneeId" TEXT,
  "status" TEXT NOT NULL DEFAULT 'OPEN',
  "revision" BIGINT NOT NULL DEFAULT 0,
  "lastMessageSequence" BIGINT NOT NULL DEFAULT 0,
  "unassignedSince" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,
  "lastMessageAt" TIMESTAMP(3),
  "resolvedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SupportConversation_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "SupportConversation_status_check" CHECK ("status" IN ('OPEN', 'RESOLVED')),
  CONSTRAINT "SupportConversation_revision_check" CHECK ("revision" >= 0),
  CONSTRAINT "SupportConversation_sequence_check" CHECK ("lastMessageSequence" >= 0)
);

CREATE UNIQUE INDEX "SupportConversation_requesterId_key"
  ON "SupportConversation"("requesterId");
CREATE INDEX "SupportConversation_status_assigneeId_unassignedSince_id_idx"
  ON "SupportConversation"("status", "assigneeId", "unassignedSince", "id");
CREATE INDEX "SupportConversation_status_assigneeId_lastMessageAt_id_idx"
  ON "SupportConversation"("status", "assigneeId", "lastMessageAt", "id");
CREATE INDEX "SupportConversation_status_lastMessageAt_id_idx"
  ON "SupportConversation"("status", "lastMessageAt", "id");
CREATE INDEX "SupportConversation_status_resolvedAt_id_idx"
  ON "SupportConversation"("status", "resolvedAt", "id");

ALTER TABLE "SupportConversation"
  ADD CONSTRAINT "SupportConversation_requesterId_fkey"
  FOREIGN KEY ("requesterId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "SupportConversation"
  ADD CONSTRAINT "SupportConversation_assigneeId_fkey"
  FOREIGN KEY ("assigneeId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "SupportMessage" (
  "id" TEXT NOT NULL,
  "conversationId" TEXT NOT NULL,
  "senderId" TEXT,
  "senderRole" TEXT NOT NULL,
  "sequence" BIGINT NOT NULL,
  "clientMessageId" TEXT NOT NULL,
  "contentType" TEXT NOT NULL,
  "text" TEXT,
  "mediaIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SupportMessage_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "SupportMessage_sequence_check" CHECK ("sequence" > 0),
  CONSTRAINT "SupportMessage_client_id_check" CHECK (char_length("clientMessageId") BETWEEN 1 AND 64),
  CONSTRAINT "SupportMessage_content_check" CHECK (
    ("contentType" = 'TEXT' AND "text" IS NOT NULL AND cardinality("mediaIds") = 0) OR
    ("contentType" = 'IMAGE' AND "text" IS NULL AND cardinality("mediaIds") BETWEEN 1 AND 4)
  )
);

CREATE UNIQUE INDEX "SupportMessage_conversationId_sequence_key"
  ON "SupportMessage"("conversationId", "sequence");
CREATE UNIQUE INDEX "SupportMessage_conversationId_senderId_clientMessageId_key"
  ON "SupportMessage"("conversationId", "senderId", "clientMessageId");
CREATE INDEX "SupportMessage_conversationId_createdAt_idx"
  ON "SupportMessage"("conversationId", "createdAt");
CREATE INDEX "SupportMessage_senderId_createdAt_idx"
  ON "SupportMessage"("senderId", "createdAt");

ALTER TABLE "SupportMessage"
  ADD CONSTRAINT "SupportMessage_conversationId_fkey"
  FOREIGN KEY ("conversationId") REFERENCES "SupportConversation"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SupportMessage"
  ADD CONSTRAINT "SupportMessage_senderId_fkey"
  FOREIGN KEY ("senderId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "SupportReadReceipt" (
  "id" TEXT NOT NULL,
  "conversationId" TEXT NOT NULL,
  "readerId" TEXT NOT NULL,
  "lastReadSequence" BIGINT NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SupportReadReceipt_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "SupportReadReceipt_sequence_check" CHECK ("lastReadSequence" >= 0)
);

CREATE UNIQUE INDEX "SupportReadReceipt_conversationId_readerId_key"
  ON "SupportReadReceipt"("conversationId", "readerId");
CREATE INDEX "SupportReadReceipt_readerId_updatedAt_idx"
  ON "SupportReadReceipt"("readerId", "updatedAt");

ALTER TABLE "SupportReadReceipt"
  ADD CONSTRAINT "SupportReadReceipt_conversationId_fkey"
  FOREIGN KEY ("conversationId") REFERENCES "SupportConversation"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SupportReadReceipt"
  ADD CONSTRAINT "SupportReadReceipt_readerId_fkey"
  FOREIGN KEY ("readerId") REFERENCES "User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "SupportAuditEvent" (
  "id" TEXT NOT NULL,
  "conversationId" TEXT NOT NULL,
  "actorId" TEXT,
  "action" TEXT NOT NULL,
  "previousAssigneeId" TEXT,
  "nextAssigneeId" TEXT,
  "previousStatus" TEXT,
  "nextStatus" TEXT,
  "messageSequence" BIGINT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SupportAuditEvent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "SupportAuditEvent_conversationId_createdAt_idx"
  ON "SupportAuditEvent"("conversationId", "createdAt");
CREATE INDEX "SupportAuditEvent_actorId_createdAt_idx"
  ON "SupportAuditEvent"("actorId", "createdAt");
CREATE INDEX "SupportAuditEvent_createdAt_idx"
  ON "SupportAuditEvent"("createdAt");

ALTER TABLE "SupportAuditEvent"
  ADD CONSTRAINT "SupportAuditEvent_conversationId_fkey"
  FOREIGN KEY ("conversationId") REFERENCES "SupportConversation"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SupportAuditEvent"
  ADD CONSTRAINT "SupportAuditEvent_actorId_fkey"
  FOREIGN KEY ("actorId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX "DomainOutboxEvent_support_chat_claim_idx"
  ON "DomainOutboxEvent"("availableAt", "leaseExpiresAt", "occurredAt")
  WHERE "eventType" = 'SUPPORT_CHAT_UPDATED'
    AND "publishedAt" IS NULL
    AND "deadLetteredAt" IS NULL;
