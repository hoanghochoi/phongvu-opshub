CREATE TABLE "SalesReportCategoryGroup" (
  "id" TEXT NOT NULL,
  "catGroupName" TEXT NOT NULL,
  "catGroupNameVi" TEXT NOT NULL,
  "sourceRowCount" INTEGER NOT NULL DEFAULT 0,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "SalesReportCategoryGroup_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesReport" (
  "id" TEXT NOT NULL,
  "reportType" TEXT NOT NULL,
  "orderCode" TEXT,
  "customerPhone" TEXT,
  "customerNeed" TEXT,
  "categoryGroupId" TEXT NOT NULL,
  "categoryGroupName" TEXT NOT NULL,
  "categoryGroupNameVi" TEXT NOT NULL,
  "consultedSolutionAnswer" TEXT NOT NULL,
  "consultedSolutionOtherReason" TEXT,
  "experiencedAnswer" TEXT NOT NULL,
  "experiencedOtherReason" TEXT,
  "zaloAnswer" TEXT NOT NULL,
  "zaloOtherReason" TEXT,
  "appDownloadAnswer" TEXT NOT NULL,
  "appDownloadOtherReason" TEXT,
  "notPurchasedReason" TEXT,
  "notPurchasedOtherReason" TEXT,
  "createdByUserId" TEXT,
  "createdByEmail" TEXT,
  "createdByName" TEXT,
  "createdByPersonnelCode" TEXT,
  "storeCode" TEXT,
  "storeName" TEXT,
  "organizationNodeId" TEXT,
  "organizationNodeName" TEXT,
  "regionCode" TEXT,
  "areaCode" TEXT,
  "erpOrderId" TEXT,
  "erpExternalOrderRef" TEXT,
  "erpOrderCreatedAt" TIMESTAMP(3),
  "erpPaymentStatus" TEXT,
  "erpConfirmationStatus" TEXT,
  "erpFulfillmentStatus" TEXT,
  "erpTerminalName" TEXT,
  "erpGrandTotal" INTEGER,
  "erpPlatformId" INTEGER,
  "erpConsultantCustomId" TEXT,
  "erpConsultantName" TEXT,
  "erpSnapshot" JSONB,
  "erpFetchedAt" TIMESTAMP(3),
  "erpFetchStatus" TEXT,
  "rawResponses" JSONB,
  "submittedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "SalesReport_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesReportOrderItem" (
  "id" TEXT NOT NULL,
  "salesReportId" TEXT NOT NULL,
  "sku" TEXT,
  "sellerSku" TEXT,
  "name" TEXT,
  "brandCode" TEXT,
  "brandName" TEXT,
  "productTypeCode" TEXT,
  "productTypeName" TEXT,
  "productGroupId" TEXT,
  "productGroupName" TEXT,
  "quantity" INTEGER,
  "sellPrice" INTEGER,
  "finalSellPrice" INTEGER,
  "rowTotal" INTEGER,
  "raw" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "SalesReportOrderItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SalesReportPayment" (
  "id" TEXT NOT NULL,
  "salesReportId" TEXT NOT NULL,
  "paymentMethod" TEXT,
  "amount" INTEGER,
  "paidAt" TIMESTAMP(3),
  "transactionCode" TEXT,
  "partnerTransactionCode" TEXT,
  "raw" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "SalesReportPayment_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SalesReport_orderCode_key"
  ON "SalesReport"("orderCode");

CREATE INDEX "SalesReportCategoryGroup_isActive_sortOrder_idx"
  ON "SalesReportCategoryGroup"("isActive", "sortOrder");

CREATE INDEX "SalesReport_reportType_submittedAt_idx"
  ON "SalesReport"("reportType", "submittedAt");

CREATE INDEX "SalesReport_storeCode_submittedAt_idx"
  ON "SalesReport"("storeCode", "submittedAt");

CREATE INDEX "SalesReport_createdByUserId_submittedAt_idx"
  ON "SalesReport"("createdByUserId", "submittedAt");

CREATE INDEX "SalesReport_categoryGroupId_submittedAt_idx"
  ON "SalesReport"("categoryGroupId", "submittedAt");

CREATE INDEX "SalesReport_erpOrderId_idx"
  ON "SalesReport"("erpOrderId");

CREATE INDEX "SalesReport_notPurchasedReason_submittedAt_idx"
  ON "SalesReport"("notPurchasedReason", "submittedAt");

CREATE INDEX "SalesReport_organizationNodeId_submittedAt_idx"
  ON "SalesReport"("organizationNodeId", "submittedAt");

CREATE INDEX "SalesReportOrderItem_salesReportId_idx"
  ON "SalesReportOrderItem"("salesReportId");

CREATE INDEX "SalesReportOrderItem_sku_idx"
  ON "SalesReportOrderItem"("sku");

CREATE INDEX "SalesReportOrderItem_sellerSku_idx"
  ON "SalesReportOrderItem"("sellerSku");

CREATE INDEX "SalesReportOrderItem_brandName_idx"
  ON "SalesReportOrderItem"("brandName");

CREATE INDEX "SalesReportOrderItem_productGroupName_idx"
  ON "SalesReportOrderItem"("productGroupName");

CREATE INDEX "SalesReportPayment_salesReportId_idx"
  ON "SalesReportPayment"("salesReportId");

CREATE INDEX "SalesReportPayment_paymentMethod_idx"
  ON "SalesReportPayment"("paymentMethod");

CREATE INDEX "SalesReportPayment_paidAt_idx"
  ON "SalesReportPayment"("paidAt");

ALTER TABLE "SalesReport"
  ADD CONSTRAINT "SalesReport_categoryGroupId_fkey"
  FOREIGN KEY ("categoryGroupId") REFERENCES "SalesReportCategoryGroup"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "SalesReport"
  ADD CONSTRAINT "SalesReport_createdByUserId_fkey"
  FOREIGN KEY ("createdByUserId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "SalesReportOrderItem"
  ADD CONSTRAINT "SalesReportOrderItem_salesReportId_fkey"
  FOREIGN KEY ("salesReportId") REFERENCES "SalesReport"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "SalesReportPayment"
  ADD CONSTRAINT "SalesReportPayment_salesReportId_fkey"
  FOREIGN KEY ("salesReportId") REFERENCES "SalesReport"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
