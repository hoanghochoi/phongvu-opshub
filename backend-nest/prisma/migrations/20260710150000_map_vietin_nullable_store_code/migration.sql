ALTER TABLE "MapVietinTransaction"
ALTER COLUMN "storeCode" DROP NOT NULL;

ALTER TABLE "MapVietinTransactionOrderAudit"
ALTER COLUMN "storeCode" DROP NOT NULL;
