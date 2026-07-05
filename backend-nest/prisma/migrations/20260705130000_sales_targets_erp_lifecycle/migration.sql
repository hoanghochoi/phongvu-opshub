-- Persist normalized ERP lifecycle and return amounts for revenue eligibility.
ALTER TABLE "SalesReport"
  ADD COLUMN "erpLifecycleStatus" TEXT NOT NULL DEFAULT 'PENDING',
  ADD COLUMN "erpHasReturnedFullItems" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "erpReturnedAfterTaxAmount" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "erpStatusCheckedAt" TIMESTAMP(3),
  ADD COLUMN "erpStatusCheckFailureCount" INTEGER NOT NULL DEFAULT 0;

ALTER TABLE "SalesReportErpOrderCache"
  ADD COLUMN "lifecycleStatus" TEXT NOT NULL DEFAULT 'PENDING',
  ADD COLUMN "hasReturnedFullItems" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "returnedAfterTaxAmount" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "statusCheckedAt" TIMESTAMP(3),
  ADD COLUMN "statusCheckAttemptedAt" TIMESTAMP(3),
  ADD COLUMN "statusCheckFailureCount" INTEGER NOT NULL DEFAULT 0;

-- Existing non-cancelled rows must be verified by the bounded 20-minute job.
UPDATE "SalesReport"
SET "erpLifecycleStatus" = CASE
  WHEN LOWER(COALESCE("erpConfirmationStatus", '')) = 'cancelled'
    OR LOWER(COALESCE("erpFulfillmentStatus", '')) = 'cancelled'
    THEN 'CANCELLED'
  ELSE 'PENDING'
END;

UPDATE "SalesReportErpOrderCache"
SET "lifecycleStatus" = CASE
  WHEN LOWER(COALESCE("confirmationStatus", '')) = 'cancelled'
    OR LOWER(COALESCE("fulfillmentStatus", '')) = 'cancelled'
    THEN 'CANCELLED'
  ELSE 'PENDING'
END;

-- Older purchased reports may predate the ERP cache. Seed lightweight cache
-- rows so the bounded status job verifies them gradually after deploy.
INSERT INTO "SalesReportErpOrderCache" (
  "id",
  "orderCode",
  "erpOrderId",
  "erpExternalOrderRef",
  "orderCreatedAt",
  "paymentStatus",
  "confirmationStatus",
  "fulfillmentStatus",
  "lifecycleStatus",
  "hasReturnedFullItems",
  "returnedAfterTaxAmount",
  "statusCheckFailureCount",
  "excludedAt",
  "exclusionReason",
  "terminalName",
  "grandTotal",
  "customerName",
  "customerPhone",
  "customerType",
  "paymentMethods",
  "platformId",
  "consultantCustomId",
  "consultantName",
  "storeCode",
  "storeName",
  "organizationNodeId",
  "sourceUserId",
  "sourceUserEmail",
  "sanitizedSnapshot",
  "fetchedAt",
  "createdAt",
  "updatedAt"
)
SELECT
  'erp-backfill-' || md5(report."orderCode"),
  report."orderCode",
  report."erpOrderId",
  report."erpExternalOrderRef",
  report."erpOrderCreatedAt",
  report."erpPaymentStatus",
  report."erpConfirmationStatus",
  report."erpFulfillmentStatus",
  report."erpLifecycleStatus",
  report."erpHasReturnedFullItems",
  report."erpReturnedAfterTaxAmount",
  report."erpStatusCheckFailureCount",
  report."erpExcludedAt",
  report."erpExclusionReason",
  report."erpTerminalName",
  report."erpGrandTotal",
  report."customerName",
  report."customerPhone",
  report."customerType",
  report."erpPaymentMethods",
  report."erpPlatformId",
  report."erpConsultantCustomId",
  report."erpConsultantName",
  report."storeCode",
  report."storeName",
  report."organizationNodeId",
  report."createdByUserId",
  report."createdByEmail",
  report."erpSnapshot",
  COALESCE(report."erpFetchedAt", report."submittedAt"),
  report."createdAt",
  CURRENT_TIMESTAMP
FROM "SalesReport" AS report
WHERE report."reportType" = 'PURCHASED'
  AND report."orderCode" IS NOT NULL
ON CONFLICT ("orderCode") DO NOTHING;

CREATE INDEX "SalesReport_erpLifecycleStatus_erpStatusCheckedAt_idx"
  ON "SalesReport"("erpLifecycleStatus", "erpStatusCheckedAt");
CREATE INDEX "SalesReportErpOrderCache_lifecycleStatus_statusCheckedAt_idx"
  ON "SalesReportErpOrderCache"("lifecycleStatus", "statusCheckedAt");
CREATE INDEX "SalesReportErpOrderCache_orderCreatedAt_lifecycleStatus_statusCheckedAt_idx"
  ON "SalesReportErpOrderCache"("orderCreatedAt", "lifecycleStatus", "statusCheckedAt");

CREATE TABLE "SalesTarget" (
  "id" TEXT NOT NULL,
  "organizationNodeId" TEXT NOT NULL,
  "monthStart" DATE NOT NULL,
  "targetBeforeTax" BIGINT NOT NULL,
  "updatedByUserId" TEXT,
  "updatedByEmail" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SalesTarget_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SalesTarget_organizationNodeId_monthStart_key"
  ON "SalesTarget"("organizationNodeId", "monthStart");
CREATE INDEX "SalesTarget_monthStart_idx" ON "SalesTarget"("monthStart");
CREATE INDEX "SalesTarget_organizationNodeId_monthStart_idx"
  ON "SalesTarget"("organizationNodeId", "monthStart");
ALTER TABLE "SalesTarget"
  ADD CONSTRAINT "SalesTarget_organizationNodeId_fkey"
  FOREIGN KEY ("organizationNodeId") REFERENCES "OrganizationNode"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;
