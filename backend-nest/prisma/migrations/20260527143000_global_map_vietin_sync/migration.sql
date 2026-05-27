CREATE TABLE "MapVietinUnmappedTransaction" (
  "id" TEXT NOT NULL,
  "unmappedKey" TEXT NOT NULL,
  "virtualAccount" TEXT,
  "reason" TEXT NOT NULL,
  "transactionNumber" TEXT,
  "amount" INTEGER,
  "content" TEXT NOT NULL,
  "status" TEXT,
  "paidAt" TIMESTAMP(3),
  "payerName" TEXT,
  "payerAccount" TEXT,
  "rawData" JSONB NOT NULL,
  "firstSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "MapVietinUnmappedTransaction_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "MapVietinUnmappedTransaction_unmappedKey_key"
  ON "MapVietinUnmappedTransaction"("unmappedKey");

CREATE INDEX "MapVietinUnmappedTransaction_reason_firstSeenAt_idx"
  ON "MapVietinUnmappedTransaction"("reason", "firstSeenAt");

CREATE INDEX "MapVietinUnmappedTransaction_virtualAccount_firstSeenAt_idx"
  ON "MapVietinUnmappedTransaction"("virtualAccount", "firstSeenAt");
