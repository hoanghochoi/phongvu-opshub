ALTER TABLE "MapVietinTransaction"
ADD COLUMN "incomeTypeSource" TEXT NOT NULL DEFAULT 'AUTO',
ADD COLUMN "incomeTypeUpdatedAt" TIMESTAMP(3),
ADD COLUMN "incomeTypeUpdatedByUserId" TEXT,
ADD COLUMN "incomeTypeUpdatedByEmail" TEXT;

WITH normalized AS (
  SELECT
    "id",
    regexp_replace(UPPER(COALESCE("content", '')), '[[:space:]]+', '', 'g') AS compact_content,
    regexp_replace(UPPER(COALESCE("storeCode", '')), '[[:space:]]+', '', 'g') AS compact_store,
    regexp_replace(UPPER(COALESCE("payerAccount", '')), '[[:space:]]+', '', 'g') AS compact_payer_account
  FROM "MapVietinTransaction"
)
UPDATE "MapVietinTransaction" AS transaction
SET
  "incomeType" = CASE
    WHEN POSITION('NHATTIN' IN normalized.compact_content) > 0
      OR POSITION('VNPAYTT217344' IN normalized.compact_content) > 0
      OR POSITION('SHOPEEPAYMS' IN normalized.compact_content) > 0
      OR POSITION('SHOPEEWSSSELLERWITHDRAWAL' IN normalized.compact_content) > 0
      OR POSITION('GIAOHANGTIETKIEMCHUYENTIENCOD' IN normalized.compact_content) > 0
      OR POSITION('TTGDQUAVIZALOPAY' IN normalized.compact_content) > 0
      OR POSITION('DIEUTIENTUDONG' IN normalized.compact_content) > 0
      OR normalized.compact_content LIKE 'BCCN%'
      OR normalized.compact_content LIKE 'BCCTY%'
      OR normalized.compact_content LIKE 'BCCP%'
      OR normalized.compact_content LIKE 'BCDKKD%'
      OR normalized.compact_payer_account IN (
        '8637988888',
        '0302607125',
        '113000179095',
        '110600994666',
        '1011103131001',
        '0071001142275',
        '117601180666'
      )
      OR (
        normalized.compact_store <> ''
        AND POSITION(
          'TNG' || normalized.compact_store || 'NOPTIEN'
          IN normalized.compact_content
        ) > 0
      )
    THEN 'PARTNER_INTERNAL'
    ELSE 'SALES'
  END,
  "incomeTypeSource" = 'AUTO',
  "incomeTypeUpdatedAt" = NULL,
  "incomeTypeUpdatedByUserId" = NULL,
  "incomeTypeUpdatedByEmail" = NULL
FROM normalized
WHERE transaction."id" = normalized."id";

ALTER TABLE "MapVietinTransaction"
ADD CONSTRAINT "MapVietinTransaction_incomeTypeSource_check"
CHECK ("incomeTypeSource" IN ('AUTO', 'MANUAL'));
