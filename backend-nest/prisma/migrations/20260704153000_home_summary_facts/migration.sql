CREATE TABLE "HomeSummaryOrderFact" (
    "id" TEXT NOT NULL,
    "summaryDate" TIMESTAMP(3) NOT NULL,
    "orderCode" TEXT NOT NULL,
    "orderCreatedAt" TIMESTAMP(3),
    "fetchedAt" TIMESTAMP(3),
    "storeCode" TEXT,
    "storeName" TEXT,
    "organizationNodeId" TEXT,
    "sourceUserId" TEXT,
    "sourceUserEmail" TEXT,
    "consultantCustomId" TEXT,
    "consultantName" TEXT,
    "consultantEmail" TEXT,
    "sellerId" TEXT,
    "sellerName" TEXT,
    "sellerEmail" TEXT,
    "grandTotal" INTEGER,
    "hasValidReport" BOOLEAN NOT NULL DEFAULT false,
    "reportId" TEXT,
    "reportSubmittedAt" TIMESTAMP(3),
    "reportRevenue" INTEGER,
    "reportCreatedByUserId" TEXT,
    "reportCreatedByEmail" TEXT,
    "reportCreatedByPersonnelCode" TEXT,
    "refreshedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "HomeSummaryOrderFact_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "HomeSummaryReportFact" (
    "id" TEXT NOT NULL,
    "summaryDate" TIMESTAMP(3) NOT NULL,
    "salesReportId" TEXT NOT NULL,
    "reportType" TEXT NOT NULL,
    "orderCode" TEXT,
    "createdByUserId" TEXT,
    "createdByEmail" TEXT,
    "createdByPersonnelCode" TEXT,
    "storeCode" TEXT,
    "storeName" TEXT,
    "organizationNodeId" TEXT,
    "revenue" INTEGER,
    "submittedAt" TIMESTAMP(3) NOT NULL,
    "refreshedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "HomeSummaryReportFact_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "HomeSummaryOrderFact_orderCode_key" ON "HomeSummaryOrderFact"("orderCode");
CREATE UNIQUE INDEX "HomeSummaryReportFact_salesReportId_key" ON "HomeSummaryReportFact"("salesReportId");

CREATE INDEX "HomeSummaryOrderFact_summaryDate_storeCode_idx" ON "HomeSummaryOrderFact"("summaryDate", "storeCode");
CREATE INDEX "HomeSummaryOrderFact_summaryDate_organizationNodeId_idx" ON "HomeSummaryOrderFact"("summaryDate", "organizationNodeId");
CREATE INDEX "HomeSummaryOrderFact_summaryDate_sourceUserId_idx" ON "HomeSummaryOrderFact"("summaryDate", "sourceUserId");
CREATE INDEX "HomeSummaryOrderFact_summaryDate_sourceUserEmail_idx" ON "HomeSummaryOrderFact"("summaryDate", "sourceUserEmail");
CREATE INDEX "HomeSummaryOrderFact_summaryDate_consultantCustomId_idx" ON "HomeSummaryOrderFact"("summaryDate", "consultantCustomId");
CREATE INDEX "HomeSummaryOrderFact_summaryDate_consultantEmail_idx" ON "HomeSummaryOrderFact"("summaryDate", "consultantEmail");
CREATE INDEX "HomeSummaryOrderFact_summaryDate_sellerId_idx" ON "HomeSummaryOrderFact"("summaryDate", "sellerId");
CREATE INDEX "HomeSummaryOrderFact_summaryDate_sellerEmail_idx" ON "HomeSummaryOrderFact"("summaryDate", "sellerEmail");

CREATE INDEX "HomeSummaryReportFact_summaryDate_reportType_idx" ON "HomeSummaryReportFact"("summaryDate", "reportType");
CREATE INDEX "HomeSummaryReportFact_summaryDate_orderCode_idx" ON "HomeSummaryReportFact"("summaryDate", "orderCode");
CREATE INDEX "HomeSummaryReportFact_summaryDate_storeCode_idx" ON "HomeSummaryReportFact"("summaryDate", "storeCode");
CREATE INDEX "HomeSummaryReportFact_summaryDate_organizationNodeId_idx" ON "HomeSummaryReportFact"("summaryDate", "organizationNodeId");
CREATE INDEX "HomeSummaryReportFact_summaryDate_createdByUserId_idx" ON "HomeSummaryReportFact"("summaryDate", "createdByUserId");
CREATE INDEX "HomeSummaryReportFact_summaryDate_createdByEmail_idx" ON "HomeSummaryReportFact"("summaryDate", "createdByEmail");
CREATE INDEX "HomeSummaryReportFact_summaryDate_createdByPersonnelCode_idx" ON "HomeSummaryReportFact"("summaryDate", "createdByPersonnelCode");
