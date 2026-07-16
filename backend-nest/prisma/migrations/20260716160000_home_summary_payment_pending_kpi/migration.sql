ALTER TABLE "HomeSummaryOrderFact"
ADD COLUMN IF NOT EXISTS "isPaymentPending" BOOLEAN NOT NULL DEFAULT false;

UPDATE "HomeSummaryOrderFact" AS fact
SET "isPaymentPending" = true
FROM "SalesReportErpOrderCache" AS cache
WHERE cache."orderCode" = fact."orderCode"
  AND UPPER(
    REGEXP_REPLACE(
      TRIM(COALESCE(cache."paymentStatus", '')),
      '[^a-zA-Z0-9]+',
      '_',
      'g'
    )
  ) IN (
    'PENDING',
    'PENDING_PAYMENT',
    'PAYMENT_PENDING',
    'WAITING_PAYMENT',
    'WAITING_FOR_PAYMENT',
    'AWAITING_PAYMENT',
    'AWAITING_FOR_PAYMENT',
    'UNPAID',
    'NOT_PAID'
  );

SELECT opshub_enqueue_home_summary_projection(summary_date, 'ERP_ORDER_CACHE')
FROM (
  -- summaryDate is stored at Vietnam midnight (17:00 UTC on the previous day).
  -- Convert it back to the Vietnam calendar date before seeding the queue.
  SELECT DISTINCT ("summaryDate" + INTERVAL '7 hours')::date AS summary_date
  FROM "HomeSummaryOrderFact"
  WHERE "isPaymentPending"
) AS affected_dates;

CREATE INDEX IF NOT EXISTS "HomeSummaryOrderFact_summaryDate_isPaymentPending_idx"
ON "HomeSummaryOrderFact"("summaryDate", "isPaymentPending");
