-- OPS-24: remove the producer/worker lock cycle.
--
-- Producer triggers previously locked ProjectionState -> ProjectionQueue while
-- the worker finalizer locks ProjectionQueue -> ProjectionState. Acquire every
-- affected queue key in a deterministic order first, then state, then outbox.
-- The queue uniqueness, lease and dirty-generation behavior remains unchanged.

CREATE OR REPLACE FUNCTION opshub_enqueue_home_summary_projection_kinds(
    p_summary_date DATE,
    p_source TEXT,
    p_projection_kinds TEXT[]
) RETURNS VOID AS $$
DECLARE
    v_now TIMESTAMP(3) := clock_timestamp();
    v_date_key TEXT;
    v_kind TEXT;
    v_kinds TEXT[];
    v_debounce INTERVAL;
    v_max_wait INTERVAL;
BEGIN
    IF p_summary_date IS NULL THEN
        RETURN;
    END IF;

    SELECT array_agg(normalized.kind ORDER BY normalized.kind)
      INTO v_kinds
      FROM (
        SELECT DISTINCT UPPER(TRIM(kind_value)) AS kind
          FROM unnest(COALESCE(p_projection_kinds, ARRAY[]::TEXT[])) AS kind_value
         WHERE UPPER(TRIM(kind_value)) IN ('SALES', 'FINANCE')
      ) AS normalized;

    IF COALESCE(array_length(v_kinds, 1), 0) = 0 THEN
        RETURN;
    END IF;
    v_date_key := to_char(p_summary_date, 'YYYY-MM-DD');

    -- Global lock contract: all queue keys first, sorted FINANCE then SALES.
    FOREACH v_kind IN ARRAY v_kinds LOOP
        v_debounce := CASE
            WHEN v_kind = 'FINANCE' THEN INTERVAL '2 seconds'
            ELSE INTERVAL '500 milliseconds'
        END;
        v_max_wait := CASE
            WHEN v_kind = 'FINANCE' THEN INTERVAL '5 seconds'
            ELSE INTERVAL '2 seconds'
        END;

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
    END LOOP;

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
        "salesStatus" = CASE
            WHEN 'SALES' = ANY(v_kinds) THEN 'PENDING'
            ELSE "HomeSummaryProjectionState"."salesStatus"
        END,
        "financeStatus" = CASE
            WHEN 'FINANCE' = ANY(v_kinds) THEN 'PENDING'
            ELSE "HomeSummaryProjectionState"."financeStatus"
        END,
        "updatedAt" = v_now;

    FOREACH v_kind IN ARRAY v_kinds LOOP
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

        PERFORM pg_notify(
            'opshub_home_summary_projection',
            v_date_key || ':' || v_kind
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION opshub_enqueue_home_summary_projection_kind(
    p_summary_date DATE,
    p_source TEXT,
    p_projection_kind TEXT
) RETURNS VOID AS $$
BEGIN
    PERFORM opshub_enqueue_home_summary_projection_kinds(
        p_summary_date,
        p_source,
        ARRAY[p_projection_kind]
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION opshub_enqueue_home_summary_projection(
    p_summary_date DATE,
    p_source TEXT
) RETURNS VOID AS $$
DECLARE
    v_kinds TEXT[];
BEGIN
    IF p_summary_date IS NULL THEN
        RETURN;
    END IF;

    -- A new date and reconciliation require both kinds. Pass them to one
    -- primitive so no state lock is held while acquiring the second queue key.
    IF NOT EXISTS (
        SELECT 1
        FROM "HomeSummaryProjectionState"
        WHERE "summaryDate" = p_summary_date
    ) THEN
        v_kinds := ARRAY['FINANCE', 'SALES'];
    ELSIF p_source = 'MAP_VIETIN' THEN
        v_kinds := ARRAY['FINANCE'];
    ELSIF p_source = 'RECONCILIATION' THEN
        v_kinds := ARRAY['FINANCE', 'SALES'];
    ELSE
        v_kinds := ARRAY['SALES'];
    END IF;

    PERFORM opshub_enqueue_home_summary_projection_kinds(
        p_summary_date,
        p_source,
        v_kinds
    );
END;
$$ LANGUAGE plpgsql;
