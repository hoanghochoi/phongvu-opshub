ALTER TABLE "SalesReport"
ADD COLUMN "erpExcludedAt" TIMESTAMP(3),
ADD COLUMN "erpExclusionReason" TEXT;

CREATE INDEX "SalesReport_erpExcludedAt_submittedAt_idx"
ON "SalesReport"("erpExcludedAt", "submittedAt");

ALTER TABLE "SalesReportErpOrderCache"
ADD COLUMN "excludedAt" TIMESTAMP(3),
ADD COLUMN "exclusionReason" TEXT;

CREATE INDEX "SalesReportErpOrderCache_excludedAt_orderCreatedAt_idx"
ON "SalesReportErpOrderCache"("excludedAt", "orderCreatedAt");
