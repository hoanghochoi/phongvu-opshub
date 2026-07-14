CREATE SEQUENCE "home_summary_projection_version_seq" START 1;

CREATE TABLE "HomeSummaryDailyAggregate" (
    "id" TEXT NOT NULL,
    "summaryDate" DATE NOT NULL,
    "dimensionType" TEXT NOT NULL,
    "dimensionKey" TEXT NOT NULL DEFAULT '',
    "storeCode" TEXT NOT NULL DEFAULT '',
    "totalOrders" INTEGER NOT NULL DEFAULT 0,
    "reportedOrders" INTEGER NOT NULL DEFAULT 0,
    "totalReports" INTEGER NOT NULL DEFAULT 0,
    "notPurchasedReports" INTEGER NOT NULL DEFAULT 0,
    "orderRevenueAmount" BIGINT NOT NULL DEFAULT 0,
    "reportRevenueAmount" BIGINT NOT NULL DEFAULT 0,
    "projectionVersion" BIGINT NOT NULL,
    "sourceUpdatedAt" TIMESTAMP(3),
    "generatedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "HomeSummaryDailyAggregate_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "HomeSummaryProjectionState" (
    "summaryDate" DATE NOT NULL,
    "status" TEXT NOT NULL,
    "projectionVersion" BIGINT NOT NULL DEFAULT 0,
    "sourceUpdatedAt" TIMESTAMP(3),
    "salesReportSourceUpdatedAt" TIMESTAMP(3),
    "erpOrderCacheSourceUpdatedAt" TIMESTAMP(3),
    "mapVietinSourceUpdatedAt" TIMESTAMP(3),
    "generatedAt" TIMESTAMP(3),
    "lastError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "HomeSummaryProjectionState_pkey" PRIMARY KEY ("summaryDate")
);

CREATE TABLE "HomeSummaryProjectionQueue" (
    "id" TEXT NOT NULL,
    "summaryDate" DATE NOT NULL,
    "dimensionType" TEXT NOT NULL DEFAULT 'GLOBAL',
    "dimensionKey" TEXT NOT NULL DEFAULT '',
    "storeCode" TEXT NOT NULL DEFAULT '',
    "sourceUpdatedAt" TIMESTAMP(3) NOT NULL,
    "firstEnqueuedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "availableAt" TIMESTAMP(3) NOT NULL,
    "claimedAt" TIMESTAMP(3),
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "lastError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "HomeSummaryProjectionQueue_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "DomainOutboxEvent" (
    "id" TEXT NOT NULL,
    "eventType" TEXT NOT NULL,
    "aggregateType" TEXT NOT NULL,
    "aggregateId" TEXT NOT NULL,
    "dedupeKey" TEXT,
    "schemaVersion" INTEGER NOT NULL DEFAULT 1,
    "payload" JSONB NOT NULL,
    "occurredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "availableAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "publishedAt" TIMESTAMP(3),
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "lastError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "DomainOutboxEvent_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ErpOrderCacheBackfillCheckpoint" (
    "jobKey" TEXT NOT NULL,
    "startDate" DATE NOT NULL,
    "endDate" DATE NOT NULL,
    "currentDate" DATE NOT NULL,
    "nextOffset" INTEGER NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "pagesProcessed" INTEGER NOT NULL DEFAULT 0,
    "rowsProcessed" INTEGER NOT NULL DEFAULT 0,
    "lastError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "ErpOrderCacheBackfillCheckpoint_pkey" PRIMARY KEY ("jobKey")
);

CREATE UNIQUE INDEX "HomeSummaryDailyAggregate_summaryDate_dimensionType_dimensionKey_storeCode_key"
ON "HomeSummaryDailyAggregate"("summaryDate", "dimensionType", "dimensionKey", "storeCode");
CREATE INDEX "HomeSummaryDailyAggregate_dimensionType_dimensionKey_summaryDate_idx"
ON "HomeSummaryDailyAggregate"("dimensionType", "dimensionKey", "summaryDate");
CREATE INDEX "HomeSummaryDailyAggregate_dimensionType_storeCode_summaryDate_idx"
ON "HomeSummaryDailyAggregate"("dimensionType", "storeCode", "summaryDate");
CREATE INDEX "HomeSummaryProjectionState_status_updatedAt_idx"
ON "HomeSummaryProjectionState"("status", "updatedAt");
CREATE UNIQUE INDEX "HomeSummaryProjectionQueue_summaryDate_dimensionType_dimensionKey_storeCode_key"
ON "HomeSummaryProjectionQueue"("summaryDate", "dimensionType", "dimensionKey", "storeCode");
CREATE INDEX "HomeSummaryProjectionQueue_availableAt_claimedAt_idx"
ON "HomeSummaryProjectionQueue"("availableAt", "claimedAt");
CREATE INDEX "HomeSummaryProjectionQueue_ready_claim_idx"
ON "HomeSummaryProjectionQueue"("availableAt", "firstEnqueuedAt")
WHERE "claimedAt" IS NULL;
CREATE UNIQUE INDEX "DomainOutboxEvent_dedupeKey_key" ON "DomainOutboxEvent"("dedupeKey");
CREATE INDEX "DomainOutboxEvent_publishedAt_availableAt_idx"
ON "DomainOutboxEvent"("publishedAt", "availableAt");
CREATE INDEX "DomainOutboxEvent_eventType_occurredAt_idx"
ON "DomainOutboxEvent"("eventType", "occurredAt");
CREATE INDEX "DomainOutboxEvent_home_summary_pending_idx"
ON "DomainOutboxEvent"("availableAt", "occurredAt")
WHERE "publishedAt" IS NULL AND "eventType" = 'HOME_SUMMARY_UPDATED';
CREATE INDEX "ErpOrderCacheBackfillCheckpoint_status_updatedAt_idx"
ON "ErpOrderCacheBackfillCheckpoint"("status", "updatedAt");

CREATE OR REPLACE FUNCTION opshub_enqueue_home_summary_projection(
    p_summary_date DATE,
    p_source TEXT
) RETURNS VOID AS $$
DECLARE
    v_now TIMESTAMP(3) := CURRENT_TIMESTAMP;
    v_date_key TEXT;
BEGIN
    IF p_summary_date IS NULL THEN
        RETURN;
    END IF;
    v_date_key := to_char(p_summary_date, 'YYYY-MM-DD');

    INSERT INTO "HomeSummaryProjectionState" (
        "summaryDate", "status", "projectionVersion", "sourceUpdatedAt",
        "salesReportSourceUpdatedAt", "erpOrderCacheSourceUpdatedAt",
        "mapVietinSourceUpdatedAt", "createdAt", "updatedAt"
    ) VALUES (
        p_summary_date, 'PENDING', 0, v_now,
        CASE WHEN p_source = 'SALES_REPORT' THEN v_now END,
        CASE WHEN p_source = 'ERP_ORDER_CACHE' THEN v_now END,
        CASE WHEN p_source = 'MAP_VIETIN' THEN v_now END,
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
        "updatedAt" = v_now;

    INSERT INTO "HomeSummaryProjectionQueue" (
        "id", "summaryDate", "dimensionType", "dimensionKey", "storeCode",
        "sourceUpdatedAt", "firstEnqueuedAt", "availableAt", "claimedAt",
        "attempts", "lastError", "createdAt", "updatedAt"
    ) VALUES (
        gen_random_uuid()::text, p_summary_date, 'GLOBAL', '', '', v_now,
        v_now, v_now + INTERVAL '500 milliseconds', NULL, 0, NULL, v_now, v_now
    )
    ON CONFLICT ("summaryDate", "dimensionType", "dimensionKey", "storeCode")
    DO UPDATE SET
        "sourceUpdatedAt" = EXCLUDED."sourceUpdatedAt",
        "availableAt" = LEAST(
            "HomeSummaryProjectionQueue"."firstEnqueuedAt" + INTERVAL '2 seconds',
            v_now + INTERVAL '500 milliseconds'
        ),
        "claimedAt" = NULL,
        "attempts" = 0,
        "lastError" = NULL,
        "updatedAt" = v_now;

    INSERT INTO "DomainOutboxEvent" (
        "id", "eventType", "aggregateType", "aggregateId", "dedupeKey",
        "schemaVersion", "payload", "occurredAt", "availableAt",
        "publishedAt", "attempts", "lastError", "createdAt", "updatedAt"
    ) VALUES (
        gen_random_uuid()::text, 'HOME_SUMMARY_SOURCE_CHANGED',
        'HOME_SUMMARY_DATE', v_date_key,
        'home-summary-source:' || v_date_key || ':GLOBAL', 1,
        jsonb_build_object('summaryDate', v_date_key, 'source', p_source),
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

    PERFORM pg_notify('opshub_home_summary_projection', v_date_key);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION opshub_home_summary_sales_report_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_new_date DATE;
    v_old_date DATE;
BEGIN
    IF TG_OP <> 'DELETE' THEN
        v_new_date := (COALESCE(NEW."erpOrderCreatedAt", NEW."submittedAt") + INTERVAL '7 hours')::date;
        PERFORM opshub_enqueue_home_summary_projection(v_new_date, 'SALES_REPORT');
    END IF;
    IF TG_OP <> 'INSERT' THEN
        v_old_date := (COALESCE(OLD."erpOrderCreatedAt", OLD."submittedAt") + INTERVAL '7 hours')::date;
        IF TG_OP = 'DELETE' OR v_old_date IS DISTINCT FROM v_new_date THEN
            PERFORM opshub_enqueue_home_summary_projection(v_old_date, 'SALES_REPORT');
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION opshub_home_summary_erp_cache_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_new_date DATE;
    v_old_date DATE;
BEGIN
    IF TG_OP <> 'DELETE' THEN
        v_new_date := (COALESCE(NEW."orderCreatedAt", NEW."fetchedAt") + INTERVAL '7 hours')::date;
        PERFORM opshub_enqueue_home_summary_projection(v_new_date, 'ERP_ORDER_CACHE');
    END IF;
    IF TG_OP <> 'INSERT' THEN
        v_old_date := (COALESCE(OLD."orderCreatedAt", OLD."fetchedAt") + INTERVAL '7 hours')::date;
        IF TG_OP = 'DELETE' OR v_old_date IS DISTINCT FROM v_new_date THEN
            PERFORM opshub_enqueue_home_summary_projection(v_old_date, 'ERP_ORDER_CACHE');
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION opshub_home_summary_map_vietin_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_new_date DATE;
    v_old_date DATE;
BEGIN
    IF TG_OP <> 'DELETE' THEN
        v_new_date := (COALESCE(NEW."paidAt", NEW."firstSeenAt") + INTERVAL '7 hours')::date;
        PERFORM opshub_enqueue_home_summary_projection(v_new_date, 'MAP_VIETIN');
    END IF;
    IF TG_OP <> 'INSERT' THEN
        v_old_date := (COALESCE(OLD."paidAt", OLD."firstSeenAt") + INTERVAL '7 hours')::date;
        IF TG_OP = 'DELETE' OR v_old_date IS DISTINCT FROM v_new_date THEN
            PERFORM opshub_enqueue_home_summary_projection(v_old_date, 'MAP_VIETIN');
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
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

SELECT opshub_enqueue_home_summary_projection(day::date, 'RECONCILIATION')
FROM generate_series(
    CURRENT_DATE - INTERVAL '89 days',
    CURRENT_DATE,
    INTERVAL '1 day'
) AS day;
