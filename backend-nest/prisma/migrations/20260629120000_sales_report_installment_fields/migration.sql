ALTER TABLE "SalesReport"
  ADD COLUMN "installmentStatus" TEXT,
  ADD COLUMN "installmentFailureReason" TEXT;

CREATE INDEX "SalesReport_installmentStatus_submittedAt_idx"
  ON "SalesReport"("installmentStatus", "submittedAt");
