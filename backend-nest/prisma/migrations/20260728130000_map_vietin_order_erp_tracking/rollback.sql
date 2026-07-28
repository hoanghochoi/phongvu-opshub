-- Restore the schema-v1 producer before removing tracking columns. Keep
-- bigQueryRevision monotonic and retain already-enqueued/exported v2 rows;
-- the nullable BigQuery warehouse column is intentionally not removed here.
CREATE OR REPLACE FUNCTION "opshub_map_vietin_bigquery_payload"(
  transaction_row "MapVietinTransaction",
  revision_value BIGINT,
  deleted_value BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN jsonb_build_object(
    'transaction_id', transaction_row."id",
    'revision', revision_value::text,
    'transaction_date', to_char(
      (
        (COALESCE(transaction_row."paidAt", transaction_row."firstSeenAt") AT TIME ZONE 'UTC')
        AT TIME ZONE 'Asia/Ho_Chi_Minh'
      )::date,
      'YYYY-MM-DD'
    ),
    'store_code', transaction_row."storeCode",
    'statement_number', COALESCE(
      NULLIF(transaction_row."rawData" #>> '{providerIdentifiers,efastTrxId}', ''),
      NULLIF(transaction_row."rawData" #>> '{providerIdentifiers,mapTransactionNumber}', ''),
      NULLIF(transaction_row."transactionNumber", '')
    ),
    'amount', transaction_row."amount",
    'orders', to_jsonb(transaction_row."orders"),
    'order_source', transaction_row."orderSource",
    'status', "opshub_map_vietin_bigquery_canonical_status"(
      transaction_row."status"
    ),
    'paid_at', CASE
      WHEN transaction_row."paidAt" IS NULL THEN NULL
      ELSE to_char(transaction_row."paidAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    END,
    'income_type', transaction_row."incomeType",
    'provider_source', "opshub_map_vietin_bigquery_provider_source"(
      transaction_row."rawData"
    ),
    'first_seen_at', to_char(transaction_row."firstSeenAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source_created_at', to_char(transaction_row."createdAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source_updated_at', to_char(transaction_row."updatedAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'is_deleted', deleted_value
  );
END;
$$;

CREATE OR REPLACE FUNCTION "opshub_map_vietin_bigquery_revision_snapshot"(
  transaction_row "MapVietinTransaction"
)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT "opshub_map_vietin_bigquery_payload"(
    transaction_row,
    0,
    FALSE
  )
    - 'revision'
    - 'provider_source'
    - 'source_updated_at';
$$;

CREATE OR REPLACE FUNCTION "opshub_map_vietin_bigquery_revision_before_write"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW."bigQueryRevision" := 1;
    RETURN NEW;
  END IF;

  IF "opshub_map_vietin_bigquery_revision_snapshot"(NEW)
    IS DISTINCT FROM "opshub_map_vietin_bigquery_revision_snapshot"(OLD)
  THEN
    NEW."bigQueryRevision" := OLD."bigQueryRevision" + 1;
  ELSE
    NEW."bigQueryRevision" := OLD."bigQueryRevision";
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "opshub_enqueue_map_vietin_bigquery_transaction"(
  transaction_id_value TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  transaction_row "MapVietinTransaction"%ROWTYPE;
  event_id_value TEXT := gen_random_uuid()::text;
  inserted_count INTEGER := 0;
BEGIN
  SELECT *
  INTO transaction_row
  FROM "MapVietinTransaction"
  WHERE "id" = transaction_id_value;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  INSERT INTO "DomainOutboxEvent" (
    "id", "eventType", "aggregateType", "aggregateId", "dedupeKey",
    "schemaVersion", "payload", "occurredAt", "availableAt", "createdAt", "updatedAt"
  )
  VALUES (
    event_id_value,
    'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION',
    'MapVietinTransaction',
    transaction_row."id",
    'map-vietin-bigquery:' || transaction_row."id" || ':' || transaction_row."bigQueryRevision"::text,
    1,
    "opshub_map_vietin_bigquery_payload"(
      transaction_row,
      transaction_row."bigQueryRevision",
      FALSE
    ),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  )
  ON CONFLICT ("dedupeKey") DO NOTHING;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count = 1;
END;
$$;

CREATE OR REPLACE FUNCTION "opshub_map_vietin_bigquery_revision_after_write"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  event_id_value TEXT;
  tombstone_revision BIGINT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    event_id_value := gen_random_uuid()::text;
    tombstone_revision := OLD."bigQueryRevision" + 1;

    INSERT INTO "DomainOutboxEvent" (
      "id", "eventType", "aggregateType", "aggregateId", "dedupeKey",
      "schemaVersion", "payload", "occurredAt", "availableAt", "createdAt", "updatedAt"
    )
    VALUES (
      event_id_value,
      'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION',
      'MapVietinTransaction',
      OLD."id",
      'map-vietin-bigquery:' || OLD."id" || ':' || tombstone_revision::text,
      1,
      "opshub_map_vietin_bigquery_payload"(OLD, tombstone_revision, TRUE),
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
    )
    ON CONFLICT ("dedupeKey") DO NOTHING;

    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' OR NEW."bigQueryRevision" <> OLD."bigQueryRevision" THEN
    PERFORM "opshub_enqueue_map_vietin_bigquery_transaction"(NEW."id");
  END IF;

  RETURN NEW;
END;
$$;

DROP TABLE IF EXISTS "MapVietinTransactionOrderTrackingAudit";

DROP INDEX IF EXISTS "MapVietinTransaction_storeCode_orderTrackingStatus_paidAt_idx";
DROP INDEX IF EXISTS "MapVietinTransaction_orderTrackingStatus_paidAt_idx";

ALTER TABLE "MapVietinTransaction"
DROP CONSTRAINT IF EXISTS "MapVietinTransaction_orderTrackingStatus_check",
DROP COLUMN IF EXISTS "orderTrackingUpdatedByEmail",
DROP COLUMN IF EXISTS "orderTrackingUpdatedByUserId",
DROP COLUMN IF EXISTS "orderTrackingUpdatedAt",
DROP COLUMN IF EXISTS "orderTrackingStatus";

ALTER TABLE "MapVietinStatementOrderTransferRequest"
DROP COLUMN IF EXISTS "resolutionSource";
