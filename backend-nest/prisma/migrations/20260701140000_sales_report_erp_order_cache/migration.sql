CREATE TABLE "SalesReportErpOrderCache" (
    "id" TEXT NOT NULL,
    "orderCode" TEXT NOT NULL,
    "erpOrderId" TEXT,
    "erpExternalOrderRef" TEXT,
    "orderCreatedAt" TIMESTAMP(3),
    "paymentStatus" TEXT,
    "confirmationStatus" TEXT,
    "fulfillmentStatus" TEXT,
    "terminalName" TEXT,
    "grandTotal" INTEGER,
    "customerName" TEXT,
    "customerPhone" TEXT,
    "customerType" TEXT,
    "paymentMethods" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "platformId" INTEGER,
    "consultantCustomId" TEXT,
    "consultantName" TEXT,
    "consultantEmail" TEXT,
    "sellerId" TEXT,
    "sellerName" TEXT,
    "sellerEmail" TEXT,
    "storeCode" TEXT,
    "storeName" TEXT,
    "organizationNodeId" TEXT,
    "sourceUserId" TEXT,
    "sourceUserEmail" TEXT,
    "sanitizedSnapshot" JSONB,
    "fetchedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SalesReportErpOrderCache_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SalesReportErpOrderCache_orderCode_key" ON "SalesReportErpOrderCache"("orderCode");
CREATE INDEX "SalesReportErpOrderCache_orderCreatedAt_idx" ON "SalesReportErpOrderCache"("orderCreatedAt");
CREATE INDEX "SalesReportErpOrderCache_storeCode_orderCreatedAt_idx" ON "SalesReportErpOrderCache"("storeCode", "orderCreatedAt");
CREATE INDEX "SalesReportErpOrderCache_organizationNodeId_orderCreatedAt_idx" ON "SalesReportErpOrderCache"("organizationNodeId", "orderCreatedAt");
CREATE INDEX "SalesReportErpOrderCache_consultantEmail_orderCreatedAt_idx" ON "SalesReportErpOrderCache"("consultantEmail", "orderCreatedAt");
CREATE INDEX "SalesReportErpOrderCache_sellerEmail_orderCreatedAt_idx" ON "SalesReportErpOrderCache"("sellerEmail", "orderCreatedAt");
CREATE INDEX "SalesReportErpOrderCache_sourceUserEmail_orderCreatedAt_idx" ON "SalesReportErpOrderCache"("sourceUserEmail", "orderCreatedAt");
CREATE INDEX "SalesReportErpOrderCache_consultantCustomId_orderCreatedAt_idx" ON "SalesReportErpOrderCache"("consultantCustomId", "orderCreatedAt");
CREATE INDEX "SalesReportErpOrderCache_sellerId_orderCreatedAt_idx" ON "SalesReportErpOrderCache"("sellerId", "orderCreatedAt");
