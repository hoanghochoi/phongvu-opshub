ALTER TABLE "SalesReport"
  ADD COLUMN "customerName" TEXT;

ALTER TABLE "SalesReportOrderItem"
  ADD COLUMN "categoryType" TEXT;

CREATE INDEX "SalesReportOrderItem_categoryType_idx"
  ON "SalesReportOrderItem"("categoryType");
