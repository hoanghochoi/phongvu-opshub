CREATE TABLE "SalesHistoryVersion" (
    "id" TEXT NOT NULL,
    "sourceHash" TEXT NOT NULL,
    "rowCount" INTEGER NOT NULL,
    "cleanRowCount" INTEGER NOT NULL,
    "quarantinedRows" INTEGER NOT NULL,
    "cleanGrainCount" INTEGER NOT NULL,
    "quarantineCount" INTEGER NOT NULL,
    "rangeStart" DATE NOT NULL,
    "rangeEnd" DATE NOT NULL,
    "createdByUserId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "SalesHistoryVersion_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesHistoryImportJob" (
    "id" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'QUEUED',
    "sourceHash" TEXT,
    "encoding" TEXT,
    "delimiter" TEXT,
    "uploadedBytes" BIGINT NOT NULL DEFAULT 0,
    "expectedBytes" BIGINT NOT NULL DEFAULT 0,
    "totalRows" INTEGER NOT NULL DEFAULT 0,
    "cleanRows" INTEGER NOT NULL DEFAULT 0,
    "quarantinedRows" INTEGER NOT NULL DEFAULT 0,
    "cleanGrains" INTEGER NOT NULL DEFAULT 0,
    "quarantinedGrains" INTEGER NOT NULL DEFAULT 0,
    "failureCode" TEXT,
    "failureMessage" TEXT,
    "requestedByUserId" TEXT,
    "artifactPath" TEXT,
    "workerId" TEXT,
    "leaseExpiresAt" TIMESTAMP(3),
    "heartbeatAt" TIMESTAMP(3),
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "claimToken" BIGINT NOT NULL DEFAULT 0,
    "versionId" TEXT,
    "cancelRequestedAt" TIMESTAMP(3),
    "startedAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "SalesHistoryImportJob_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesHistoryImportGrainStage" (
    "id" TEXT NOT NULL,
    "jobId" TEXT NOT NULL,
    "summaryDate" DATE NOT NULL,
    "storeCode" TEXT NOT NULL,
    "rowCount" INTEGER NOT NULL DEFAULT 0,
    "invalidRows" INTEGER NOT NULL DEFAULT 0,
    "reasonCodes" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "SalesHistoryImportGrainStage_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesHistoryImportOrderStage" (
    "id" TEXT NOT NULL,
    "jobId" TEXT NOT NULL,
    "summaryDate" DATE NOT NULL,
    "storeCode" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "orderHash" TEXT NOT NULL,
    "totalRevenue" BIGINT NOT NULL DEFAULT 0,
    "extendedInsuranceQuantity" INTEGER NOT NULL DEFAULT 0,
    "laptopQuantity" INTEGER NOT NULL DEFAULT 0,
    "pcQuantity" INTEGER NOT NULL DEFAULT 0,
    "assembledPcQuantity" INTEGER NOT NULL DEFAULT 0,
    "appleQuantity" INTEGER NOT NULL DEFAULT 0,
    "monitorQuantity" INTEGER NOT NULL DEFAULT 0,
    "printerQuantity" INTEGER NOT NULL DEFAULT 0,
    "accessoriesQuantity" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "SalesHistoryImportOrderStage_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesHistoryCoverage" (
    "id" TEXT NOT NULL,
    "versionId" TEXT NOT NULL,
    "summaryDate" DATE NOT NULL,
    "storeCode" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "rowCount" INTEGER NOT NULL DEFAULT 0,
    "quarantinedRows" INTEGER NOT NULL DEFAULT 0,
    "reasonCodes" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "SalesHistoryCoverage_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesHistoryAggregate" (
    "id" TEXT NOT NULL,
    "versionId" TEXT NOT NULL,
    "summaryDate" DATE NOT NULL,
    "storeCode" TEXT NOT NULL,
    "dimensionType" TEXT NOT NULL DEFAULT 'STORE',
    "dimensionKey" TEXT NOT NULL DEFAULT '',
    "totalRevenue" BIGINT NOT NULL DEFAULT 0,
    "totalOrders" INTEGER NOT NULL DEFAULT 0,
    "extendedInsuranceQuantity" INTEGER NOT NULL DEFAULT 0,
    "laptopQuantity" INTEGER NOT NULL DEFAULT 0,
    "pcQuantity" INTEGER NOT NULL DEFAULT 0,
    "assembledPcQuantity" INTEGER NOT NULL DEFAULT 0,
    "appleQuantity" INTEGER NOT NULL DEFAULT 0,
    "monitorQuantity" INTEGER NOT NULL DEFAULT 0,
    "printerQuantity" INTEGER NOT NULL DEFAULT 0,
    "accessoriesQuantity" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "SalesHistoryAggregate_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesHistoryActiveGrain" (
    "id" TEXT NOT NULL,
    "summaryDate" DATE NOT NULL,
    "storeCode" TEXT NOT NULL,
    "currentVersionId" TEXT NOT NULL,
    "activatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "SalesHistoryActiveGrain_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesHistoryActivation" (
    "id" TEXT NOT NULL,
    "versionId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "actorUserId" TEXT,
    "grainCount" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "SalesHistoryActivation_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesHistoryActivationGrain" (
    "id" TEXT NOT NULL,
    "activationId" TEXT NOT NULL,
    "summaryDate" DATE NOT NULL,
    "storeCode" TEXT NOT NULL,
    "fromVersionId" TEXT,
    "toVersionId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "SalesHistoryActivationGrain_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SalesHistoryImportJob_versionId_key" ON "SalesHistoryImportJob"("versionId");
CREATE INDEX "SalesHistoryImportJob_status_createdAt_idx" ON "SalesHistoryImportJob"("status", "createdAt");
CREATE INDEX "SalesHistoryImportJob_status_leaseExpiresAt_createdAt_idx" ON "SalesHistoryImportJob"("status", "leaseExpiresAt", "createdAt");
CREATE INDEX "SalesHistoryImportJob_requestedByUserId_createdAt_idx" ON "SalesHistoryImportJob"("requestedByUserId", "createdAt");
CREATE UNIQUE INDEX "SalesHistoryImportGrainStage_jobId_summaryDate_storeCode_key" ON "SalesHistoryImportGrainStage"("jobId", "summaryDate", "storeCode");
CREATE INDEX "SalesHistoryImportGrainStage_jobId_invalidRows_idx" ON "SalesHistoryImportGrainStage"("jobId", "invalidRows");
CREATE UNIQUE INDEX "SalesHistoryImportOrderStage_jobId_summaryDate_storeCode_userId_orderHash_key" ON "SalesHistoryImportOrderStage"("jobId", "summaryDate", "storeCode", "userId", "orderHash");
CREATE INDEX "SalesHistoryImportOrderStage_jobId_summaryDate_storeCode_idx" ON "SalesHistoryImportOrderStage"("jobId", "summaryDate", "storeCode");
CREATE INDEX "SalesHistoryVersion_createdAt_idx" ON "SalesHistoryVersion"("createdAt");
CREATE INDEX "SalesHistoryVersion_rangeStart_rangeEnd_idx" ON "SalesHistoryVersion"("rangeStart", "rangeEnd");
CREATE UNIQUE INDEX "SalesHistoryCoverage_versionId_summaryDate_storeCode_key" ON "SalesHistoryCoverage"("versionId", "summaryDate", "storeCode");
CREATE INDEX "SalesHistoryCoverage_summaryDate_storeCode_status_idx" ON "SalesHistoryCoverage"("summaryDate", "storeCode", "status");
CREATE UNIQUE INDEX "SalesHistoryAggregate_versionId_summaryDate_storeCode_dimensionType_dimensionKey_key" ON "SalesHistoryAggregate"("versionId", "summaryDate", "storeCode", "dimensionType", "dimensionKey");
CREATE INDEX "SalesHistoryAggregate_summaryDate_storeCode_dimensionType_dimensionKey_idx" ON "SalesHistoryAggregate"("summaryDate", "storeCode", "dimensionType", "dimensionKey");
CREATE UNIQUE INDEX "SalesHistoryActiveGrain_summaryDate_storeCode_key" ON "SalesHistoryActiveGrain"("summaryDate", "storeCode");
CREATE INDEX "SalesHistoryActiveGrain_currentVersionId_summaryDate_idx" ON "SalesHistoryActiveGrain"("currentVersionId", "summaryDate");
CREATE INDEX "SalesHistoryActivation_versionId_createdAt_idx" ON "SalesHistoryActivation"("versionId", "createdAt");
CREATE UNIQUE INDEX "SalesHistoryActivationGrain_activationId_summaryDate_storeCode_key" ON "SalesHistoryActivationGrain"("activationId", "summaryDate", "storeCode");
CREATE INDEX "SalesHistoryActivationGrain_summaryDate_storeCode_createdAt_idx" ON "SalesHistoryActivationGrain"("summaryDate", "storeCode", "createdAt");

ALTER TABLE "SalesHistoryImportJob" ADD CONSTRAINT "SalesHistoryImportJob_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "SalesHistoryVersion"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "SalesHistoryImportGrainStage" ADD CONSTRAINT "SalesHistoryImportGrainStage_jobId_fkey" FOREIGN KEY ("jobId") REFERENCES "SalesHistoryImportJob"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SalesHistoryImportOrderStage" ADD CONSTRAINT "SalesHistoryImportOrderStage_jobId_fkey" FOREIGN KEY ("jobId") REFERENCES "SalesHistoryImportJob"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SalesHistoryCoverage" ADD CONSTRAINT "SalesHistoryCoverage_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "SalesHistoryVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SalesHistoryAggregate" ADD CONSTRAINT "SalesHistoryAggregate_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "SalesHistoryVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SalesHistoryActiveGrain" ADD CONSTRAINT "SalesHistoryActiveGrain_currentVersionId_fkey" FOREIGN KEY ("currentVersionId") REFERENCES "SalesHistoryVersion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "SalesHistoryActivation" ADD CONSTRAINT "SalesHistoryActivation_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "SalesHistoryVersion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "SalesHistoryActivationGrain" ADD CONSTRAINT "SalesHistoryActivationGrain_activationId_fkey" FOREIGN KEY ("activationId") REFERENCES "SalesHistoryActivation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
