-- Restore the Phase 1 closure enqueue functions.

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

DROP FUNCTION IF EXISTS opshub_enqueue_home_summary_projection_kinds(DATE, TEXT, TEXT[]);
