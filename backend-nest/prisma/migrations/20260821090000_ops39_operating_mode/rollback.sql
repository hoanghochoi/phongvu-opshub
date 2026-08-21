DROP TRIGGER IF EXISTS "BankConnectionControl_sync_mode" ON "BankConnectionControl";
DROP FUNCTION IF EXISTS sync_bank_connection_operating_mode();
ALTER TABLE "BankConnectionControl" DROP COLUMN IF EXISTS "operatingMode";
DROP TYPE IF EXISTS "BankConnectionOperatingMode";
