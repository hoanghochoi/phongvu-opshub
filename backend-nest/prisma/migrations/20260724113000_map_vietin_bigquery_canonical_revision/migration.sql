CREATE OR REPLACE FUNCTION "opshub_map_vietin_bigquery_canonical_status"(
  status_value TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  trimmed_status TEXT := NULLIF(BTRIM(status_value), '');
  normalized_status TEXT := UPPER(COALESCE(NULLIF(BTRIM(status_value), ''), ''));
BEGIN
  IF trimmed_status IS NULL THEN
    RETURN NULL;
  END IF;

  IF trimmed_status IN (
    'Thành công',
    'THÀNH CÔNG',
    'Đã thanh toán',
    'ĐÃ THANH TOÁN',
    'Hoàn thành',
    'HOÀN THÀNH'
  ) OR normalized_status IN (
    'SUCCESS',
    'THANH CONG',
    'DA THANH TOAN',
    'HOAN THANH',
    'COMPLETED',
    'APPROVED',
    '00'
  ) THEN
    RETURN 'SUCCESS';
  END IF;

  RETURN trimmed_status;
END;
$$;

CREATE OR REPLACE FUNCTION "opshub_map_vietin_bigquery_provider_source"(
  raw_data JSONB
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN NULLIF(
      BTRIM(raw_data #>> '{providerIdentifiers,efastTrxId}'),
      ''
    ) IS NOT NULL
      OR UPPER(COALESCE(NULLIF(BTRIM(raw_data ->> 'source'), ''), '')) = 'VIETIN_EFAST'
    THEN 'VIETIN_EFAST'
    WHEN NULLIF(
      BTRIM(raw_data #>> '{providerIdentifiers,mapTransactionNumber}'),
      ''
    ) IS NOT NULL
    THEN 'MAP'
    ELSE COALESCE(NULLIF(BTRIM(raw_data ->> 'source'), ''), 'MAP')
  END;
$$;

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
    OR "opshub_map_vietin_bigquery_canonical_status"(NEW."status")
      IS DISTINCT FROM "opshub_map_vietin_bigquery_canonical_status"(OLD."status")
    OR NEW."paidAt" IS DISTINCT FROM OLD."paidAt"
    OR NEW."incomeType" IS DISTINCT FROM OLD."incomeType"
    OR NEW."firstSeenAt" IS DISTINCT FROM OLD."firstSeenAt"
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
