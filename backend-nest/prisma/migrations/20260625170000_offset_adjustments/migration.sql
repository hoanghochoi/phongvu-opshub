CREATE TABLE "OffsetAdjustment" (
  "id" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'PENDING_ACC',
  "storeCode" TEXT NOT NULL,
  "oldOrderCode" TEXT,
  "newOrderCode" TEXT,
  "orderCode" TEXT,
  "scanDate" TIMESTAMP(3),
  "editContentKind" TEXT,
  "transactionCode" TEXT,
  "amount" INTEGER NOT NULL,
  "note" TEXT,
  "ctCode" TEXT,
  "rejectReason" TEXT,
  "createdByUserId" TEXT,
  "createdByEmail" TEXT,
  "reviewedByUserId" TEXT,
  "reviewedByEmail" TEXT,
  "submittedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "reviewedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "OffsetAdjustment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "OffsetAdjustmentHistory" (
  "id" TEXT NOT NULL,
  "adjustmentId" TEXT NOT NULL,
  "action" TEXT NOT NULL,
  "fromStatus" TEXT,
  "toStatus" TEXT,
  "actorUserId" TEXT,
  "actorEmail" TEXT,
  "reason" TEXT,
  "snapshot" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "OffsetAdjustmentHistory_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "OffsetAdjustmentHistory"
ADD CONSTRAINT "OffsetAdjustmentHistory_adjustmentId_fkey"
FOREIGN KEY ("adjustmentId")
REFERENCES "OffsetAdjustment"("id")
ON DELETE CASCADE
ON UPDATE CASCADE;

CREATE UNIQUE INDEX "OffsetAdjustment_type_orderCode_key"
ON "OffsetAdjustment"("type", "orderCode");

CREATE UNIQUE INDEX "OffsetAdjustment_type_transactionCode_key"
ON "OffsetAdjustment"("type", "transactionCode");

CREATE INDEX "OffsetAdjustment_storeCode_submittedAt_idx"
ON "OffsetAdjustment"("storeCode", "submittedAt");

CREATE INDEX "OffsetAdjustment_status_submittedAt_idx"
ON "OffsetAdjustment"("status", "submittedAt");

CREATE INDEX "OffsetAdjustment_type_submittedAt_idx"
ON "OffsetAdjustment"("type", "submittedAt");

CREATE INDEX "OffsetAdjustment_oldOrderCode_idx"
ON "OffsetAdjustment"("oldOrderCode");

CREATE INDEX "OffsetAdjustment_newOrderCode_idx"
ON "OffsetAdjustment"("newOrderCode");

CREATE INDEX "OffsetAdjustment_amount_idx"
ON "OffsetAdjustment"("amount");

CREATE INDEX "OffsetAdjustmentHistory_adjustmentId_createdAt_idx"
ON "OffsetAdjustmentHistory"("adjustmentId", "createdAt");

CREATE INDEX "OffsetAdjustmentHistory_action_createdAt_idx"
ON "OffsetAdjustmentHistory"("action", "createdAt");
