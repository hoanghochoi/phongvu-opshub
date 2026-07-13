-- One-time cleanup for duplicate VietinBank transactions created when eFAST
-- arrived before MAP. The runtime de-dupe fix must be deployed with this
-- migration so the removed rows cannot be recreated.

CREATE TEMP TABLE "_MapEfastDuplicatePairs" ON COMMIT DROP AS
SELECT
  e.id AS "efastId",
  m.id AS "mapId",
  COALESCE(cardinality(e.orders), 0) AS "efastOrderCount",
  COALESCE(cardinality(m.orders), 0) AS "mapOrderCount"
FROM "MapVietinTransaction" e
JOIN "MapVietinTransaction" m
  ON m.id <> e.id
  AND m."storeCode" IS NOT DISTINCT FROM e."storeCode"
  AND m.amount = e.amount
  AND m."paidAt" = e."paidAt"
  AND (
    m."transactionNumber" = e."transactionNumber"
    OR m."rawData"->>'txnReference' = e."transactionNumber"
    OR m."rawData"->>'trxId' = e."transactionNumber"
    OR m."rawData"->>'trxRefNo' = e."transactionNumber"
  )
WHERE e."rawData"->>'source' = 'VIETIN_EFAST'
  AND COALESCE(m."rawData"->>'source', 'MAP') <> 'VIETIN_EFAST';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "_MapEfastDuplicatePairs"
    GROUP BY "efastId"
    HAVING COUNT(*) > 1
  ) OR EXISTS (
    SELECT 1
    FROM "_MapEfastDuplicatePairs"
    GROUP BY "mapId"
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'MAP/eFAST cleanup stopped because duplicate pairing is ambiguous';
  END IF;
END $$;

CREATE TEMP TABLE "_MapEfastDuplicateCleanup" ON COMMIT DROP AS
SELECT
  CASE
    WHEN "efastOrderCount" = 0 AND "mapOrderCount" > 0 THEN "efastId"
    WHEN "mapOrderCount" = 0 AND "efastOrderCount" > 0 THEN "mapId"
    ELSE "efastId"
  END AS "deleteId",
  CASE
    WHEN "efastOrderCount" = 0 AND "mapOrderCount" > 0 THEN "mapId"
    WHEN "mapOrderCount" = 0 AND "efastOrderCount" > 0 THEN "efastId"
    ELSE "mapId"
  END AS "keepId"
FROM "_MapEfastDuplicatePairs";

DO $$
DECLARE
  pair_count INTEGER;
  delete_efast_no_orders INTEGER;
  delete_map_no_orders INTEGER;
  delete_efast_tie INTEGER;
BEGIN
  SELECT
    COUNT(*),
    COUNT(*) FILTER (
      WHERE "efastOrderCount" = 0 AND "mapOrderCount" > 0
    ),
    COUNT(*) FILTER (
      WHERE "mapOrderCount" = 0 AND "efastOrderCount" > 0
    ),
    COUNT(*) FILTER (
      WHERE NOT (
        "efastOrderCount" = 0 AND "mapOrderCount" > 0
      ) AND NOT (
        "mapOrderCount" = 0 AND "efastOrderCount" > 0
      )
    )
  INTO
    pair_count,
    delete_efast_no_orders,
    delete_map_no_orders,
    delete_efast_tie
  FROM "_MapEfastDuplicatePairs";

  RAISE NOTICE
    'MAP/eFAST cleanup selected pairs=%, deleteEfastNoOrders=%, deleteMapNoOrders=%, deleteEfastTie=%',
    pair_count,
    delete_efast_no_orders,
    delete_map_no_orders,
    delete_efast_tie;
END $$;

-- Preserve references and manual history on the transaction that remains.
UPDATE "VietQrPaymentIntent" payment
SET "matchedTransactionId" = cleanup."keepId"
FROM "_MapEfastDuplicateCleanup" cleanup
WHERE payment."matchedTransactionId" = cleanup."deleteId";

UPDATE "MapVietinTransactionOrderAudit" audit
SET "transactionId" = cleanup."keepId"
FROM "_MapEfastDuplicateCleanup" cleanup
WHERE audit."transactionId" = cleanup."deleteId";

UPDATE "MapVietinStatementOrderTransferRequest" transfer_request
SET "transactionId" = cleanup."keepId"
FROM "_MapEfastDuplicateCleanup" cleanup
WHERE transfer_request."transactionId" = cleanup."deleteId";

UPDATE "PaymentNotificationDeliveryLog" delivery
SET "transactionId" = cleanup."keepId"
FROM "_MapEfastDuplicateCleanup" cleanup
WHERE delivery."transactionId" = cleanup."deleteId";

-- When both rows have notifications, remove only the duplicate notification
-- and its delivery history. If the keeper lacks one, reattach the existing
-- notification instead so payment history remains available.
DELETE FROM "PaymentNotificationDeliveryLog" delivery
USING "PaymentNotification" duplicate_notification,
      "PaymentNotification" keeper_notification,
      "_MapEfastDuplicateCleanup" cleanup
WHERE duplicate_notification."transactionId" = cleanup."deleteId"
  AND keeper_notification."transactionId" = cleanup."keepId"
  AND delivery."notificationId" = duplicate_notification.id;

DELETE FROM "PaymentNotification" duplicate_notification
USING "PaymentNotification" keeper_notification,
      "_MapEfastDuplicateCleanup" cleanup
WHERE duplicate_notification."transactionId" = cleanup."deleteId"
  AND keeper_notification."transactionId" = cleanup."keepId";

UPDATE "PaymentNotification" notification
SET "transactionId" = cleanup."keepId"
FROM "_MapEfastDuplicateCleanup" cleanup
WHERE notification."transactionId" = cleanup."deleteId";

DELETE FROM "MapVietinTransaction" tx
USING "_MapEfastDuplicateCleanup" cleanup
WHERE tx.id = cleanup."deleteId";

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "MapVietinTransaction" tx
    JOIN "_MapEfastDuplicateCleanup" cleanup
      ON tx.id = cleanup."deleteId"
  ) THEN
    RAISE EXCEPTION 'MAP/eFAST cleanup verification failed: selected transaction still exists';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM "PaymentNotification" notification
    JOIN "_MapEfastDuplicateCleanup" cleanup
      ON notification."transactionId" = cleanup."deleteId"
  ) THEN
    RAISE EXCEPTION 'MAP/eFAST cleanup verification failed: notification still references deleted transaction';
  END IF;
END $$;
