ALTER TABLE "MapVietinTransaction"
ADD COLUMN "incomeType" TEXT NOT NULL DEFAULT 'SALES';

UPDATE "MapVietinTransaction"
SET "incomeType" = 'PARTNER_INTERNAL'
WHERE
  upper(regexp_replace(trim(coalesce("content", '')), '[^a-zA-Z0-9]+', ' ', 'g')) ~ '(^| )BC (CN|CP|CTY|DKKD)[A-Z0-9]*( |$)'
  OR upper(regexp_replace(trim(coalesce("content", '')), '[^a-zA-Z0-9]+', ' ', 'g')) ~ '(^| )(SO GD GOC|RECESS|VNSHOP|SHOPEE|SHOPEEPAY|VNPAY|ZALOPAY|GIAOHANGTIETKIEM|NHAT TIN|THEO LO EMB|KHDN)( |$)'
  OR upper(regexp_replace(trim(coalesce("content", '')), '[^a-zA-Z0-9]+', ' ', 'g')) ~ '(^| )(TT|CHUYEN TIEN) COD( |$)';

ALTER TABLE "MapVietinTransaction"
ADD CONSTRAINT "MapVietinTransaction_incomeType_check"
CHECK ("incomeType" IN ('SALES', 'PARTNER_INTERNAL'));

CREATE INDEX "MapVietinTransaction_storeCode_incomeType_paidAt_idx"
ON "MapVietinTransaction"("storeCode", "incomeType", "paidAt");

CREATE INDEX "MapVietinTransaction_incomeType_paidAt_idx"
ON "MapVietinTransaction"("incomeType", "paidAt");
