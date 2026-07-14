ALTER TABLE "SalesReport"
ADD COLUMN "customerZaloContact" TEXT,
ADD COLUMN "entrySource" TEXT,
ADD COLUMN "submittedByUserId" TEXT,
ADD COLUMN "submittedByEmail" TEXT,
ADD COLUMN "submittedByName" TEXT;

UPDATE "SalesReport"
SET "entrySource" = NULLIF("rawResponses"->>'entrySource', ''),
    "submittedByUserId" = "createdByUserId",
    "submittedByEmail" = "createdByEmail",
    "submittedByName" = "createdByName"
WHERE "entrySource" IS NULL
   OR "submittedByEmail" IS NULL;

UPDATE "SalesReport"
SET "customerPhone" = NULL
WHERE btrim(COALESCE("customerPhone", '')) = '';

CREATE INDEX "SalesReport_entrySource_submittedAt_idx"
ON "SalesReport"("entrySource", "submittedAt");

CREATE TABLE "SalesReportFollowUpCase" (
  "id" TEXT NOT NULL,
  "sourceReportId" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'OPEN',
  "assigneeUserId" TEXT,
  "assigneeEmail" TEXT,
  "assigneeName" TEXT,
  "assigneePersonnelCode" TEXT,
  "assignedAt" TIMESTAMP(3),
  "lastFollowUpAt" TIMESTAMP(3),
  "lastFollowUpByUserId" TEXT,
  "lastFollowUpByEmail" TEXT,
  "lastFollowUpByName" TEXT,
  "followUpCount" INTEGER NOT NULL DEFAULT 0,
  "priorityAt" TIMESTAMP(3) NOT NULL,
  "convertedReportId" TEXT,
  "closedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SalesReportFollowUpCase_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesReportFollowUpEntry" (
  "id" TEXT NOT NULL,
  "caseId" TEXT NOT NULL,
  "sequenceNumber" INTEGER NOT NULL,
  "outcome" TEXT NOT NULL,
  "notPurchasedReason" TEXT,
  "notPurchasedOtherReason" TEXT,
  "actorUserId" TEXT,
  "actorEmail" TEXT,
  "actorName" TEXT,
  "purchasedReportId" TEXT,
  "contactedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SalesReportFollowUpEntry_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesReportFollowUpEvent" (
  "id" TEXT NOT NULL,
  "caseId" TEXT NOT NULL,
  "eventType" TEXT NOT NULL,
  "actorUserId" TEXT,
  "actorEmail" TEXT,
  "actorName" TEXT,
  "fromAssigneeUserId" TEXT,
  "toAssigneeUserId" TEXT,
  "fromStatus" TEXT,
  "toStatus" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SalesReportFollowUpEvent_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SalesReportFollowUpCase_sourceReportId_key" ON "SalesReportFollowUpCase"("sourceReportId");
CREATE UNIQUE INDEX "SalesReportFollowUpCase_convertedReportId_key" ON "SalesReportFollowUpCase"("convertedReportId");
CREATE INDEX "SalesReportFollowUpCase_status_priorityAt_idx" ON "SalesReportFollowUpCase"("status", "priorityAt");
CREATE INDEX "SalesReportFollowUpCase_assigneeUserId_status_priorityAt_idx" ON "SalesReportFollowUpCase"("assigneeUserId", "status", "priorityAt");
CREATE INDEX "SalesReportFollowUpCase_assigneeEmail_status_priorityAt_idx" ON "SalesReportFollowUpCase"("assigneeEmail", "status", "priorityAt");
CREATE UNIQUE INDEX "SalesReportFollowUpEntry_purchasedReportId_key" ON "SalesReportFollowUpEntry"("purchasedReportId");
CREATE UNIQUE INDEX "SalesReportFollowUpEntry_caseId_sequenceNumber_key" ON "SalesReportFollowUpEntry"("caseId", "sequenceNumber");
CREATE INDEX "SalesReportFollowUpEntry_caseId_contactedAt_idx" ON "SalesReportFollowUpEntry"("caseId", "contactedAt");
CREATE INDEX "SalesReportFollowUpEntry_outcome_contactedAt_idx" ON "SalesReportFollowUpEntry"("outcome", "contactedAt");
CREATE INDEX "SalesReportFollowUpEvent_caseId_createdAt_idx" ON "SalesReportFollowUpEvent"("caseId", "createdAt");
CREATE INDEX "SalesReportFollowUpEvent_eventType_createdAt_idx" ON "SalesReportFollowUpEvent"("eventType", "createdAt");

ALTER TABLE "SalesReportFollowUpCase" ADD CONSTRAINT "SalesReportFollowUpCase_sourceReportId_fkey" FOREIGN KEY ("sourceReportId") REFERENCES "SalesReport"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SalesReportFollowUpCase" ADD CONSTRAINT "SalesReportFollowUpCase_convertedReportId_fkey" FOREIGN KEY ("convertedReportId") REFERENCES "SalesReport"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "SalesReportFollowUpEntry" ADD CONSTRAINT "SalesReportFollowUpEntry_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "SalesReportFollowUpCase"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SalesReportFollowUpEntry" ADD CONSTRAINT "SalesReportFollowUpEntry_purchasedReportId_fkey" FOREIGN KEY ("purchasedReportId") REFERENCES "SalesReport"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "SalesReportFollowUpEvent" ADD CONSTRAINT "SalesReportFollowUpEvent_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "SalesReportFollowUpCase"("id") ON DELETE CASCADE ON UPDATE CASCADE;

INSERT INTO "SalesReportFollowUpCase" (
  "id", "sourceReportId", "status", "assigneeUserId", "assigneeEmail",
  "assigneeName", "assigneePersonnelCode", "assignedAt", "priorityAt",
  "createdAt", "updatedAt"
)
SELECT
  gen_random_uuid()::text,
  report."id",
  'OPEN',
  report."createdByUserId",
  report."createdByEmail",
  report."createdByName",
  report."createdByPersonnelCode",
  report."submittedAt",
  report."submittedAt",
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "SalesReport" report
WHERE report."reportType" = 'NOT_PURCHASED'
ON CONFLICT ("sourceReportId") DO NOTHING;
