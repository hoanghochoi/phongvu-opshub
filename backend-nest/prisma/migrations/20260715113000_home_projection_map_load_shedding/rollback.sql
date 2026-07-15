-- Khôi phục debounce chung 500 ms/tối đa 2 giây và trigger MAP trước tối ưu.
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
