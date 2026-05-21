CREATE TABLE "MapVietinTransaction" (
  "id" TEXT NOT NULL,
  "storeCode" TEXT NOT NULL,
  "transactionKey" TEXT NOT NULL,
  "transactionNumber" TEXT,
  "amount" INTEGER NOT NULL,
  "content" TEXT NOT NULL,
  "status" TEXT,
  "paidAt" TIMESTAMP(3),
  "payerName" TEXT,
  "payerAccount" TEXT,
  "rawData" JSONB NOT NULL,
  "firstSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "MapVietinTransaction_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "MapVietinSyncState" (
  "id" TEXT NOT NULL,
  "storeCode" TEXT NOT NULL,
  "lastSyncedAt" TIMESTAMP(3),
  "lastSuccessAt" TIMESTAMP(3),
  "lastError" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "MapVietinSyncState_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "MapVietinTransaction_transactionKey_key"
  ON "MapVietinTransaction"("transactionKey");

CREATE INDEX "MapVietinTransaction_storeCode_paidAt_idx"
  ON "MapVietinTransaction"("storeCode", "paidAt");

CREATE INDEX "MapVietinTransaction_storeCode_firstSeenAt_idx"
  ON "MapVietinTransaction"("storeCode", "firstSeenAt");

CREATE UNIQUE INDEX "MapVietinSyncState_storeCode_key"
  ON "MapVietinSyncState"("storeCode");
