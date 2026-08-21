CREATE TYPE "BankConnectionOperatingMode" AS ENUM (
  'STOPPED',
  'UAT_INGEST_ONLY',
  'LIVE'
);

ALTER TABLE "BankConnectionControl"
  ADD COLUMN "operatingMode" "BankConnectionOperatingMode" NOT NULL DEFAULT 'STOPPED';

-- Expansion is deliberately fail-closed. A deploy never inherits an enabled
-- legacy pair and never starts projecting an existing UAT backlog.
UPDATE "BankConnectionControl"
SET "operatingMode" = 'STOPPED',
    "ingressEnabled" = false,
    "projectionEnabled" = false,
    "version" = "version" + 1,
    "updatedAt" = CURRENT_TIMESTAMP;

CREATE OR REPLACE FUNCTION sync_bank_connection_operating_mode()
RETURNS trigger AS $$
DECLARE
  mode_changed boolean;
  legacy_changed boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    mode_changed := NEW."operatingMode" IS DISTINCT FROM 'STOPPED'::"BankConnectionOperatingMode";
    legacy_changed := NEW."ingressEnabled" OR NEW."projectionEnabled";
  ELSE
    mode_changed := NEW."operatingMode" IS DISTINCT FROM OLD."operatingMode";
    legacy_changed := NEW."ingressEnabled" IS DISTINCT FROM OLD."ingressEnabled"
      OR NEW."projectionEnabled" IS DISTINCT FROM OLD."projectionEnabled";
  END IF;

  IF mode_changed AND legacy_changed THEN
    IF NOT (
      (NEW."operatingMode" = 'STOPPED' AND NOT NEW."ingressEnabled" AND NOT NEW."projectionEnabled")
      OR (NEW."operatingMode" = 'UAT_INGEST_ONLY' AND NEW."ingressEnabled" AND NOT NEW."projectionEnabled")
      OR (NEW."operatingMode" = 'LIVE' AND NEW."ingressEnabled" AND NEW."projectionEnabled")
    ) THEN
      RAISE EXCEPTION 'Bank connection mode and legacy controls are inconsistent';
    END IF;
  ELSIF mode_changed THEN
    NEW."ingressEnabled" := NEW."operatingMode" <> 'STOPPED';
    NEW."projectionEnabled" := NEW."operatingMode" = 'LIVE';
  ELSIF legacy_changed THEN
    IF NEW."projectionEnabled" AND NOT NEW."ingressEnabled" THEN
      RAISE EXCEPTION 'Projection cannot be enabled while ingress is disabled';
    END IF;
    NEW."operatingMode" := CASE
      WHEN NEW."projectionEnabled" THEN 'LIVE'::"BankConnectionOperatingMode"
      WHEN NEW."ingressEnabled" THEN 'UAT_INGEST_ONLY'::"BankConnectionOperatingMode"
      ELSE 'STOPPED'::"BankConnectionOperatingMode"
    END;
  ELSE
    NEW."ingressEnabled" := NEW."operatingMode" <> 'STOPPED';
    NEW."projectionEnabled" := NEW."operatingMode" = 'LIVE';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "BankConnectionControl_sync_mode"
BEFORE INSERT OR UPDATE ON "BankConnectionControl"
FOR EACH ROW EXECUTE FUNCTION sync_bank_connection_operating_mode();
