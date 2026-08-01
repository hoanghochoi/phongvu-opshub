-- OPS-39 expand-only canonical bank ingress and managed H2H credentials.
ALTER TABLE "MapVietinTransaction"
  ADD COLUMN "bankSource" TEXT NOT NULL DEFAULT 'VIETIN',
  ADD COLUMN "currency" TEXT NOT NULL DEFAULT 'VND',
  ADD COLUMN "direction" TEXT NOT NULL DEFAULT 'C',
  ADD COLUMN "exactAmount" DECIMAL(24,6),
  ADD COLUMN "canonicalBankTransactionId" TEXT;

UPDATE "MapVietinTransaction"
SET "exactAmount" = "amount"::DECIMAL(24,6)
WHERE "exactAmount" IS NULL;

CREATE UNIQUE INDEX "MapVietinTransaction_canonicalBankTransactionId_key"
  ON "MapVietinTransaction"("canonicalBankTransactionId");

CREATE OR REPLACE FUNCTION "opshub_map_vietin_bigquery_payload"(
  transaction_row "MapVietinTransaction",
  revision_value BIGINT,
  deleted_value BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN jsonb_build_object(
    'transaction_id', transaction_row."id",
    'revision', revision_value::text,
    'transaction_date', to_char(
      (
        (COALESCE(transaction_row."paidAt", transaction_row."firstSeenAt") AT TIME ZONE 'UTC')
        AT TIME ZONE 'Asia/Ho_Chi_Minh'
      )::date,
      'YYYY-MM-DD'
    ),
    'store_code', transaction_row."storeCode",
    'statement_number', COALESCE(
      NULLIF(transaction_row."rawData" #>> '{providerIdentifiers,efastTrxId}', ''),
      NULLIF(transaction_row."rawData" #>> '{providerIdentifiers,mapTransactionNumber}', ''),
      NULLIF(transaction_row."transactionNumber", '')
    ),
    'amount', transaction_row."amount",
    'orders', to_jsonb(transaction_row."orders"),
    'order_source', transaction_row."orderSource",
    'order_tracking_status', transaction_row."orderTrackingStatus",
    'status', "opshub_map_vietin_bigquery_canonical_status"(transaction_row."status"),
    'paid_at', CASE
      WHEN transaction_row."paidAt" IS NULL THEN NULL
      ELSE to_char(transaction_row."paidAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    END,
    'income_type', transaction_row."incomeType",
    'provider_source', "opshub_map_vietin_bigquery_provider_source"(transaction_row."rawData"),
    'bank_source', transaction_row."bankSource",
    'currency', transaction_row."currency",
    'direction', transaction_row."direction",
    'exact_amount', COALESCE(transaction_row."exactAmount", transaction_row."amount"::DECIMAL(24,6))::text,
    'first_seen_at', to_char(transaction_row."firstSeenAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source_created_at', to_char(transaction_row."createdAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source_updated_at', to_char(transaction_row."updatedAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'is_deleted', deleted_value
  );
END;
$$;

CREATE TABLE "BankApiClient" (
  "id" TEXT NOT NULL,
  "displayName" TEXT NOT NULL,
  "bankCode" TEXT NOT NULL DEFAULT 'BIDV',
  "clientId" TEXT NOT NULL,
  "secretHash" TEXT NOT NULL,
  "scope" TEXT NOT NULL DEFAULT 'balance-changes:write',
  "status" TEXT NOT NULL DEFAULT 'ACTIVE',
  "version" INTEGER NOT NULL DEFAULT 1,
  "activatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "overlapExpiresAt" TIMESTAMP(3),
  "revokedAt" TIMESTAMP(3),
  "createdByUserId" TEXT,
  "createdByEmailHash" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "BankApiClient_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "BankApiClient_clientId_key" ON "BankApiClient"("clientId");
CREATE INDEX "BankApiClient_bankCode_status_activatedAt_idx" ON "BankApiClient"("bankCode", "status", "activatedAt");

CREATE TABLE "BankAccessToken" (
  "id" TEXT NOT NULL,
  "clientRefId" TEXT NOT NULL,
  "tokenHash" TEXT NOT NULL,
  "scope" TEXT NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "revokedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "BankAccessToken_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "BankAccessToken_tokenHash_key" ON "BankAccessToken"("tokenHash");
CREATE INDEX "BankAccessToken_clientRefId_expiresAt_idx" ON "BankAccessToken"("clientRefId", "expiresAt");
CREATE INDEX "BankAccessToken_expiresAt_revokedAt_idx" ON "BankAccessToken"("expiresAt", "revokedAt");
ALTER TABLE "BankAccessToken" ADD CONSTRAINT "BankAccessToken_clientRefId_fkey"
  FOREIGN KEY ("clientRefId") REFERENCES "BankApiClient"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "BankPgpKey" (
  "id" TEXT NOT NULL,
  "displayName" TEXT NOT NULL,
  "bankCode" TEXT NOT NULL DEFAULT 'BIDV',
  "fingerprint" TEXT NOT NULL,
  "algorithm" TEXT NOT NULL,
  "publicKeyArmor" TEXT NOT NULL,
  "privateKeyCipher" TEXT NOT NULL,
  "envelopeVersion" INTEGER NOT NULL DEFAULT 1,
  "status" TEXT NOT NULL DEFAULT 'ACTIVE',
  "version" INTEGER NOT NULL DEFAULT 1,
  "activatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "overlapExpiresAt" TIMESTAMP(3),
  "revokedAt" TIMESTAMP(3),
  "createdByUserId" TEXT,
  "createdByEmailHash" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "BankPgpKey_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "BankPgpKey_fingerprint_key" ON "BankPgpKey"("fingerprint");
CREATE INDEX "BankPgpKey_bankCode_status_activatedAt_idx" ON "BankPgpKey"("bankCode", "status", "activatedAt");

CREATE TABLE "BankConnectionAudit" (
  "id" TEXT NOT NULL,
  "bankCode" TEXT NOT NULL DEFAULT 'BIDV',
  "actorUserId" TEXT,
  "actorEmailHash" TEXT,
  "action" TEXT NOT NULL,
  "targetType" TEXT NOT NULL,
  "targetId" TEXT NOT NULL,
  "summary" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "BankConnectionAudit_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "BankConnectionAudit_bankCode_createdAt_idx" ON "BankConnectionAudit"("bankCode", "createdAt");
CREATE INDEX "BankConnectionAudit_targetType_targetId_createdAt_idx" ON "BankConnectionAudit"("targetType", "targetId", "createdAt");

CREATE TABLE "BankConnectionControl" (
  "bankCode" TEXT NOT NULL,
  "ingressEnabled" BOOLEAN NOT NULL DEFAULT false,
  "projectionEnabled" BOOLEAN NOT NULL DEFAULT false,
  "version" INTEGER NOT NULL DEFAULT 1,
  "updatedByUserId" TEXT,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "BankConnectionControl_pkey" PRIMARY KEY ("bankCode")
);
INSERT INTO "BankConnectionControl" ("bankCode", "updatedAt") VALUES ('BIDV', CURRENT_TIMESTAMP);

INSERT INTO "FeatureDefinition" (
  "id", "code", "displayName", "description", "parentCode", "sortOrder",
  "visibleInUserPicker", "isSystem", "isActive", "createdAt", "updatedAt"
) VALUES (
  'feature-admin-api-connections',
  'ADMIN_API_CONNECTIONS',
  'Quản lý kết nối API',
  'Quản lý kết nối ngân hàng H2H',
  'ADMIN',
  98,
  false,
  true,
  true,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("code") DO UPDATE SET
  "displayName" = EXCLUDED."displayName",
  "description" = EXCLUDED."description",
  "parentCode" = EXCLUDED."parentCode",
  "sortOrder" = EXCLUDED."sortOrder",
  "visibleInUserPicker" = false,
  "isSystem" = true,
  "isActive" = true,
  "updatedAt" = CURRENT_TIMESTAMP;

CREATE TABLE "BankIngressReceipt" (
  "id" TEXT NOT NULL,
  "bankCode" TEXT NOT NULL,
  "requestId" TEXT NOT NULL,
  "requestHash" TEXT NOT NULL,
  "clientRefId" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'ACCEPTED',
  "transactionCount" INTEGER NOT NULL DEFAULT 0,
  "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completedAt" TIMESTAMP(3),
  CONSTRAINT "BankIngressReceipt_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "BankIngressReceipt_bankCode_requestId_key" ON "BankIngressReceipt"("bankCode", "requestId");
CREATE INDEX "BankIngressReceipt_receivedAt_idx" ON "BankIngressReceipt"("receivedAt");
CREATE INDEX "BankIngressReceipt_clientRefId_receivedAt_idx" ON "BankIngressReceipt"("clientRefId", "receivedAt");

CREATE TABLE "BankTransaction" (
  "id" TEXT NOT NULL,
  "receiptId" TEXT NOT NULL,
  "bankCode" TEXT NOT NULL,
  "identityHash" TEXT NOT NULL,
  "payloadHash" TEXT NOT NULL,
  "accountNoHash" TEXT NOT NULL,
  "accountNoMasked" TEXT NOT NULL,
  "exactAmount" DECIMAL(24,6) NOT NULL,
  "currency" TEXT NOT NULL,
  "transactionDate" DATE NOT NULL,
  "transactionTime" TEXT NOT NULL,
  "paidAt" TIMESTAMP(3) NOT NULL,
  "direction" TEXT NOT NULL,
  "sequence" TEXT NOT NULL,
  "referenceNumber" TEXT NOT NULL,
  "remark" TEXT NOT NULL,
  "senderBankCode" TEXT,
  "senderAccountName" TEXT,
  "senderAccountHash" TEXT,
  "senderAccountMasked" TEXT,
  "senderBankName" TEXT,
  "endingBalance" DECIMAL(24,6),
  "channelReference" TEXT,
  "channelId" TEXT,
  "businessDate" DATE NOT NULL,
  "receiverBankCode" TEXT,
  "receiverAccountName" TEXT,
  "receiverAccountHash" TEXT,
  "receiverAccountMasked" TEXT,
  "receiverBankName" TEXT,
  "virtualAccountHash" TEXT,
  "virtualAccountMasked" TEXT,
  "showroomCodeHint" TEXT,
  "transactionCode" TEXT,
  "extensions" JSONB NOT NULL,
  "conflictStatus" TEXT NOT NULL DEFAULT 'NONE',
  "projectionStatus" TEXT NOT NULL DEFAULT 'PENDING',
  "projectionReason" TEXT,
  "projectedTransactionId" TEXT,
  "projectionAttempts" INTEGER NOT NULL DEFAULT 0,
  "projectionAvailableAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "projectionClaimedAt" TIMESTAMP(3),
  "projectionClaimToken" TEXT,
  "projectionLeaseExpiresAt" TIMESTAMP(3),
  "projectionLastError" TEXT,
  "projectedAt" TIMESTAMP(3),
  "retainedUntil" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "BankTransaction_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "BankTransaction_identityHash_payloadHash_key" ON "BankTransaction"("identityHash", "payloadHash");
CREATE UNIQUE INDEX "BankTransaction_projectedTransactionId_key" ON "BankTransaction"("projectedTransactionId");
CREATE INDEX "BankTransaction_receiptId_idx" ON "BankTransaction"("receiptId");
CREATE INDEX "BankTransaction_projectionStatus_projectionAvailableAt_projectionLeaseExpiresAt_idx" ON "BankTransaction"("projectionStatus", "projectionAvailableAt", "projectionLeaseExpiresAt");
CREATE INDEX "BankTransaction_bankCode_businessDate_idx" ON "BankTransaction"("bankCode", "businessDate");
CREATE INDEX "BankTransaction_accountNoHash_paidAt_idx" ON "BankTransaction"("accountNoHash", "paidAt");
CREATE INDEX "BankTransaction_showroomCodeHint_paidAt_idx" ON "BankTransaction"("showroomCodeHint", "paidAt");
CREATE INDEX "BankTransaction_retainedUntil_idx" ON "BankTransaction"("retainedUntil");
ALTER TABLE "BankTransaction" ADD CONSTRAINT "BankTransaction_receiptId_fkey"
  FOREIGN KEY ("receiptId") REFERENCES "BankIngressReceipt"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "MapVietinTransaction" ADD CONSTRAINT "MapVietinTransaction_canonicalBankTransactionId_fkey"
  FOREIGN KEY ("canonicalBankTransactionId") REFERENCES "BankTransaction"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE OR REPLACE FUNCTION opshub_bank_connection_audit_immutable()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'BankConnectionAudit is immutable';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "BankConnectionAudit_immutable_update"
BEFORE UPDATE ON "BankConnectionAudit"
FOR EACH ROW EXECUTE FUNCTION opshub_bank_connection_audit_immutable();

CREATE TRIGGER "BankConnectionAudit_immutable_delete"
BEFORE DELETE ON "BankConnectionAudit"
FOR EACH ROW EXECUTE FUNCTION opshub_bank_connection_audit_immutable();
