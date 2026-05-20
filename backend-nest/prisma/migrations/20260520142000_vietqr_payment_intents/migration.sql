CREATE TABLE "VietQrPaymentIntent" (
  "id" TEXT NOT NULL,
  "storeCode" TEXT NOT NULL,
  "createdById" TEXT,
  "amount" INTEGER,
  "orderCode" TEXT,
  "transferContent" TEXT NOT NULL,
  "qrPayload" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "matchedTransactionId" TEXT,
  "matchedTransactionNumber" TEXT,
  "matchedAmount" INTEGER,
  "matchedTranTime" TIMESTAMP(3),
  "confirmedAt" TIMESTAMP(3),
  "lastCheckedAt" TIMESTAMP(3),
  "lastCheckResult" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "VietQrPaymentIntent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "VietQrPaymentIntent_storeCode_createdAt_idx" ON "VietQrPaymentIntent"("storeCode", "createdAt");
CREATE INDEX "VietQrPaymentIntent_status_createdAt_idx" ON "VietQrPaymentIntent"("status", "createdAt");
ALTER TABLE "VietQrPaymentIntent" ADD CONSTRAINT "VietQrPaymentIntent_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
