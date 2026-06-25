CREATE TABLE "MapVietinStatementOrderTransferRequest" (
  "id" TEXT NOT NULL,
  "transactionId" TEXT NOT NULL,
  "storeCode" TEXT NOT NULL,
  "oldOrders" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "requestedOrders" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "requestedByUserId" TEXT,
  "requestedByEmail" TEXT,
  "reviewedByUserId" TEXT,
  "reviewedByEmail" TEXT,
  "reviewedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "MapVietinStatementOrderTransferRequest_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "MapVietinStatementOrderTransferRequest"
ADD CONSTRAINT "MapVietinStatementOrderTransferRequest_transactionId_fkey"
FOREIGN KEY ("transactionId")
REFERENCES "MapVietinTransaction"("id")
ON DELETE CASCADE
ON UPDATE CASCADE;

CREATE INDEX "MapVietinStatementOrderTransferRequest_transactionId_status_idx"
ON "MapVietinStatementOrderTransferRequest"("transactionId", "status");

CREATE INDEX "MapVietinStatementOrderTransferRequest_storeCode_status_createdAt_idx"
ON "MapVietinStatementOrderTransferRequest"("storeCode", "status", "createdAt");

CREATE INDEX "MapVietinStatementOrderTransferRequest_status_createdAt_idx"
ON "MapVietinStatementOrderTransferRequest"("status", "createdAt");

CREATE UNIQUE INDEX "MapVietinStatementOrderTransferRequest_one_pending_per_transaction_idx"
ON "MapVietinStatementOrderTransferRequest"("transactionId")
WHERE "status" = 'PENDING';
