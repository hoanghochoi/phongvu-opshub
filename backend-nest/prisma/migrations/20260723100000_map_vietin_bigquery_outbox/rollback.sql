DROP TRIGGER IF EXISTS "MapVietinTransaction_bigquery_revision_after_write"
ON "MapVietinTransaction";

DROP TRIGGER IF EXISTS "MapVietinTransaction_bigquery_revision_before_write"
ON "MapVietinTransaction";

DROP FUNCTION IF EXISTS "opshub_map_vietin_bigquery_revision_after_write"();
DROP FUNCTION IF EXISTS "opshub_map_vietin_bigquery_revision_before_write"();
DROP FUNCTION IF EXISTS "opshub_enqueue_map_vietin_bigquery_transaction"(TEXT);
DROP FUNCTION IF EXISTS "opshub_map_vietin_bigquery_payload"(
  "MapVietinTransaction",
  BIGINT,
  BOOLEAN
);

DROP INDEX IF EXISTS "DomainOutboxEvent_map_vietin_bigquery_claim_idx";
DROP TABLE IF EXISTS "MapVietinBigQueryBackfillCheckpoint";

DELETE FROM "DomainOutboxEvent"
WHERE "eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION';

ALTER TABLE "DomainOutboxEvent"
DROP COLUMN IF EXISTS "deadLetteredAt";

ALTER TABLE "MapVietinTransaction"
DROP COLUMN IF EXISTS "bigQueryRevision";
