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

DROP FUNCTION IF EXISTS "opshub_map_vietin_bigquery_revision_snapshot"(
  "MapVietinTransaction"
);
