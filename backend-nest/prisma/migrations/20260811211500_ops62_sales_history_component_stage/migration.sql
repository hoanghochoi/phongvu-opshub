ALTER TABLE "SalesHistoryImportOrderStage"
ADD COLUMN "cpuQuantity" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "mainboardQuantity" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "memoryQuantity" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "storageQuantity" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "caseQuantity" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "psuQuantity" INTEGER NOT NULL DEFAULT 0;

CREATE INDEX "SalesHistoryImportOrderStage_jobId_orderHash_idx"
ON "SalesHistoryImportOrderStage"("jobId", "orderHash");
