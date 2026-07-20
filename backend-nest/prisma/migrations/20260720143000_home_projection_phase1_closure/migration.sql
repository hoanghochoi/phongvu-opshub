-- Phase 1 closure: independent SALES/FINANCE snapshots, generation-safe queue claims,
-- and leased outbox publication. Existing rows are retained as SALES snapshots so the
-- migration is additive from the reader's point of view.

ALTER TABLE "HomeSummaryDailyAggregate"
  ADD COLUMN "projectionKind" TEXT NOT NULL DEFAULT 'SALES',
  ADD COLUMN "metrics" JSONB NOT NULL DEFAULT '{}'::jsonb;

DROP INDEX "HomeSummaryDailyAggregate_summaryDate_dimensionType_dimensionKey_storeCode_key";
DROP INDEX "HomeSummaryDailyAggregate_dimensionType_dimensionKey_summaryDate_idx";
DROP INDEX "HomeSummaryDailyAggregate_dimensionType_storeCode_summaryDate_idx";
CREATE UNIQUE INDEX "HomeSummaryDailyAggregate_summaryDate_projectionKind_dimensionType_dimensionKey_storeCode_key"
  ON "HomeSummaryDailyAggregate"("summaryDate", "projectionKind", "dimensionType", "dimensionKey", "storeCode");
CREATE INDEX "HomeSummaryDailyAggregate_projectionKind_dimensionType_dimensionKey_summaryDate_idx"
  ON "HomeSummaryDailyAggregate"("projectionKind", "dimensionType", "dimensionKey", "summaryDate");
CREATE INDEX "HomeSummaryDailyAggregate_projectionKind_dimensionType_storeCode_summaryDate_idx"
  ON "HomeSummaryDailyAggregate"("projectionKind", "dimensionType", "storeCode", "summaryDate");

ALTER TABLE "HomeSummaryProjectionState"
  ADD COLUMN "salesStatus" TEXT NOT NULL DEFAULT 'PENDING',
  ADD COLUMN "salesProjectionVersion" BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN "salesGeneratedAt" TIMESTAMP(3),
  ADD COLUMN "financeStatus" TEXT NOT NULL DEFAULT 'PENDING',
  ADD COLUMN "financeProjectionVersion" BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN "financeGeneratedAt" TIMESTAMP(3);

UPDATE "HomeSummaryProjectionState"
SET "status" = 'PENDING',
    "salesStatus" = 'PENDING',
    "salesProjectionVersion" = 0,
    "salesGeneratedAt" = NULL,
    "financeStatus" = 'PENDING',
    "financeProjectionVersion" = 0,
    "financeGeneratedAt" = NULL;

ALTER TABLE "HomeSummaryProjectionQueue"
  ADD COLUMN "projectionKind" TEXT NOT NULL DEFAULT 'SALES',
  ADD COLUMN "claimToken" TEXT,
  ADD COLUMN "leaseExpiresAt" TIMESTAMP(3),
  ADD COLUMN "dirtyGeneration" BIGINT NOT NULL DEFAULT 1,
  ADD COLUMN "claimedGeneration" BIGINT;

ALTER TABLE "HomeSummaryProjectionQueue"
  ADD CONSTRAINT "HomeSummaryProjectionQueue_projectionKind_check"
    CHECK ("projectionKind" IN ('SALES', 'FINANCE')),
  ADD CONSTRAINT "HomeSummaryProjectionQueue_generation_check"
    CHECK ("dirtyGeneration" > 0 AND ("claimedGeneration" IS NULL OR "claimedGeneration" > 0));

ALTER TABLE "HomeSummaryDailyAggregate"
  ADD CONSTRAINT "HomeSummaryDailyAggregate_projectionKind_check"
    CHECK ("projectionKind" IN ('SALES', 'FINANCE'));

DROP INDEX "HomeSummaryProjectionQueue_summaryDate_dimensionType_dimensionKey_storeCode_key";
DROP INDEX "HomeSummaryProjectionQueue_availableAt_claimedAt_idx";
DROP INDEX "HomeSummaryProjectionQueue_ready_claim_idx";
CREATE UNIQUE INDEX "HomeSummaryProjectionQueue_summaryDate_projectionKind_key"
  ON "HomeSummaryProjectionQueue"("summaryDate", "projectionKind");
CREATE INDEX "HomeSummaryProjectionQueue_availableAt_leaseExpiresAt_idx"
  ON "HomeSummaryProjectionQueue"("availableAt", "leaseExpiresAt");
CREATE INDEX "HomeSummaryProjectionQueue_ready_lease_idx"
  ON "HomeSummaryProjectionQueue"("availableAt", "firstEnqueuedAt")
  WHERE "claimToken" IS NULL;

ALTER TABLE "DomainOutboxEvent"
  ADD COLUMN "claimedAt" TIMESTAMP(3),
  ADD COLUMN "claimToken" TEXT,
  ADD COLUMN "leaseExpiresAt" TIMESTAMP(3);
CREATE INDEX "DomainOutboxEvent_publish_lease_idx"
  ON "DomainOutboxEvent"("availableAt", "leaseExpiresAt", "occurredAt")
  WHERE "publishedAt" IS NULL AND "eventType" = 'HOME_SUMMARY_UPDATED';

CREATE OR REPLACE FUNCTION opshub_enqueue_home_summary_projection_kind(
    p_summary_date DATE,
    p_source TEXT,
    p_projection_kind TEXT
) RETURNS VOID AS $$
DECLARE
    v_now TIMESTAMP(3) := clock_timestamp();
    v_date_key TEXT;
    v_kind TEXT := UPPER(TRIM(p_projection_kind));
    v_debounce INTERVAL := CASE
        WHEN v_kind = 'FINANCE' THEN INTERVAL '2 seconds'
        ELSE INTERVAL '500 milliseconds'
    END;
    v_max_wait INTERVAL := CASE
        WHEN v_kind = 'FINANCE' THEN INTERVAL '5 seconds'
        ELSE INTERVAL '2 seconds'
    END;
BEGIN
    IF p_summary_date IS NULL OR v_kind NOT IN ('SALES', 'FINANCE') THEN
        RETURN;
    END IF;
    v_date_key := to_char(p_summary_date, 'YYYY-MM-DD');

    INSERT INTO "HomeSummaryProjectionState" (
        "summaryDate", "status", "projectionVersion", "sourceUpdatedAt",
        "salesReportSourceUpdatedAt", "erpOrderCacheSourceUpdatedAt",
        "mapVietinSourceUpdatedAt", "salesStatus", "financeStatus",
        "createdAt", "updatedAt"
    ) VALUES (
        p_summary_date, 'PENDING', 0, v_now,
        CASE WHEN p_source = 'SALES_REPORT' THEN v_now END,
        CASE WHEN p_source = 'ERP_ORDER_CACHE' THEN v_now END,
        CASE WHEN p_source = 'MAP_VIETIN' THEN v_now END,
        'PENDING', 'PENDING',
        v_now, v_now
    )
    ON CONFLICT ("summaryDate") DO UPDATE SET
        "status" = 'PENDING',
        "sourceUpdatedAt" = GREATEST(
            COALESCE("HomeSummaryProjectionState"."sourceUpdatedAt", EXCLUDED."sourceUpdatedAt"),
            EXCLUDED."sourceUpdatedAt"
        ),
        "salesReportSourceUpdatedAt" = COALESCE(
            EXCLUDED."salesReportSourceUpdatedAt",
            "HomeSummaryProjectionState"."salesReportSourceUpdatedAt"
        ),
        "erpOrderCacheSourceUpdatedAt" = COALESCE(
            EXCLUDED."erpOrderCacheSourceUpdatedAt",
            "HomeSummaryProjectionState"."erpOrderCacheSourceUpdatedAt"
        ),
        "mapVietinSourceUpdatedAt" = COALESCE(
            EXCLUDED."mapVietinSourceUpdatedAt",
            "HomeSummaryProjectionState"."mapVietinSourceUpdatedAt"
        ),
        "salesStatus" = CASE WHEN v_kind = 'SALES' THEN 'PENDING' ELSE "HomeSummaryProjectionState"."salesStatus" END,
        "financeStatus" = CASE WHEN v_kind = 'FINANCE' THEN 'PENDING' ELSE "HomeSummaryProjectionState"."financeStatus" END,
        "updatedAt" = v_now;

    INSERT INTO "HomeSummaryProjectionQueue" (
        "id", "summaryDate", "projectionKind", "dimensionType", "dimensionKey", "storeCode",
        "sourceUpdatedAt", "firstEnqueuedAt", "availableAt", "claimedAt",
        "claimToken", "leaseExpiresAt", "dirtyGeneration", "claimedGeneration",
        "attempts", "lastError", "createdAt", "updatedAt"
    ) VALUES (
        gen_random_uuid()::text, p_summary_date, v_kind, 'GLOBAL', '', '', v_now,
        v_now, v_now + v_debounce, NULL, NULL, NULL, 1, NULL,
        0, NULL, v_now, v_now
    )
    ON CONFLICT ("summaryDate", "projectionKind") DO UPDATE SET
        "sourceUpdatedAt" = GREATEST("HomeSummaryProjectionQueue"."sourceUpdatedAt", EXCLUDED."sourceUpdatedAt"),
        "dirtyGeneration" = "HomeSummaryProjectionQueue"."dirtyGeneration" + 1,
        "availableAt" = LEAST(
            "HomeSummaryProjectionQueue"."firstEnqueuedAt" + v_max_wait,
            v_now + v_debounce
        ),
        "attempts" = CASE WHEN "HomeSummaryProjectionQueue"."claimToken" IS NULL THEN 0 ELSE "HomeSummaryProjectionQueue"."attempts" END,
        "lastError" = NULL,
        "updatedAt" = v_now;

    INSERT INTO "DomainOutboxEvent" (
        "id", "eventType", "aggregateType", "aggregateId", "dedupeKey",
        "schemaVersion", "payload", "occurredAt", "availableAt",
        "publishedAt", "attempts", "lastError", "createdAt", "updatedAt"
    ) VALUES (
        gen_random_uuid()::text, 'HOME_SUMMARY_SOURCE_CHANGED',
        'HOME_SUMMARY_DATE', v_date_key,
        'home-summary-source:' || v_date_key || ':' || v_kind, 1,
        jsonb_build_object('summaryDate', v_date_key, 'source', p_source, 'projectionKind', v_kind),
        v_now, v_now, NULL, 0, NULL, v_now, v_now
    )
    ON CONFLICT ("dedupeKey") DO UPDATE SET
        "payload" = EXCLUDED."payload",
        "occurredAt" = EXCLUDED."occurredAt",
        "availableAt" = EXCLUDED."availableAt",
        "publishedAt" = NULL,
        "attempts" = 0,
        "lastError" = NULL,
        "updatedAt" = v_now;

    PERFORM pg_notify('opshub_home_summary_projection', v_date_key || ':' || v_kind);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION opshub_enqueue_home_summary_projection(
    p_summary_date DATE,
    p_source TEXT
) RETURNS VOID AS $$
BEGIN
    -- A brand-new calendar date has no last-complete snapshot for either kind.
    -- Build both immediately so the first SALES or MAP commit cannot leave
    -- users with a 503 until the minute reconciliation catches up.
    IF NOT EXISTS (
        SELECT 1
        FROM "HomeSummaryProjectionState"
        WHERE "summaryDate" = p_summary_date
    ) THEN
        PERFORM opshub_enqueue_home_summary_projection_kind(p_summary_date, p_source, 'SALES');
        PERFORM opshub_enqueue_home_summary_projection_kind(p_summary_date, p_source, 'FINANCE');
    ELSIF p_source = 'MAP_VIETIN' THEN
        PERFORM opshub_enqueue_home_summary_projection_kind(p_summary_date, p_source, 'FINANCE');
    ELSIF p_source = 'RECONCILIATION' THEN
        PERFORM opshub_enqueue_home_summary_projection_kind(p_summary_date, p_source, 'SALES');
        PERFORM opshub_enqueue_home_summary_projection_kind(p_summary_date, p_source, 'FINANCE');
    ELSE
        PERFORM opshub_enqueue_home_summary_projection_kind(p_summary_date, p_source, 'SALES');
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Transition-table triggers coalesce a bulk INSERT/UPDATE/DELETE into one enqueue per
-- affected day instead of repeatedly updating the same queue/outbox rows per source row.
CREATE OR REPLACE FUNCTION opshub_home_summary_statement_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_source TEXT := TG_ARGV[0];
    v_new_expr TEXT;
    v_old_expr TEXT;
    v_sql TEXT;
    v_date DATE;
BEGIN
    v_new_expr := CASE v_source
        WHEN 'SALES_REPORT' THEN 'COALESCE("erpOrderCreatedAt", "submittedAt")'
        WHEN 'ERP_ORDER_CACHE' THEN 'COALESCE("orderCreatedAt", "fetchedAt")'
        ELSE 'COALESCE("paidAt", "firstSeenAt")'
    END;
    v_old_expr := v_new_expr;

    IF TG_OP = 'INSERT' THEN
        v_sql := format('SELECT DISTINCT ((%s) + INTERVAL ''7 hours'')::date FROM new_rows', v_new_expr);
    ELSIF TG_OP = 'DELETE' THEN
        v_sql := format('SELECT DISTINCT ((%s) + INTERVAL ''7 hours'')::date FROM old_rows', v_old_expr);
    ELSE
        v_sql := format(
            'SELECT DISTINCT affected_date FROM (' ||
            ' SELECT ((%1$s) + INTERVAL ''7 hours'')::date AS affected_date FROM new_rows' ||
            ' UNION SELECT ((%1$s) + INTERVAL ''7 hours'')::date AS affected_date FROM old_rows' ||
            ') changed', v_new_expr
        );
    END IF;

    FOR v_date IN EXECUTE v_sql LOOP
        PERFORM opshub_enqueue_home_summary_projection(v_date, v_source);
    END LOOP;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "SalesReport_home_summary_projection" ON "SalesReport";
DROP TRIGGER IF EXISTS "SalesReportErpOrderCache_home_summary_projection" ON "SalesReportErpOrderCache";
DROP TRIGGER IF EXISTS "MapVietinTransaction_home_summary_projection" ON "MapVietinTransaction";

CREATE TRIGGER "SalesReport_home_summary_projection_insert"
AFTER INSERT ON "SalesReport" REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION opshub_home_summary_statement_trigger('SALES_REPORT');
CREATE TRIGGER "SalesReport_home_summary_projection_update"
AFTER UPDATE ON "SalesReport" REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION opshub_home_summary_statement_trigger('SALES_REPORT');
CREATE TRIGGER "SalesReport_home_summary_projection_delete"
AFTER DELETE ON "SalesReport" REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION opshub_home_summary_statement_trigger('SALES_REPORT');

CREATE TRIGGER "SalesReportErpOrderCache_home_summary_projection_insert"
AFTER INSERT ON "SalesReportErpOrderCache" REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION opshub_home_summary_statement_trigger('ERP_ORDER_CACHE');
CREATE TRIGGER "SalesReportErpOrderCache_home_summary_projection_update"
AFTER UPDATE ON "SalesReportErpOrderCache" REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION opshub_home_summary_statement_trigger('ERP_ORDER_CACHE');
CREATE TRIGGER "SalesReportErpOrderCache_home_summary_projection_delete"
AFTER DELETE ON "SalesReportErpOrderCache" REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION opshub_home_summary_statement_trigger('ERP_ORDER_CACHE');

CREATE TRIGGER "MapVietinTransaction_home_summary_projection_insert"
AFTER INSERT ON "MapVietinTransaction" REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION opshub_home_summary_statement_trigger('MAP_VIETIN');
CREATE TRIGGER "MapVietinTransaction_home_summary_projection_update"
AFTER UPDATE ON "MapVietinTransaction" REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION opshub_home_summary_statement_trigger('MAP_VIETIN');
CREATE TRIGGER "MapVietinTransaction_home_summary_projection_delete"
AFTER DELETE ON "MapVietinTransaction" REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION opshub_home_summary_statement_trigger('MAP_VIETIN');

-- Both kinds are rebuilt before the projection reader is enabled. Existing SALES
-- rows remain physically present as the rollback-safe last complete snapshot.
DELETE FROM "DomainOutboxEvent"
WHERE "eventType" = 'HOME_SUMMARY_SOURCE_CHANGED'
  AND "dedupeKey" LIKE 'home-summary-source:%:GLOBAL';

SELECT opshub_enqueue_home_summary_projection("summaryDate", 'RECONCILIATION')
FROM "HomeSummaryProjectionState";
