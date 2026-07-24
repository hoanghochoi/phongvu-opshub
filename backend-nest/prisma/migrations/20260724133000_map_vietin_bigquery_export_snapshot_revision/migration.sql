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
