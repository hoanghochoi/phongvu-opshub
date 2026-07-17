ALTER TABLE "SalesReport"
ADD COLUMN "customerContactChannels" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

UPDATE "SalesReport"
SET "customerContactChannels" = ARRAY_REMOVE(
  ARRAY[
    CASE
      WHEN (
        "reportType" = 'NOT_PURCHASED'
        AND btrim(COALESCE("customerPhone", '')) ~ '^0[0-9]{9}$'
      ) OR (
        "reportType" <> 'NOT_PURCHASED'
        AND btrim(COALESCE("customerPhone", '')) <> ''
      )
      THEN 'PHONE'
      ELSE NULL
    END,
    CASE
      WHEN lower(btrim(COALESCE("customerPhone", ''))) = '0zalo'
        OR btrim(COALESCE("customerZaloContact", '')) <> ''
      THEN 'ZALO_PERSONAL'
      ELSE NULL
    END
  ],
  NULL
);

UPDATE "SalesReport"
SET "customerPhone" = btrim("customerPhone")
WHERE "reportType" = 'NOT_PURCHASED'
  AND btrim(COALESCE("customerPhone", '')) ~ '^0[0-9]{9}$';

UPDATE "SalesReport"
SET "customerPhone" = NULL
WHERE "reportType" = 'NOT_PURCHASED'
  AND btrim(COALESCE("customerPhone", '')) !~ '^0[0-9]{9}$';

ALTER TABLE "SalesReport"
ADD CONSTRAINT "SalesReport_customerContactChannels_check"
CHECK (
  "customerContactChannels" <@ ARRAY['PHONE', 'ZALO_PERSONAL', 'ZALO_OA']::TEXT[]
  AND array_position("customerContactChannels", NULL) IS NULL
),
ADD CONSTRAINT "SalesReport_notPurchasedPhone_check"
CHECK (
  "reportType" <> 'NOT_PURCHASED'
  OR "customerPhone" IS NULL
  OR "customerPhone" ~ '^0[0-9]{9}$'
),
ADD CONSTRAINT "SalesReport_notPurchasedPhoneChannel_check"
CHECK (
  "reportType" <> 'NOT_PURCHASED'
  OR ("customerPhone" IS NOT NULL) = ('PHONE' = ANY("customerContactChannels"))
);
