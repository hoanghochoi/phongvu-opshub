DROP TRIGGER IF EXISTS "SalesReport_home_summary_projection_insert" ON "SalesReport";
DROP TRIGGER IF EXISTS "SalesReport_home_summary_projection_update" ON "SalesReport";
DROP TRIGGER IF EXISTS "SalesReport_home_summary_projection_delete" ON "SalesReport";
DROP TRIGGER IF EXISTS "SalesReportErpOrderCache_home_summary_projection_insert" ON "SalesReportErpOrderCache";
DROP TRIGGER IF EXISTS "SalesReportErpOrderCache_home_summary_projection_update" ON "SalesReportErpOrderCache";
DROP TRIGGER IF EXISTS "SalesReportErpOrderCache_home_summary_projection_delete" ON "SalesReportErpOrderCache";
DROP TRIGGER IF EXISTS "MapVietinTransaction_home_summary_projection_insert" ON "MapVietinTransaction";
DROP TRIGGER IF EXISTS "MapVietinTransaction_home_summary_projection_update" ON "MapVietinTransaction";
DROP TRIGGER IF EXISTS "MapVietinTransaction_home_summary_projection_delete" ON "MapVietinTransaction";
DROP FUNCTION IF EXISTS opshub_home_summary_statement_trigger();
DROP FUNCTION IF EXISTS opshub_enqueue_home_summary_projection_kind(DATE, TEXT, TEXT);

DELETE FROM "DomainOutboxEvent"
WHERE "eventType" = 'HOME_SUMMARY_SOURCE_CHANGED'
  AND (
    "dedupeKey" LIKE 'home-summary-source:%:SALES'
    OR "dedupeKey" LIKE 'home-summary-source:%:FINANCE'
  );

-- Restore the previous row-level trigger shape before removing new columns.
CREATE OR REPLACE FUNCTION opshub_enqueue_home_summary_projection(
    p_summary_date DATE,
    p_source TEXT
) RETURNS VOID AS $$
DECLARE
    v_now TIMESTAMP(3) := CURRENT_TIMESTAMP;
    v_date_key TEXT;
BEGIN
    IF p_summary_date IS NULL THEN RETURN; END IF;
    v_date_key := to_char(p_summary_date, 'YYYY-MM-DD');
    INSERT INTO "HomeSummaryProjectionState" (
        "summaryDate", "status", "projectionVersion", "sourceUpdatedAt",
        "salesReportSourceUpdatedAt", "erpOrderCacheSourceUpdatedAt", "mapVietinSourceUpdatedAt",
        "createdAt", "updatedAt"
    ) VALUES (
        p_summary_date, 'PENDING', 0, v_now,
        CASE WHEN p_source = 'SALES_REPORT' THEN v_now END,
        CASE WHEN p_source = 'ERP_ORDER_CACHE' THEN v_now END,
        CASE WHEN p_source = 'MAP_VIETIN' THEN v_now END,
        v_now, v_now
    ) ON CONFLICT ("summaryDate") DO UPDATE SET
        "status"='PENDING', "sourceUpdatedAt"=v_now, "updatedAt"=v_now;
    INSERT INTO "HomeSummaryProjectionQueue" (
        "id", "summaryDate", "dimensionType", "dimensionKey", "storeCode",
        "sourceUpdatedAt", "firstEnqueuedAt", "availableAt", "attempts", "createdAt", "updatedAt"
    ) VALUES (
        gen_random_uuid()::text, p_summary_date, 'GLOBAL', '', '', v_now,
        v_now, v_now + INTERVAL '500 milliseconds', 0, v_now, v_now
    ) ON CONFLICT ("summaryDate", "dimensionType", "dimensionKey", "storeCode") DO UPDATE SET
        "sourceUpdatedAt"=v_now, "availableAt"=v_now + INTERVAL '500 milliseconds',
        "claimedAt"=NULL, "attempts"=0, "lastError"=NULL, "updatedAt"=v_now;
    PERFORM pg_notify('opshub_home_summary_projection', v_date_key);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "SalesReport_home_summary_projection"
AFTER INSERT OR UPDATE OR DELETE ON "SalesReport"
FOR EACH ROW EXECUTE FUNCTION opshub_home_summary_sales_report_trigger();
CREATE TRIGGER "SalesReportErpOrderCache_home_summary_projection"
AFTER INSERT OR UPDATE OR DELETE ON "SalesReportErpOrderCache"
FOR EACH ROW EXECUTE FUNCTION opshub_home_summary_erp_cache_trigger();
CREATE TRIGGER "MapVietinTransaction_home_summary_projection"
AFTER INSERT OR UPDATE OR DELETE ON "MapVietinTransaction"
FOR EACH ROW EXECUTE FUNCTION opshub_home_summary_map_vietin_trigger();

DELETE FROM "HomeSummaryProjectionQueue" WHERE "projectionKind" = 'FINANCE';
DELETE FROM "HomeSummaryDailyAggregate" WHERE "projectionKind" = 'FINANCE';
DROP INDEX "DomainOutboxEvent_publish_lease_idx";
ALTER TABLE "DomainOutboxEvent" DROP COLUMN "leaseExpiresAt", DROP COLUMN "claimToken", DROP COLUMN "claimedAt";

DROP INDEX "HomeSummaryProjectionQueue_ready_lease_idx";
DROP INDEX "HomeSummaryProjectionQueue_availableAt_leaseExpiresAt_idx";
DROP INDEX "HomeSummaryProjectionQueue_summaryDate_projectionKind_key";
ALTER TABLE "HomeSummaryProjectionQueue"
  DROP COLUMN "claimedGeneration", DROP COLUMN "dirtyGeneration", DROP COLUMN "leaseExpiresAt",
  DROP COLUMN "claimToken", DROP COLUMN "projectionKind";
CREATE UNIQUE INDEX "HomeSummaryProjectionQueue_summaryDate_dimensionType_dimensionKey_storeCode_key"
  ON "HomeSummaryProjectionQueue"("summaryDate", "dimensionType", "dimensionKey", "storeCode");
CREATE INDEX "HomeSummaryProjectionQueue_availableAt_claimedAt_idx"
  ON "HomeSummaryProjectionQueue"("availableAt", "claimedAt");
CREATE INDEX "HomeSummaryProjectionQueue_ready_claim_idx"
  ON "HomeSummaryProjectionQueue"("availableAt", "firstEnqueuedAt") WHERE "claimedAt" IS NULL;

ALTER TABLE "HomeSummaryProjectionState"
  DROP COLUMN "financeGeneratedAt", DROP COLUMN "financeProjectionVersion", DROP COLUMN "financeStatus",
  DROP COLUMN "salesGeneratedAt", DROP COLUMN "salesProjectionVersion", DROP COLUMN "salesStatus";

DROP INDEX "HomeSummaryDailyAggregate_projectionKind_dimensionType_storeCode_summaryDate_idx";
DROP INDEX "HomeSummaryDailyAggregate_projectionKind_dimensionType_dimensionKey_summaryDate_idx";
DROP INDEX "HomeSummaryDailyAggregate_summaryDate_projectionKind_dimensionType_dimensionKey_storeCode_key";
ALTER TABLE "HomeSummaryDailyAggregate" DROP COLUMN "metrics", DROP COLUMN "projectionKind";
CREATE UNIQUE INDEX "HomeSummaryDailyAggregate_summaryDate_dimensionType_dimensionKey_storeCode_key"
  ON "HomeSummaryDailyAggregate"("summaryDate", "dimensionType", "dimensionKey", "storeCode");
CREATE INDEX "HomeSummaryDailyAggregate_dimensionType_dimensionKey_summaryDate_idx"
  ON "HomeSummaryDailyAggregate"("dimensionType", "dimensionKey", "summaryDate");
CREATE INDEX "HomeSummaryDailyAggregate_dimensionType_storeCode_summaryDate_idx"
  ON "HomeSummaryDailyAggregate"("dimensionType", "storeCode", "summaryDate");

-- Restore one durable source signal per date for the legacy worker contract.
SELECT opshub_enqueue_home_summary_projection("summaryDate", 'RECONCILIATION')
FROM "HomeSummaryProjectionState";
