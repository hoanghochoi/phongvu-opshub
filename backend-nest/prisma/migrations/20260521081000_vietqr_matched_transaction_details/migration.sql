ALTER TABLE "VietQrPaymentIntent"
ADD COLUMN "matchedPayerName" TEXT,
ADD COLUMN "matchedPayerAccount" TEXT,
ADD COLUMN "matchedTransactionContent" TEXT;
