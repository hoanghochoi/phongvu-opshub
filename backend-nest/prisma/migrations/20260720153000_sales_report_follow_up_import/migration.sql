-- CreateTable
CREATE TABLE "SalesReportImportBatch" (
    "id" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "fileHash" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PROCESSING',
    "importedByUserId" TEXT,
    "importedByEmail" TEXT,
    "importedByName" TEXT,
    "totalRows" INTEGER NOT NULL DEFAULT 0,
    "validRows" INTEGER NOT NULL DEFAULT 0,
    "importedRows" INTEGER NOT NULL DEFAULT 0,
    "purchasedRows" INTEGER NOT NULL DEFAULT 0,
    "duplicateRows" INTEGER NOT NULL DEFAULT 0,
    "invalidRows" INTEGER NOT NULL DEFAULT 0,
    "unassignedRows" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "SalesReportImportBatch_pkey" PRIMARY KEY ("id")
);

-- AlterTable
ALTER TABLE "SalesReport"
ADD COLUMN "sourceSalespersonCode" TEXT,
ADD COLUMN "importFingerprint" TEXT,
ADD COLUMN "importBatchId" TEXT;

-- CreateIndex
CREATE INDEX "SalesReportImportBatch_fileHash_createdAt_idx" ON "SalesReportImportBatch"("fileHash", "createdAt");
CREATE INDEX "SalesReportImportBatch_importedByUserId_createdAt_idx" ON "SalesReportImportBatch"("importedByUserId", "createdAt");
CREATE INDEX "SalesReportImportBatch_status_createdAt_idx" ON "SalesReportImportBatch"("status", "createdAt");
CREATE UNIQUE INDEX "SalesReport_importFingerprint_key" ON "SalesReport"("importFingerprint");
CREATE INDEX "SalesReport_importBatchId_idx" ON "SalesReport"("importBatchId");

-- AddForeignKey
ALTER TABLE "SalesReport" ADD CONSTRAINT "SalesReport_importBatchId_fkey"
FOREIGN KEY ("importBatchId") REFERENCES "SalesReportImportBatch"("id")
ON DELETE SET NULL ON UPDATE CASCADE;
