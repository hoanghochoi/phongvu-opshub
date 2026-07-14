ALTER TABLE "SalesReport"
ADD COLUMN "erpStatusCheckAttemptedAt" TIMESTAMP(3),
ADD COLUMN "erpStatusCheckAttemptDate" DATE,
ADD COLUMN "erpStatusCheckAttemptCount" INTEGER NOT NULL DEFAULT 0;

ALTER TABLE "SalesReportErpOrderCache"
ADD COLUMN "statusCheckAttemptDate" DATE,
ADD COLUMN "statusCheckAttemptCount" INTEGER NOT NULL DEFAULT 0;

UPDATE "SalesReport"
SET
  "erpStatusCheckAttemptedAt" = "erpStatusCheckedAt",
  "erpStatusCheckAttemptDate" = (
    "erpStatusCheckedAt" AT TIME ZONE 'Asia/Ho_Chi_Minh'
  )::date,
  "erpStatusCheckAttemptCount" = 1
WHERE "erpStatusCheckedAt" IS NOT NULL;

UPDATE "SalesReportErpOrderCache"
SET
  "statusCheckAttemptDate" = (
    COALESCE("statusCheckAttemptedAt", "statusCheckedAt")
      AT TIME ZONE 'Asia/Ho_Chi_Minh'
  )::date,
  "statusCheckAttemptCount" = 1
WHERE COALESCE("statusCheckAttemptedAt", "statusCheckedAt") IS NOT NULL;

CREATE INDEX "SalesReport_erpLifecycleStatus_erpStatusCheckAttemptDate_idx"
ON "SalesReport"("erpLifecycleStatus", "erpStatusCheckAttemptDate");

CREATE INDEX "SalesReportErpOrderCache_lifecycleStatus_statusCheckAttemptDate_idx"
ON "SalesReportErpOrderCache"("lifecycleStatus", "statusCheckAttemptDate");
