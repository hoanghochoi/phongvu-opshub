ALTER TABLE "MapVietinTransaction"
ADD COLUMN "orders" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "orderSource" TEXT,
ADD COLUMN "orderUpdatedAt" TIMESTAMP(3),
ADD COLUMN "orderUpdatedByUserId" TEXT,
ADD COLUMN "orderUpdatedByEmail" TEXT;

CREATE TABLE "MapVietinTransactionOrderAudit" (
  "id" TEXT NOT NULL,
  "transactionId" TEXT NOT NULL,
  "storeCode" TEXT NOT NULL,
  "oldOrders" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "newOrders" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "changedByUserId" TEXT,
  "changedByEmail" TEXT,
  "source" TEXT NOT NULL DEFAULT 'MANUAL',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "MapVietinTransactionOrderAudit_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "MapVietinTransaction_amount_idx"
  ON "MapVietinTransaction"("amount");

CREATE INDEX "MapVietinTransaction_orders_idx"
  ON "MapVietinTransaction" USING GIN ("orders");

CREATE INDEX "MapVietinTransactionOrderAudit_transactionId_createdAt_idx"
  ON "MapVietinTransactionOrderAudit"("transactionId", "createdAt");

CREATE INDEX "MapVietinTransactionOrderAudit_storeCode_createdAt_idx"
  ON "MapVietinTransactionOrderAudit"("storeCode", "createdAt");

ALTER TABLE "MapVietinTransactionOrderAudit"
ADD CONSTRAINT "MapVietinTransactionOrderAudit_transactionId_fkey"
FOREIGN KEY ("transactionId") REFERENCES "MapVietinTransaction"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
