ALTER TABLE "MapVietinTransaction"
ADD COLUMN "bigQueryRevision" BIGINT NOT NULL DEFAULT 0;

ALTER TABLE "DomainOutboxEvent"
ADD COLUMN "deadLetteredAt" TIMESTAMP(3);

CREATE TABLE "MapVietinBigQueryBackfillCheckpoint" (
  "jobKey" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "upperBoundFirstSeenAt" TIMESTAMP(3) NOT NULL,
  "upperBoundTransactionId" TEXT NOT NULL,
  "lastFirstSeenAt" TIMESTAMP(3),
  "lastTransactionId" TEXT,
  "claimToken" TEXT,
  "leaseExpiresAt" TIMESTAMP(3),
  "pagesProcessed" INTEGER NOT NULL DEFAULT 0,
  "rowsEnqueued" INTEGER NOT NULL DEFAULT 0,
  "lastError" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "MapVietinBigQueryBackfillCheckpoint_pkey" PRIMARY KEY ("jobKey")
);

CREATE INDEX "MapVietinBigQueryBackfillCheckpoint_status_leaseExpiresAt_updatedAt_idx"
ON "MapVietinBigQueryBackfillCheckpoint"("status", "leaseExpiresAt", "updatedAt");

CREATE INDEX "DomainOutboxEvent_map_vietin_bigquery_claim_idx"
ON "DomainOutboxEvent"("availableAt", "leaseExpiresAt", "occurredAt")
WHERE "eventType" = 'MAP_VIETIN_BIGQUERY_TRANSACTION_REVISION'
  AND "publishedAt" IS NULL
  AND "deadLetteredAt" IS NULL;

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
    'status', transaction_row."status",
    'paid_at', CASE
      WHEN transaction_row."paidAt" IS NULL THEN NULL
      ELSE to_char(transaction_row."paidAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    END,
    'income_type', transaction_row."incomeType",
    'provider_source', NULLIF(transaction_row."rawData" #>> '{source}', ''),
    'first_seen_at', to_char(transaction_row."firstSeenAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source_created_at', to_char(transaction_row."createdAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source_updated_at', to_char(transaction_row."updatedAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'is_deleted', deleted_value
  );
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

CREATE OR REPLACE FUNCTION "opshub_map_vietin_bigquery_revision_before_write"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW."bigQueryRevision" := 1;
    RETURN NEW;
  END IF;

  IF NEW."storeCode" IS DISTINCT FROM OLD."storeCode"
    OR NEW."transactionNumber" IS DISTINCT FROM OLD."transactionNumber"
    OR NEW."amount" IS DISTINCT FROM OLD."amount"
    OR NEW."orders" IS DISTINCT FROM OLD."orders"
    OR NEW."orderSource" IS DISTINCT FROM OLD."orderSource"
    OR NEW."status" IS DISTINCT FROM OLD."status"
    OR NEW."paidAt" IS DISTINCT FROM OLD."paidAt"
    OR NEW."incomeType" IS DISTINCT FROM OLD."incomeType"
    OR NEW."firstSeenAt" IS DISTINCT FROM OLD."firstSeenAt"
    OR (NEW."rawData" #>> '{source}') IS DISTINCT FROM (OLD."rawData" #>> '{source}')
    OR (NEW."rawData" #>> '{providerIdentifiers,efastTrxId}')
      IS DISTINCT FROM (OLD."rawData" #>> '{providerIdentifiers,efastTrxId}')
    OR (NEW."rawData" #>> '{providerIdentifiers,mapTransactionNumber}')
      IS DISTINCT FROM (OLD."rawData" #>> '{providerIdentifiers,mapTransactionNumber}')
  THEN
    NEW."bigQueryRevision" := OLD."bigQueryRevision" + 1;
  ELSE
    NEW."bigQueryRevision" := OLD."bigQueryRevision";
  END IF;

  RETURN NEW;
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

CREATE TRIGGER "MapVietinTransaction_bigquery_revision_before_write"
BEFORE INSERT OR UPDATE ON "MapVietinTransaction"
FOR EACH ROW
EXECUTE FUNCTION "opshub_map_vietin_bigquery_revision_before_write"();

CREATE TRIGGER "MapVietinTransaction_bigquery_revision_after_write"
AFTER INSERT OR UPDATE OR DELETE ON "MapVietinTransaction"
FOR EACH ROW
EXECUTE FUNCTION "opshub_map_vietin_bigquery_revision_after_write"();
