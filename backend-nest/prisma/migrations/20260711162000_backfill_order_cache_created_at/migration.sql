UPDATE "SalesReportErpOrderCache"
SET "orderCreatedAt" = ("sanitizedSnapshot"->>'createdAt')::timestamptz
WHERE "orderCreatedAt" IS NULL
  AND jsonb_typeof("sanitizedSnapshot") = 'object'
  AND "sanitizedSnapshot" ? 'createdAt'
  AND ("sanitizedSnapshot"->>'createdAt') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T';

WITH corrected AS (
  SELECT
    fact."id",
    cache."orderCreatedAt",
    date_trunc(
      'day',
      cache."orderCreatedAt" AT TIME ZONE 'Asia/Ho_Chi_Minh'
    ) AT TIME ZONE 'Asia/Ho_Chi_Minh' AS "summaryDate"
  FROM "HomeSummaryOrderFact" fact
  JOIN "SalesReportErpOrderCache" cache
    ON cache."orderCode" = fact."orderCode"
  WHERE cache."orderCreatedAt" IS NOT NULL
    AND (
      fact."orderCreatedAt" IS NULL
      OR fact."orderCreatedAt" <> cache."orderCreatedAt"
      OR fact."summaryDate" <> (
        date_trunc(
          'day',
          cache."orderCreatedAt" AT TIME ZONE 'Asia/Ho_Chi_Minh'
        ) AT TIME ZONE 'Asia/Ho_Chi_Minh'
      )
    )
)
UPDATE "HomeSummaryOrderFact" fact
SET
  "orderCreatedAt" = corrected."orderCreatedAt",
  "summaryDate" = corrected."summaryDate"
FROM corrected
WHERE fact."id" = corrected."id";
