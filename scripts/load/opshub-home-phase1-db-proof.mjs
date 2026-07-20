import { createRequire } from "node:module";
import process from "node:process";
import { performance } from "node:perf_hooks";

const requireFromBackend = createRequire(
  new URL("../../backend-nest/package.json", import.meta.url),
);
const { Client } = requireFromBackend("pg");

const REQUIRED_TABLES = [
  "HomeSummaryDailyAggregate",
  "HomeSummaryOrderFact",
  "HomeSummaryReportFact",
  "HomeSummaryProjectionQueue",
  "HomeSummaryProjectionState",
  "DomainOutboxEvent",
  "MapVietinTransaction",
];
const METRIC_NAMES = [
  "totalOrders",
  "reportedOrders",
  "totalReports",
  "notPurchasedReports",
  "orderRevenueAmount",
  "reportRevenueAmount",
];
const BURST_ROWS = 5_000;
const BURST_APPROVAL = "OPSHUB_LOCAL_DISPOSABLE_HOME_BURST_APPROVED";

if (process.argv.includes("--help")) {
  process.stdout.write(
    [
      "Read-only parity/lag report:",
      "  DATABASE_URL=<url> node scripts/load/opshub-home-phase1-db-proof.mjs",
      "",
      "Optional local disposable 5,000-row burst:",
      `  BURST_MUTATION_ENABLED=1 BURST_APPROVAL=${BURST_APPROVAL}`,
      "  OPSHUB_DISPOSABLE_DB=1 BURST_RUN_ID=<lowercase-run-id>",
      "  BURST_DATE=<future-date> DATABASE_URL=<loopback disposable db url>",
      "",
      "The burst requires a projection worker already connected to the same DB.",
    ].join("\n") + "\n",
  );
  process.exit(0);
}

const databaseUrl = String(process.env.DATABASE_URL || "").trim();
if (!databaseUrl) throw new Error("DATABASE_URL is required");

const statementTimeoutMs = boundedInteger(
  process.env.PROOF_STATEMENT_TIMEOUT_MS,
  30_000,
  1_000,
  120_000,
  "PROOF_STATEMENT_TIMEOUT_MS",
);
const scopeSamples = boundedInteger(
  process.env.PARITY_SCOPE_SAMPLES,
  3,
  1,
  20,
  "PARITY_SCOPE_SAMPLES",
);
const client = new Client({
  connectionString: databaseUrl,
  application_name: "opshub-home-phase1-proof",
  statement_timeout: statementTimeoutMs,
});

let report;
try {
  await client.connect();
  await assertRequiredTables(client);
  const parity = await collectReadOnlyProof(client, scopeSamples);
  const burst =
    process.env.BURST_MUTATION_ENABLED === "1"
      ? await runDisposableBurst(client, databaseUrl)
      : { enabled: false };
  report = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    mode: burst.enabled ? "read-only-plus-disposable-burst" : "read-only",
    parity,
    burst,
  };
} finally {
  await client.end().catch(() => undefined);
}

process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
const strict = String(process.env.PARITY_STRICT ?? "1") !== "0";
if (
  strict &&
  (report.parity.incompleteRangeCount > 0 ||
    report.parity.mismatchCount > 0 ||
    (report.burst.enabled && !report.burst.passed))
) {
  process.exitCode = 2;
}

async function assertRequiredTables(db) {
  const result = await db.query(
    `SELECT name, to_regclass('public.' || quote_ident(name)) IS NOT NULL AS present
       FROM unnest($1::text[]) AS names(name)`,
    [REQUIRED_TABLES],
  );
  const missing = result.rows
    .filter((row) => !row.present)
    .map((row) => row.name);
  if (missing.length > 0) {
    throw new Error(
      `Required Home proof tables are missing: ${missing.join(", ")}`,
    );
  }
}

async function collectReadOnlyProof(db, sampleLimit) {
  await db.query("BEGIN READ ONLY");
  try {
    const endDate = await resolveEndDate(db);
    const ranges = [];
    let mismatchCount = 0;
    let incompleteRangeCount = 0;
    for (const days of [1, 7, 30, 90]) {
      const startDate = addUtcDays(endDate, -(days - 1));
      const completeness = await db.query(
        `SELECT COUNT(*)::int AS complete_days
          FROM "HomeSummaryProjectionState"
          WHERE "summaryDate" BETWEEN $1::date AND $2::date
            AND "salesStatus" = 'COMPLETE'
            AND "financeStatus" = 'COMPLETE'
            AND "salesGeneratedAt" IS NOT NULL
            AND "financeGeneratedAt" IS NOT NULL`,
        [startDate, endDate],
      );
      const completeDays = Number(completeness.rows[0]?.complete_days || 0);
      if (completeDays !== days) incompleteRangeCount += 1;

      const scopes = [{ type: "GLOBAL", key: "", storeCode: "" }];
      scopes.push(
        ...(await selectScopeSamples(
          db,
          "STORE",
          startDate,
          endDate,
          sampleLimit,
        )),
      );
      scopes.push(
        ...(await selectScopeSamples(
          db,
          "USER_STORE",
          startDate,
          endDate,
          sampleLimit,
        )),
      );

      const results = [];
      for (let index = 0; index < scopes.length; index += 1) {
        const scope = scopes[index];
        const comparison = await compareScope(db, startDate, endDate, scope);
        const mismatches = METRIC_NAMES.filter(
          (name) => comparison.projection[name] !== comparison.facts[name],
        );
        mismatchCount += mismatches.length;
        results.push({
          scope: scope.type === "GLOBAL" ? "GLOBAL" : `${scope.type}_SAMPLE`,
          sampleIndex:
            scope.type === "GLOBAL"
              ? 0
              : results.filter((item) => item.scope === `${scope.type}_SAMPLE`)
                  .length + 1,
          passed: mismatches.length === 0,
          mismatches,
        });
      }
      ranges.push({
        days,
        startDate,
        endDate,
        completeDays,
        expectedDays: days,
        passed: completeDays === days && results.every((item) => item.passed),
        scopes: results,
      });
    }

    const runtime = await collectProjectionRuntime(db, endDate);
    await db.query("ROLLBACK");
    return {
      endDate,
      rangeCount: ranges.length,
      incompleteRangeCount,
      mismatchCount,
      ranges,
      runtime,
    };
  } catch (error) {
    await db.query("ROLLBACK").catch(() => undefined);
    throw error;
  }
}

async function resolveEndDate(db) {
  const requested = String(process.env.PROOF_END_DATE || "").trim();
  if (requested) {
    assertDate(requested, "PROOF_END_DATE");
    return requested;
  }
  const result = await db.query(
    `SELECT to_char(MAX(state."summaryDate"), 'YYYY-MM-DD') AS end_date
      FROM "HomeSummaryProjectionState" AS state
      WHERE state."salesStatus" = 'COMPLETE'
        AND state."financeStatus" = 'COMPLETE'
        AND EXISTS (
          SELECT 1
          FROM "HomeSummaryDailyAggregate" AS aggregate
          WHERE aggregate."summaryDate" = state."summaryDate"
            AND aggregate."projectionKind" = 'SALES'
            AND aggregate."dimensionType" = 'GLOBAL'
            AND aggregate."dimensionKey" = ''
            AND aggregate."storeCode" = ''
        )`,
  );
  const endDate = result.rows[0]?.end_date;
  if (!endDate) {
    throw new Error(
      "No COMPLETE Home projection date is available for parity proof",
    );
  }
  return endDate;
}

async function selectScopeSamples(db, type, startDate, endDate, limit) {
  const result = await db.query(
    `SELECT "dimensionKey" AS key, "storeCode",
            SUM("totalOrders" + "totalReports") AS activity
       FROM "HomeSummaryDailyAggregate"
      WHERE "projectionKind" = 'SALES'
        AND "dimensionType" = $1
        AND "summaryDate" BETWEEN $2::date AND $3::date
      GROUP BY "dimensionKey", "storeCode"
      ORDER BY activity DESC, "dimensionKey", "storeCode"
      LIMIT $4`,
    [type, startDate, endDate, limit],
  );
  return result.rows.map((row) => ({
    type,
    key: String(row.key || ""),
    storeCode: String(row.storeCode || ""),
  }));
}

async function compareScope(db, startDate, endDate, scope) {
  const result = await db.query(
    `SELECT
       (SELECT COALESCE(SUM("totalOrders"), 0)::text
          FROM "HomeSummaryDailyAggregate"
         WHERE "summaryDate" BETWEEN $1::date AND $2::date
           AND "projectionKind" = 'SALES'
           AND "dimensionType" = $3
           AND ($3 = 'GLOBAL' OR "storeCode" = $4)
           AND ($3 <> 'USER_STORE' OR "dimensionKey" = $5)) AS aggregate_total_orders,
       (SELECT COUNT(*)::text
          FROM "HomeSummaryOrderFact"
         WHERE ("summaryDate" + INTERVAL '7 hours')::date BETWEEN $1::date AND $2::date
           AND NOT "isPaymentPending"
           AND ($3 = 'GLOBAL' OR UPPER(TRIM(COALESCE("storeCode", ''))) = $4)
           AND ($3 <> 'USER_STORE' OR LOWER($5) = ANY(ARRAY[
             LOWER(TRIM(COALESCE("sourceUserEmail", ''))),
             LOWER(TRIM(COALESCE("consultantEmail", ''))),
             LOWER(TRIM(COALESCE("sellerEmail", ''))),
             LOWER(TRIM(COALESCE("reportCreatedByEmail", '')))
           ]))) AS fact_total_orders,
       (SELECT COALESCE(SUM("reportedOrders"), 0)::text
          FROM "HomeSummaryDailyAggregate"
         WHERE "summaryDate" BETWEEN $1::date AND $2::date
           AND "projectionKind" = 'SALES'
           AND "dimensionType" = $3
           AND ($3 = 'GLOBAL' OR "storeCode" = $4)
           AND ($3 <> 'USER_STORE' OR "dimensionKey" = $5)) AS aggregate_reported_orders,
       (SELECT COUNT(*) FILTER (WHERE "hasValidReport")::text
          FROM "HomeSummaryOrderFact"
         WHERE ("summaryDate" + INTERVAL '7 hours')::date BETWEEN $1::date AND $2::date
           AND NOT "isPaymentPending"
           AND ($3 = 'GLOBAL' OR UPPER(TRIM(COALESCE("storeCode", ''))) = $4)
           AND ($3 <> 'USER_STORE' OR LOWER($5) = ANY(ARRAY[
             LOWER(TRIM(COALESCE("sourceUserEmail", ''))),
             LOWER(TRIM(COALESCE("consultantEmail", ''))),
             LOWER(TRIM(COALESCE("sellerEmail", ''))),
             LOWER(TRIM(COALESCE("reportCreatedByEmail", '')))
           ]))) AS fact_reported_orders,
       (SELECT COALESCE(SUM("totalReports"), 0)::text
          FROM "HomeSummaryDailyAggregate"
         WHERE "summaryDate" BETWEEN $1::date AND $2::date
           AND "projectionKind" = 'SALES'
           AND "dimensionType" = $3
           AND ($3 = 'GLOBAL' OR "storeCode" = $4)
           AND ($3 <> 'USER_STORE' OR "dimensionKey" = $5)) AS aggregate_total_reports,
       (SELECT COUNT(*)::text
          FROM "HomeSummaryReportFact"
         WHERE ("summaryDate" + INTERVAL '7 hours')::date BETWEEN $1::date AND $2::date
           AND ($3 = 'GLOBAL' OR UPPER(TRIM(COALESCE("storeCode", ''))) = $4)
           AND ($3 <> 'USER_STORE' OR
             LOWER(TRIM(COALESCE("createdByEmail", ''))) = LOWER($5))) AS fact_total_reports,
       (SELECT COALESCE(SUM("notPurchasedReports"), 0)::text
          FROM "HomeSummaryDailyAggregate"
         WHERE "summaryDate" BETWEEN $1::date AND $2::date
           AND "projectionKind" = 'SALES'
           AND "dimensionType" = $3
           AND ($3 = 'GLOBAL' OR "storeCode" = $4)
           AND ($3 <> 'USER_STORE' OR "dimensionKey" = $5)) AS aggregate_not_purchased_reports,
       (SELECT COUNT(*) FILTER (WHERE "reportType" = 'NOT_PURCHASED')::text
          FROM "HomeSummaryReportFact"
         WHERE ("summaryDate" + INTERVAL '7 hours')::date BETWEEN $1::date AND $2::date
           AND ($3 = 'GLOBAL' OR UPPER(TRIM(COALESCE("storeCode", ''))) = $4)
           AND ($3 <> 'USER_STORE' OR
             LOWER(TRIM(COALESCE("createdByEmail", ''))) = LOWER($5))) AS fact_not_purchased_reports,
       (SELECT COALESCE(SUM("orderRevenueAmount"), 0)::text
          FROM "HomeSummaryDailyAggregate"
         WHERE "summaryDate" BETWEEN $1::date AND $2::date
           AND "projectionKind" = 'SALES'
           AND "dimensionType" = $3
           AND ($3 = 'GLOBAL' OR "storeCode" = $4)
           AND ($3 <> 'USER_STORE' OR "dimensionKey" = $5)) AS aggregate_order_revenue,
       (SELECT COALESCE(SUM(GREATEST(COALESCE("grandTotal", 0), 0)), 0)::text
          FROM "HomeSummaryOrderFact"
         WHERE ("summaryDate" + INTERVAL '7 hours')::date BETWEEN $1::date AND $2::date
           AND NOT "isPaymentPending"
           AND ($3 = 'GLOBAL' OR UPPER(TRIM(COALESCE("storeCode", ''))) = $4)
           AND ($3 <> 'USER_STORE' OR LOWER($5) = ANY(ARRAY[
             LOWER(TRIM(COALESCE("sourceUserEmail", ''))),
             LOWER(TRIM(COALESCE("consultantEmail", ''))),
             LOWER(TRIM(COALESCE("sellerEmail", ''))),
             LOWER(TRIM(COALESCE("reportCreatedByEmail", '')))
           ]))) AS fact_order_revenue,
       (SELECT COALESCE(SUM("reportRevenueAmount"), 0)::text
          FROM "HomeSummaryDailyAggregate"
         WHERE "summaryDate" BETWEEN $1::date AND $2::date
           AND "projectionKind" = 'SALES'
           AND "dimensionType" = $3
           AND ($3 = 'GLOBAL' OR "storeCode" = $4)
           AND ($3 <> 'USER_STORE' OR "dimensionKey" = $5)) AS aggregate_report_revenue,
       (SELECT COALESCE(SUM(GREATEST(COALESCE("revenue", 0), 0)), 0)::text
          FROM "HomeSummaryReportFact"
         WHERE ("summaryDate" + INTERVAL '7 hours')::date BETWEEN $1::date AND $2::date
           AND ($3 = 'GLOBAL' OR UPPER(TRIM(COALESCE("storeCode", ''))) = $4)
           AND ($3 <> 'USER_STORE' OR
             LOWER(TRIM(COALESCE("createdByEmail", ''))) = LOWER($5))) AS fact_report_revenue`,
    [startDate, endDate, scope.type, scope.storeCode, scope.key],
  );
  const row = result.rows[0];
  return {
    projection: {
      totalOrders: row.aggregate_total_orders,
      reportedOrders: row.aggregate_reported_orders,
      totalReports: row.aggregate_total_reports,
      notPurchasedReports: row.aggregate_not_purchased_reports,
      orderRevenueAmount: row.aggregate_order_revenue,
      reportRevenueAmount: row.aggregate_report_revenue,
    },
    facts: {
      totalOrders: row.fact_total_orders,
      reportedOrders: row.fact_reported_orders,
      totalReports: row.fact_total_reports,
      notPurchasedReports: row.fact_not_purchased_reports,
      orderRevenueAmount: row.fact_order_revenue,
      reportRevenueAmount: row.fact_report_revenue,
    },
  };
}

async function collectProjectionRuntime(db, endDate) {
  const statusResult = await db.query(
    `SELECT
       COUNT(*) FILTER (WHERE "salesStatus" = 'COMPLETE')::int AS sales_complete_dates,
       COUNT(*) FILTER (WHERE "salesStatus" = 'PENDING')::int AS sales_pending_dates,
       COUNT(*) FILTER (WHERE "salesStatus" = 'ERROR')::int AS sales_error_dates,
       COUNT(*) FILTER (WHERE "financeStatus" = 'COMPLETE')::int AS finance_complete_dates,
       COUNT(*) FILTER (WHERE "financeStatus" = 'PENDING')::int AS finance_pending_dates,
       COUNT(*) FILTER (WHERE "financeStatus" = 'ERROR')::int AS finance_error_dates
      FROM "HomeSummaryProjectionState"
      WHERE "summaryDate" BETWEEN ($1::date - INTERVAL '89 days') AND $1::date`,
    [endDate],
  );
  const lagResult = await db.query(
    `WITH lags AS (
       SELECT 'SALES'::text AS kind,
         EXTRACT(EPOCH FROM (
           "salesGeneratedAt" - GREATEST(
             COALESCE("salesReportSourceUpdatedAt", '-infinity'::timestamp),
             COALESCE("erpOrderCacheSourceUpdatedAt", '-infinity'::timestamp)
           )
         )) * 1000 AS lag_ms
       FROM "HomeSummaryProjectionState"
       WHERE "summaryDate" BETWEEN ($1::date - INTERVAL '89 days') AND $1::date
         AND "salesStatus" = 'COMPLETE'
         AND "salesGeneratedAt" IS NOT NULL
         AND ("salesReportSourceUpdatedAt" IS NOT NULL OR "erpOrderCacheSourceUpdatedAt" IS NOT NULL)
       UNION ALL
       SELECT 'FINANCE'::text,
         EXTRACT(EPOCH FROM ("financeGeneratedAt" - "mapVietinSourceUpdatedAt")) * 1000
       FROM "HomeSummaryProjectionState"
       WHERE "summaryDate" BETWEEN ($1::date - INTERVAL '89 days') AND $1::date
         AND "financeStatus" = 'COMPLETE'
         AND "financeGeneratedAt" IS NOT NULL
         AND "mapVietinSourceUpdatedAt" IS NOT NULL
     )
     SELECT kind,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (
         ORDER BY lag_ms
       ))::bigint AS lag_p50_ms,
       ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (
         ORDER BY lag_ms
       ))::bigint AS lag_p95_ms,
       ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (
         ORDER BY lag_ms
       ))::bigint AS lag_p99_ms
     FROM lags
     GROUP BY kind
     ORDER BY kind`,
    [endDate],
  );
  const queues = await db.query(
    `SELECT COUNT(*)::int AS queue_depth,
            COALESCE(MAX(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - "firstEnqueuedAt"))), 0)::int AS oldest_queue_seconds
       FROM "HomeSummaryProjectionQueue"`,
  );
  const outbox = await db.query(
    `SELECT COUNT(*)::int AS pending_events,
            COALESCE(MAX(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - "occurredAt"))), 0)::int AS oldest_event_seconds
       FROM "DomainOutboxEvent"
      WHERE "eventType" = 'HOME_SUMMARY_UPDATED'
        AND "publishedAt" IS NULL`,
  );
  const state = statusResult.rows[0];
  const lagByKind = Object.fromEntries(
    lagResult.rows.map((row) => [
      row.kind,
      {
        p50: nullableNumber(row.lag_p50_ms),
        p95: nullableNumber(row.lag_p95_ms),
        p99: nullableNumber(row.lag_p99_ms),
      },
    ]),
  );
  return {
    statusByKind: {
      SALES: {
        completeDates: Number(state.sales_complete_dates || 0),
        pendingDates: Number(state.sales_pending_dates || 0),
        errorDates: Number(state.sales_error_dates || 0),
      },
      FINANCE: {
        completeDates: Number(state.finance_complete_dates || 0),
        pendingDates: Number(state.finance_pending_dates || 0),
        errorDates: Number(state.finance_error_dates || 0),
      },
    },
    projectionLagMsByKind: lagByKind,
    queueDepth: Number(queues.rows[0]?.queue_depth || 0),
    oldestQueueSeconds: Number(queues.rows[0]?.oldest_queue_seconds || 0),
    pendingUpdatedEvents: Number(outbox.rows[0]?.pending_events || 0),
    oldestUpdatedEventSeconds: Number(
      outbox.rows[0]?.oldest_event_seconds || 0,
    ),
  };
}

async function runDisposableBurst(db, urlText) {
  assertDisposableBurstGuard(urlText);
  const runId = String(process.env.BURST_RUN_ID || "");
  if (!/^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])?$/.test(runId)) {
    throw new Error("BURST_RUN_ID is invalid");
  }
  const burstDate = String(process.env.BURST_DATE || "");
  assertDate(burstDate, "BURST_DATE");
  const today = new Date();
  const burstTime = new Date(`${burstDate}T00:00:00.000Z`);
  const minFuture = new Date(today.getTime() + 365 * 24 * 60 * 60 * 1000);
  const maxFuture = new Date(today.getTime() + 3650 * 24 * 60 * 60 * 1000);
  if (burstTime < minFuture || burstTime > maxFuture) {
    throw new Error("BURST_DATE must be 1-10 years in the future");
  }
  const timeoutMs = boundedInteger(
    process.env.BURST_WAIT_TIMEOUT_MS,
    30_000,
    5_000,
    120_000,
    "BURST_WAIT_TIMEOUT_MS",
  );
  const lagLimitMs = boundedInteger(
    process.env.BURST_PROJECTION_LAG_LIMIT_MS,
    15_000,
    1_000,
    120_000,
    "BURST_PROJECTION_LAG_LIMIT_MS",
  );
  const prefix = `phase1-burst:${runId}:`;
  let evidence;
  let primaryError;
  let cleanupAuthorized = false;
  try {
    const preflight = await db.query(
      `SELECT
         (SELECT COUNT(*)::int FROM "MapVietinTransaction"
           WHERE (COALESCE("paidAt", "firstSeenAt") + INTERVAL '7 hours')::date = $1::date) AS source_rows,
         (SELECT COUNT(*)::int FROM "HomeSummaryProjectionState"
           WHERE "summaryDate" = $1::date) AS state_rows,
         (SELECT COUNT(*)::int FROM "HomeSummaryProjectionQueue"
           WHERE "summaryDate" = $1::date) AS queue_rows,
         (SELECT COUNT(*)::int FROM "HomeSummaryDailyAggregate"
           WHERE "summaryDate" = $1::date) AS aggregate_rows,
         (SELECT COUNT(*)::int FROM "HomeSummaryOrderFact"
           WHERE ("summaryDate" + INTERVAL '7 hours')::date = $1::date) AS order_fact_rows,
         (SELECT COUNT(*)::int FROM "HomeSummaryReportFact"
           WHERE ("summaryDate" + INTERVAL '7 hours')::date = $1::date) AS report_fact_rows`,
      [burstDate],
    );
    if (Object.values(preflight.rows[0]).some((value) => Number(value) !== 0)) {
      throw new Error("BURST_DATE is not empty in the disposable database");
    }
    cleanupAuthorized = true;

    const writeStarted = performance.now();
    await db.query("BEGIN");
    await db.query(
      `INSERT INTO "MapVietinTransaction" (
         "id", "storeCode", "transactionKey", "amount", "content", "orders",
         "rawData", "paidAt", "firstSeenAt", "createdAt", "updatedAt"
       )
       SELECT gen_random_uuid()::text, 'PHASE1', $1 || value::text,
              1000 + value, 'synthetic phase 1 projection proof', ARRAY[]::text[],
              '{}'::jsonb, $2::date + TIME '00:00:00',
              $2::date + TIME '00:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
         FROM generate_series(1, $3::int) AS series(value)`,
      [prefix, burstDate, BURST_ROWS],
    );
    await db.query("COMMIT");
    const sourceWriteDurationMs = Math.round(performance.now() - writeStarted);
    const committed = await db.query(
      "SELECT clock_timestamp() AS committed_at",
    );
    const committedAt = new Date(committed.rows[0].committed_at);
    const coalescing = await db.query(
      `SELECT
         (SELECT COUNT(*)::int FROM "HomeSummaryProjectionQueue"
           WHERE "summaryDate" = $1::date
             AND "projectionKind" = 'FINANCE') AS queue_rows,
         (SELECT COUNT(*)::int FROM "DomainOutboxEvent"
           WHERE "dedupeKey" = 'home-summary-source:' || $1::text || ':FINANCE') AS source_events`,
      [burstDate],
    );
    const projection = await waitForProjection(
      db,
      burstDate,
      committedAt,
      timeoutMs,
    );
    const projectionLagMs = Math.max(
      0,
      new Date(projection.generated_at).getTime() - committedAt.getTime(),
    );
    const queueRows = Number(coalescing.rows[0]?.queue_rows || 0);
    const sourceEvents = Number(coalescing.rows[0]?.source_events || 0);
    evidence = {
      enabled: true,
      rowCount: BURST_ROWS,
      sourceWriteDurationMs,
      queueRowsObservedAfterCommit: queueRows,
      sourceOutboxRows: sourceEvents,
      projectionLagMs,
      projectionLagLimitMs: lagLimitMs,
      projectionVersion: String(projection.projection_version),
      coalesced: queueRows <= 1 && sourceEvents === 1,
      passed:
        queueRows <= 1 && sourceEvents === 1 && projectionLagMs <= lagLimitMs,
    };
  } catch (error) {
    primaryError = error;
  } finally {
    await db.query("ROLLBACK").catch(() => undefined);
    if (cleanupAuthorized) {
      const cleanup = await cleanupBurst(db, prefix, burstDate).catch(
        (error) => ({
          passed: false,
          error: error instanceof Error ? error.message : String(error),
        }),
      );
      if (!cleanup.passed) {
        throw new Error(
          `Disposable burst cleanup failed: ${cleanup.error || "unknown"}`,
        );
      }
      if (evidence) evidence.cleanup = cleanup;
    }
  }
  if (primaryError) throw primaryError;
  return evidence;
}

function assertDisposableBurstGuard(urlText) {
  if (process.env.BURST_APPROVAL !== BURST_APPROVAL) {
    throw new Error(`BURST_APPROVAL must equal ${BURST_APPROVAL}`);
  }
  if (process.env.OPSHUB_DISPOSABLE_DB !== "1") {
    throw new Error("OPSHUB_DISPOSABLE_DB=1 is required");
  }
  if (String(process.env.NODE_ENV || "").toLowerCase() === "production") {
    throw new Error("Burst proof is forbidden when NODE_ENV=production");
  }
  const url = new URL(urlText);
  const loopbackHosts = new Set(["localhost", "127.0.0.1", "[::1]"]);
  if (!loopbackHosts.has(url.hostname.toLowerCase())) {
    throw new Error("Burst proof requires a loopback PostgreSQL host");
  }
  const databaseName = decodeURIComponent(url.pathname.replace(/^\//, ""));
  if (
    !/^opshub_(?:home_projection_test|phase1_disposable)_[a-z0-9_]+$/.test(
      databaseName,
    )
  ) {
    throw new Error("Database name does not match the disposable proof prefix");
  }
}

async function waitForProjection(db, burstDate, committedAt, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const result = await db.query(
      `SELECT "financeStatus", "financeProjectionVersion", "financeGeneratedAt"
         FROM "HomeSummaryProjectionState"
        WHERE "summaryDate" = $1::date`,
      [burstDate],
    );
    const state = result.rows[0];
    if (
      state?.financeStatus === "COMPLETE" &&
      state.financeGeneratedAt &&
      new Date(state.financeGeneratedAt) >= committedAt
    ) {
      return {
        projection_version: state.financeProjectionVersion,
        generated_at: state.financeGeneratedAt,
      };
    }
    await delay(250);
  }
  throw new Error(
    "Projection worker did not complete the disposable burst before timeout",
  );
}

async function cleanupBurst(db, prefix, burstDate) {
  await db.query("BEGIN");
  try {
    await db.query(
      `DELETE FROM "MapVietinTransaction" WHERE "transactionKey" LIKE $1`,
      [`${prefix}%`],
    );
    await db.query(
      `DELETE FROM "HomeSummaryProjectionQueue" WHERE "summaryDate" = $1::date`,
      [burstDate],
    );
    await db.query(
      `DELETE FROM "HomeSummaryDailyAggregate" WHERE "summaryDate" = $1::date`,
      [burstDate],
    );
    await db.query(
      `DELETE FROM "HomeSummaryProjectionState" WHERE "summaryDate" = $1::date`,
      [burstDate],
    );
    await db.query(
      `DELETE FROM "DomainOutboxEvent"
        WHERE "aggregateId" = $1
          AND "eventType" IN ('HOME_SUMMARY_SOURCE_CHANGED', 'HOME_SUMMARY_UPDATED')`,
      [burstDate],
    );
    await db.query("COMMIT");
  } catch (error) {
    await db.query("ROLLBACK").catch(() => undefined);
    throw error;
  }
  const result = await db.query(
    `SELECT
       (SELECT COUNT(*)::int FROM "MapVietinTransaction"
         WHERE "transactionKey" LIKE $1) AS source_rows,
       (SELECT COUNT(*)::int FROM "HomeSummaryProjectionQueue"
         WHERE "summaryDate" = $2::date) AS queue_rows,
       (SELECT COUNT(*)::int FROM "HomeSummaryProjectionState"
         WHERE "summaryDate" = $2::date) AS state_rows,
       (SELECT COUNT(*)::int FROM "HomeSummaryDailyAggregate"
         WHERE "summaryDate" = $2::date) AS aggregate_rows,
       (SELECT COUNT(*)::int FROM "DomainOutboxEvent"
         WHERE "aggregateId" = $2
           AND "eventType" IN ('HOME_SUMMARY_SOURCE_CHANGED', 'HOME_SUMMARY_UPDATED')) AS event_rows`,
    [`${prefix}%`, burstDate],
  );
  const remainingRows = Object.values(result.rows[0]).reduce(
    (sum, value) => sum + Number(value),
    0,
  );
  return { passed: remainingRows === 0, remainingRows };
}

function boundedInteger(raw, fallback, min, max, name) {
  const value = raw === undefined || raw === "" ? fallback : Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new Error(`${name} must be an integer from ${min} to ${max}`);
  }
  return value;
}

function nullableNumber(value) {
  return value === null || value === undefined ? null : Number(value);
}

function assertDate(value, name) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${name} must use YYYY-MM-DD`);
  }
  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== value
  ) {
    throw new Error(`${name} is not a valid date`);
  }
}

function addUtcDays(dateKey, delta) {
  const date = new Date(`${dateKey}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + delta);
  return date.toISOString().slice(0, 10);
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
