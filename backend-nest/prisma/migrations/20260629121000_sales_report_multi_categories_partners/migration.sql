ALTER TABLE "SalesReport"
  ADD COLUMN "installmentPartnerCodes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

CREATE TABLE "SalesReportCategorySelection" (
  "id" TEXT NOT NULL,
  "salesReportId" TEXT NOT NULL,
  "categoryGroupId" TEXT NOT NULL,
  "categoryGroupName" TEXT NOT NULL,
  "categoryGroupNameVi" TEXT NOT NULL,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "SalesReportCategorySelection_pkey" PRIMARY KEY ("id")
);

INSERT INTO "SalesReportCategorySelection" (
  "id",
  "salesReportId",
  "categoryGroupId",
  "categoryGroupName",
  "categoryGroupNameVi",
  "sortOrder"
)
SELECT
  "id" || ':' || "categoryGroupId",
  "id",
  "categoryGroupId",
  "categoryGroupName",
  "categoryGroupNameVi",
  0
FROM "SalesReport";

CREATE UNIQUE INDEX "SalesReportCategorySelection_salesReportId_categoryGroupId_key"
  ON "SalesReportCategorySelection"("salesReportId", "categoryGroupId");

CREATE INDEX "SalesReportCategorySelection_salesReportId_sortOrder_idx"
  ON "SalesReportCategorySelection"("salesReportId", "sortOrder");

CREATE INDEX "SalesReportCategorySelection_categoryGroupId_idx"
  ON "SalesReportCategorySelection"("categoryGroupId");

ALTER TABLE "SalesReportCategorySelection"
  ADD CONSTRAINT "SalesReportCategorySelection_salesReportId_fkey"
  FOREIGN KEY ("salesReportId") REFERENCES "SalesReport"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "SalesReportCategorySelection"
  ADD CONSTRAINT "SalesReportCategorySelection_categoryGroupId_fkey"
  FOREIGN KEY ("categoryGroupId") REFERENCES "SalesReportCategoryGroup"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;
