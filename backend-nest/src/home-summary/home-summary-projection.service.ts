import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { Cron, Interval } from '@nestjs/schedule';
import { Prisma } from '@prisma/client';
import pg from 'pg';
import { safeLogError } from '../common/log-sanitizer';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { HomeSummaryService } from './home-summary.service';

const HOME_SUMMARY_UPDATED_CHANNEL = 'HOME_SUMMARY_UPDATED';
const HOME_SUMMARY_SOURCE_EVENT = 'HOME_SUMMARY_SOURCE_CHANGED';
const HOME_SUMMARY_UPDATED_EVENT = 'HOME_SUMMARY_UPDATED';
const PROJECTION_LISTEN_CHANNEL = 'opshub_home_summary_projection';
const MAX_PARALLEL_JOBS = 4;
const OUTBOX_BATCH_SIZE = 20;
const PROJECTION_LEASE_SECONDS = 120;
const OUTBOX_LEASE_SECONDS = 30;

type ProjectionKind = 'SALES' | 'FINANCE';

type ClaimedProjectionJob = {
  id: string;
  summaryDate: Date;
  projectionKind: ProjectionKind;
  dimensionType: string;
  dimensionKey: string;
  storeCode: string;
  sourceUpdatedAt: Date;
  claimedAt: Date;
  claimToken: string;
  leaseExpiresAt: Date;
  dirtyGeneration: bigint;
  claimedGeneration: bigint;
  attempts: number;
  firstEnqueuedAt: Date;
};

@Injectable()
export class HomeSummaryProjectionService
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(HomeSummaryProjectionService.name);
  private listener: pg.Client | null = null;
  private listenerReconnectTimer: NodeJS.Timeout | null = null;
  private cycleRunning = false;
  private destroyed = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly homeSummary: HomeSummaryService,
    private readonly redis: RedisService,
  ) {}

  onModuleInit() {
    if (!this.workerEnabled()) {
      this.logger.log('Home projection worker skipped: reason=disabled');
      return;
    }
    void this.startListener();
    void this.runStartupCycle();
  }

  async onModuleDestroy() {
    this.destroyed = true;
    if (this.listenerReconnectTimer) {
      clearTimeout(this.listenerReconnectTimer);
      this.listenerReconnectTimer = null;
    }
    const listener = this.listener;
    this.listener = null;
    if (listener) {
      listener.removeAllListeners();
      await listener.end().catch(() => undefined);
    }
  }

  @Interval(1000)
  async handleProjectionPoll() {
    await this.runCycle('poll');
  }

  @Interval(60_000)
  async reconcileToday() {
    if (!this.workerEnabled()) return;
    await this.enqueueReconciliationDates(1, 'today_1m', false);
  }

  @Cron('0 0 * * * *')
  async reconcileRecentSevenDays() {
    if (!this.workerEnabled()) return;
    await this.enqueueReconciliationDates(7, 'recent_7d_hourly');
  }

  @Cron('0 30 2 * * *', { timeZone: 'Asia/Ho_Chi_Minh' })
  async reconcileRecentNinetyDays() {
    if (!this.workerEnabled()) return;
    await this.enqueueReconciliationDates(90, 'recent_90d_nightly');
  }

  private async startListener() {
    if (this.destroyed || !this.workerEnabled() || this.listener) return;
    const connectionString = process.env.DATABASE_URL?.trim();
    if (!connectionString) {
      this.logger.warn(
        'Home projection LISTEN skipped: reason=missing_database_url pollingFallbackMs=1000',
      );
      return;
    }
    const listener = new pg.Client({ connectionString });
    this.listener = listener;
    listener.on('notification', (message) => {
      if (message.channel !== PROJECTION_LISTEN_CHANNEL) return;
      void this.runCycle('notify');
    });
    listener.on('error', (error) => {
      this.logger.warn(
        `Home projection LISTEN failed; polling remains active error=${safeLogError(error)}`,
      );
      if (this.listener === listener) this.listener = null;
      listener.removeAllListeners();
      void listener.end().catch(() => undefined);
      this.scheduleListenerReconnect();
    });
    try {
      await listener.connect();
      await listener.query(`LISTEN ${PROJECTION_LISTEN_CHANNEL}`);
      this.logger.log(
        'Home projection LISTEN ready: pollingFallbackMs=1000 channel=opshub_home_summary_projection',
      );
    } catch (error) {
      if (this.listener === listener) this.listener = null;
      listener.removeAllListeners();
      await listener.end().catch(() => undefined);
      this.logger.warn(
        `Home projection LISTEN unavailable; polling remains active error=${safeLogError(error)}`,
      );
      this.scheduleListenerReconnect();
    }
  }

  private scheduleListenerReconnect() {
    if (this.destroyed || this.listenerReconnectTimer) return;
    this.listenerReconnectTimer = setTimeout(() => {
      this.listenerReconnectTimer = null;
      void this.startListener();
    }, 5_000);
  }

  private async runStartupCycle() {
    const startedAt = Date.now();
    this.logger.log(
      'Home projection startup reconciliation started: reason=pending_payment_rollout',
    );
    try {
      const affectedDates = await this.prisma.$queryRaw<
        Array<{ dateKey: string }>
      >(Prisma.sql`
        WITH pending_dates AS (
          SELECT DISTINCT ("summaryDate" + INTERVAL '7 hours')::date AS summary_date
          FROM "HomeSummaryOrderFact"
          WHERE "isPaymentPending"
        ), expected AS (
          SELECT pending.summary_date,
            COUNT(*) FILTER (WHERE NOT fact."isPaymentPending")::int AS total_orders,
            COUNT(*) FILTER (WHERE NOT fact."isPaymentPending" AND fact."hasValidReport")::int AS reported_orders,
            COALESCE(
              SUM(GREATEST(COALESCE(fact."grandTotal", 0), 0))
                FILTER (WHERE NOT fact."isPaymentPending"),
              0
            ) AS order_revenue
          FROM pending_dates AS pending
          JOIN "HomeSummaryOrderFact" AS fact
            ON (fact."summaryDate" + INTERVAL '7 hours')::date = pending.summary_date
          GROUP BY pending.summary_date
        )
        SELECT expected.summary_date::text AS "dateKey"
        FROM expected
        LEFT JOIN "HomeSummaryDailyAggregate" AS aggregate
          ON aggregate."summaryDate" = expected.summary_date
          AND aggregate."projectionKind" = 'SALES'
          AND aggregate."dimensionType" = 'GLOBAL'
          AND aggregate."dimensionKey" = ''
          AND aggregate."storeCode" = ''
        WHERE aggregate."id" IS NULL
          OR aggregate."totalOrders" <> expected.total_orders
          OR aggregate."reportedOrders" <> expected.reported_orders
          OR aggregate."orderRevenueAmount" <> expected.order_revenue
        ORDER BY expected.summary_date
      `);
      for (const affectedDate of affectedDates) {
        await this.prisma.$executeRaw(
          Prisma.sql`SELECT opshub_enqueue_home_summary_projection_kind(CAST(${affectedDate.dateKey} AS date), 'RECONCILIATION', 'SALES')`,
        );
      }
      this.logger.log(
        `Home projection startup reconciliation succeeded: reason=pending_payment_rollout dates=${affectedDates.length} durationMs=${Date.now() - startedAt}`,
      );
    } catch (error) {
      this.logger.error(
        `Home projection startup reconciliation failed: reason=pending_payment_rollout durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
    }
    await this.runCycle('startup');
  }

  private async runCycle(source: string) {
    if (!this.workerEnabled() || this.cycleRunning || this.destroyed) return;
    this.cycleRunning = true;
    const startedAt = Date.now();
    try {
      const jobs = await this.claimProjectionJobs();
      if (jobs.length > 0) {
        this.logger.log(
          `Home projection cycle started: source=${source} jobs=${jobs.length}`,
        );
        await Promise.all(jobs.map((job) => this.processJob(job)));
      }
      const published = await this.publishPendingEvents();
      if (jobs.length > 0 || published > 0) {
        this.logger.log(
          `Home projection cycle succeeded: source=${source} jobs=${jobs.length} published=${published} durationMs=${Date.now() - startedAt}`,
        );
      }
    } catch (error) {
      this.logger.error(
        `Home projection cycle failed: source=${source} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
    } finally {
      this.cycleRunning = false;
    }
  }

  private async claimProjectionJobs(): Promise<ClaimedProjectionJob[]> {
    const rows = await this.prisma.$queryRaw<ClaimedProjectionJob[]>(Prisma.sql`
      WITH candidates AS (
        SELECT "id"
        FROM "HomeSummaryProjectionQueue"
        WHERE "availableAt" <= CURRENT_TIMESTAMP
          AND ("claimToken" IS NULL OR "leaseExpiresAt" < CURRENT_TIMESTAMP)
        ORDER BY "availableAt" ASC, "firstEnqueuedAt" ASC
        FOR UPDATE SKIP LOCKED
        LIMIT ${MAX_PARALLEL_JOBS}
      )
      UPDATE "HomeSummaryProjectionQueue" AS queue
      SET "claimedAt" = CURRENT_TIMESTAMP,
          "claimToken" = gen_random_uuid()::text,
          "leaseExpiresAt" = CURRENT_TIMESTAMP + (${PROJECTION_LEASE_SECONDS} * INTERVAL '1 second'),
          "claimedGeneration" = queue."dirtyGeneration",
          "attempts" = queue."attempts" + 1,
          "updatedAt" = CURRENT_TIMESTAMP
      FROM candidates
      WHERE queue."id" = candidates."id"
      RETURNING queue."id", queue."summaryDate", queue."projectionKind", queue."dimensionType",
                queue."dimensionKey", queue."storeCode",
                queue."sourceUpdatedAt", queue."claimedAt", queue."claimToken",
                queue."leaseExpiresAt", queue."dirtyGeneration", queue."claimedGeneration",
                queue."attempts", queue."firstEnqueuedAt"
    `);
    return rows.map((row) => ({
      ...row,
      summaryDate: new Date(row.summaryDate),
      sourceUpdatedAt: new Date(row.sourceUpdatedAt),
      claimedAt: new Date(row.claimedAt),
      leaseExpiresAt: new Date(row.leaseExpiresAt),
      dirtyGeneration: BigInt(row.dirtyGeneration),
      claimedGeneration: BigInt(row.claimedGeneration),
      firstEnqueuedAt: new Date(row.firstEnqueuedAt),
    }));
  }

  private async processJob(job: ClaimedProjectionJob) {
    const dateKey = this.dateKey(job.summaryDate);
    const startedAt = Date.now();
    const queueDelayMs = Math.max(
      0,
      startedAt - new Date(job.firstEnqueuedAt).getTime(),
    );
    this.logger.log(
      `Home projection rebuild started: date=${dateKey} kind=${job.projectionKind} grain=${job.dimensionType} generation=${job.claimedGeneration.toString()} sourceCommitAt=${job.sourceUpdatedAt.toISOString()} queueDelayMs=${queueDelayMs} attempt=${job.attempts}`,
    );
    try {
      if (job.projectionKind === 'SALES') {
        await this.homeSummary.rebuildProjectionDate(dateKey);
      }
      const version = await this.finalizeProjection(job, dateKey);
      if (version === null) {
        this.logger.log(
          `Home projection rebuild lease lost: date=${dateKey} kind=${job.projectionKind} grain=${job.dimensionType} durationMs=${Date.now() - startedAt}`,
        );
        return;
      }
      this.logger.log(
        `Home projection rebuild succeeded: date=${dateKey} kind=${job.projectionKind} grain=${job.dimensionType} generation=${job.claimedGeneration.toString()} sourceCommitAt=${job.sourceUpdatedAt.toISOString()} projectionVersion=${version.toString()} queueDelayMs=${queueDelayMs} rebuildDurationMs=${Date.now() - startedAt}`,
      );
    } catch (error) {
      const retrySeconds = this.retrySeconds(job.attempts);
      const sanitizedError = safeLogError(error).slice(0, 500);
      await this.prisma.$transaction([
        this.prisma.homeSummaryProjectionQueue.updateMany({
          where: { id: job.id, claimToken: job.claimToken },
          data: {
            claimedAt: null,
            claimToken: null,
            leaseExpiresAt: null,
            claimedGeneration: null,
            availableAt: new Date(Date.now() + retrySeconds * 1000),
            lastError: sanitizedError,
          },
        }),
        this.prisma.homeSummaryProjectionState.updateMany({
          where: { summaryDate: job.summaryDate },
          data: {
            status: 'ERROR',
            ...(job.projectionKind === 'SALES'
              ? { salesStatus: 'ERROR' }
              : { financeStatus: 'ERROR' }),
            lastError: sanitizedError,
          },
        }),
      ]);
      this.logger.error(
        `Home projection rebuild failed: date=${dateKey} kind=${job.projectionKind} grain=${job.dimensionType} attempt=${job.attempts} retrySeconds=${retrySeconds} durationMs=${Date.now() - startedAt} error=${sanitizedError}`,
      );
    }
  }

  private async finalizeProjection(
    job: ClaimedProjectionJob,
    dateKey: string,
  ): Promise<bigint | null> {
    return this.prisma.$transaction(async (tx) => {
      const currentRows = await tx.$queryRaw<
        Array<{
          sourceUpdatedAt: Date;
          claimToken: string | null;
          dirtyGeneration: bigint;
          claimedGeneration: bigint | null;
        }>
      >(Prisma.sql`
        SELECT "sourceUpdatedAt", "claimToken", "dirtyGeneration", "claimedGeneration"
        FROM "HomeSummaryProjectionQueue"
        WHERE "id" = ${job.id}
        FOR UPDATE
      `);
      const current = currentRows[0];
      if (
        !current ||
        current.claimToken !== job.claimToken ||
        current.claimedGeneration === null ||
        BigInt(current.claimedGeneration) !== job.claimedGeneration
      ) {
        return null;
      }

      const versionRows = await tx.$queryRaw<Array<{ version: bigint }>>(
        Prisma.sql`SELECT nextval('home_summary_projection_version_seq') AS version`,
      );
      const version = versionRows[0]?.version;
      if (version === undefined) {
        throw new Error('Projection version sequence returned no value');
      }
      const generatedAt = new Date();
      await tx.homeSummaryDailyAggregate.deleteMany({
        where: {
          summaryDate: job.summaryDate,
          projectionKind: job.projectionKind,
        },
      });
      if (job.projectionKind === 'SALES') {
        await this.insertGlobalAggregate(
          tx,
          dateKey,
          version,
          job.sourceUpdatedAt,
          generatedAt,
        );
        await this.insertStoreAggregates(
          tx,
          dateKey,
          version,
          job.sourceUpdatedAt,
          generatedAt,
        );
        await this.insertUserStoreAggregates(
          tx,
          dateKey,
          version,
          job.sourceUpdatedAt,
          generatedAt,
        );
        await this.homeSummary.populateSalesProjectionMetrics(tx, dateKey);
      } else {
        await this.insertFinanceAggregates(
          tx,
          dateKey,
          version,
          job.sourceUpdatedAt,
          generatedAt,
        );
      }

      await tx.homeSummaryProjectionState.upsert({
        where: { summaryDate: job.summaryDate },
        create: {
          summaryDate: job.summaryDate,
          status: 'PENDING',
          projectionVersion: version,
          sourceUpdatedAt: job.sourceUpdatedAt,
          generatedAt,
          ...(job.projectionKind === 'SALES'
            ? {
                salesStatus: 'COMPLETE',
                salesProjectionVersion: version,
                salesGeneratedAt: generatedAt,
              }
            : {
                financeStatus: 'COMPLETE',
                financeProjectionVersion: version,
                financeGeneratedAt: generatedAt,
              }),
          lastError: null,
        },
        update: {
          projectionVersion: version,
          ...(job.projectionKind === 'SALES'
            ? {
                salesStatus: 'COMPLETE',
                salesProjectionVersion: version,
                salesGeneratedAt: generatedAt,
              }
            : {
                financeStatus: 'COMPLETE',
                financeProjectionVersion: version,
                financeGeneratedAt: generatedAt,
              }),
          lastError: null,
        },
      });
      await tx.$executeRaw(Prisma.sql`
        UPDATE "HomeSummaryProjectionState"
        SET "status" = CASE
              WHEN "salesStatus" = 'COMPLETE' AND "financeStatus" = 'COMPLETE' THEN 'COMPLETE'
              ELSE 'PENDING'
            END,
            "projectionVersion" = GREATEST("salesProjectionVersion", "financeProjectionVersion"),
            "generatedAt" = CASE
              WHEN "salesGeneratedAt" IS NULL THEN "financeGeneratedAt"
              WHEN "financeGeneratedAt" IS NULL THEN "salesGeneratedAt"
              ELSE LEAST("salesGeneratedAt", "financeGeneratedAt")
            END,
            "sourceUpdatedAt" = GREATEST(
              COALESCE("sourceUpdatedAt", ${job.sourceUpdatedAt}),
              ${job.sourceUpdatedAt}
            ),
            "updatedAt" = CURRENT_TIMESTAMP
        WHERE "summaryDate" = CAST(${dateKey} AS date)
      `);
      await tx.domainOutboxEvent.create({
        data: {
          eventType: HOME_SUMMARY_UPDATED_EVENT,
          aggregateType: 'HOME_SUMMARY_DATE',
          aggregateId: dateKey,
          dedupeKey: `home-summary-updated:${job.projectionKind}:${version.toString()}`,
          schemaVersion: 2,
          payload: {
            affectedDates: [dateKey],
            projectionVersion: Number(version),
          },
          occurredAt: generatedAt,
          availableAt: generatedAt,
        },
      });
      await tx.domainOutboxEvent.updateMany({
        where: {
          eventType: HOME_SUMMARY_SOURCE_EVENT,
          aggregateId: dateKey,
          publishedAt: null,
          payload: {
            path: ['projectionKind'],
            equals: job.projectionKind,
          },
        },
        data: { publishedAt: generatedAt, lastError: null },
      });
      const hasFollowUp =
        BigInt(current.dirtyGeneration) > job.claimedGeneration;
      if (hasFollowUp) {
        await tx.homeSummaryProjectionQueue.updateMany({
          where: { id: job.id, claimToken: job.claimToken },
          data: {
            claimedAt: null,
            claimToken: null,
            leaseExpiresAt: null,
            claimedGeneration: null,
            firstEnqueuedAt: generatedAt,
            attempts: 0,
          },
        });
      } else {
        await tx.homeSummaryProjectionQueue.deleteMany({
          where: {
            id: job.id,
            claimToken: job.claimToken,
            dirtyGeneration: job.claimedGeneration,
          },
        });
      }
      return version;
    });
  }

  private insertGlobalAggregate(
    tx: Prisma.TransactionClient,
    dateKey: string,
    version: bigint,
    sourceUpdatedAt: Date,
    generatedAt: Date,
  ) {
    return tx.$executeRaw(Prisma.sql`
      INSERT INTO "HomeSummaryDailyAggregate" (
        "id", "summaryDate", "projectionKind", "dimensionType", "dimensionKey", "storeCode",
        "totalOrders", "reportedOrders", "totalReports",
        "notPurchasedReports", "orderRevenueAmount", "reportRevenueAmount",
        "metrics", "projectionVersion", "sourceUpdatedAt", "generatedAt",
        "createdAt", "updatedAt"
      )
      SELECT gen_random_uuid()::text, CAST(${dateKey} AS date), 'SALES', 'GLOBAL', '', '',
        (SELECT COUNT(*)::int FROM "HomeSummaryOrderFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)
            AND NOT "isPaymentPending"),
        (SELECT COUNT(*) FILTER (WHERE "hasValidReport")::int
          FROM "HomeSummaryOrderFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)
            AND NOT "isPaymentPending"),
        (SELECT COUNT(*)::int FROM "HomeSummaryReportFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)),
        (SELECT COUNT(*) FILTER (WHERE "reportType" = 'NOT_PURCHASED')::int
          FROM "HomeSummaryReportFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)),
        (SELECT COALESCE(SUM(GREATEST(COALESCE("grandTotal", 0), 0)), 0)
          FROM "HomeSummaryOrderFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)
            AND NOT "isPaymentPending"),
        (SELECT COALESCE(SUM(GREATEST(COALESCE("revenue", 0), 0)), 0)
          FROM "HomeSummaryReportFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)),
        '{}'::jsonb, ${version}, ${sourceUpdatedAt}, ${generatedAt}, ${generatedAt}, ${generatedAt}
    `);
  }

  private insertStoreAggregates(
    tx: Prisma.TransactionClient,
    dateKey: string,
    version: bigint,
    sourceUpdatedAt: Date,
    generatedAt: Date,
  ) {
    return tx.$executeRaw(Prisma.sql`
      WITH order_metrics AS (
        SELECT UPPER(TRIM(COALESCE("storeCode", ''))) AS store_code,
          COUNT(*)::int AS total_orders,
          COUNT(*) FILTER (WHERE "hasValidReport")::int AS reported_orders,
          COALESCE(SUM(GREATEST(COALESCE("grandTotal", 0), 0)), 0) AS order_revenue
        FROM "HomeSummaryOrderFact"
        WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)
          AND NOT "isPaymentPending"
        GROUP BY UPPER(TRIM(COALESCE("storeCode", '')))
      ), report_metrics AS (
        SELECT UPPER(TRIM(COALESCE("storeCode", ''))) AS store_code,
          COUNT(*)::int AS total_reports,
          COUNT(*) FILTER (WHERE "reportType" = 'NOT_PURCHASED')::int AS not_purchased,
          COALESCE(SUM(GREATEST(COALESCE("revenue", 0), 0)), 0) AS report_revenue
        FROM "HomeSummaryReportFact"
        WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)
        GROUP BY UPPER(TRIM(COALESCE("storeCode", '')))
      )
      INSERT INTO "HomeSummaryDailyAggregate" (
        "id", "summaryDate", "projectionKind", "dimensionType", "dimensionKey", "storeCode",
        "totalOrders", "reportedOrders", "totalReports",
        "notPurchasedReports", "orderRevenueAmount", "reportRevenueAmount",
        "metrics", "projectionVersion", "sourceUpdatedAt", "generatedAt",
        "createdAt", "updatedAt"
      )
      SELECT gen_random_uuid()::text, CAST(${dateKey} AS date), 'SALES', 'STORE',
        COALESCE(o.store_code, r.store_code), COALESCE(o.store_code, r.store_code),
        COALESCE(o.total_orders, 0), COALESCE(o.reported_orders, 0),
        COALESCE(r.total_reports, 0), COALESCE(r.not_purchased, 0),
        COALESCE(o.order_revenue, 0), COALESCE(r.report_revenue, 0),
        '{}'::jsonb, ${version}, ${sourceUpdatedAt}, ${generatedAt}, ${generatedAt}, ${generatedAt}
      FROM order_metrics o
      FULL OUTER JOIN report_metrics r ON r.store_code = o.store_code
      WHERE COALESCE(o.store_code, r.store_code) <> ''
    `);
  }

  private insertUserStoreAggregates(
    tx: Prisma.TransactionClient,
    dateKey: string,
    version: bigint,
    sourceUpdatedAt: Date,
    generatedAt: Date,
  ) {
    return tx.$executeRaw(Prisma.sql`
      WITH order_metrics AS (
        SELECT
          LOWER(TRIM(identity.email)) AS user_key,
          UPPER(TRIM(COALESCE("storeCode", ''))) AS store_code,
          COUNT(*)::int AS total_orders,
          COUNT(*) FILTER (WHERE "hasValidReport")::int AS reported_orders,
          COALESCE(SUM(GREATEST(COALESCE("grandTotal", 0), 0)), 0) AS order_revenue
        FROM "HomeSummaryOrderFact"
        CROSS JOIN LATERAL (
          SELECT DISTINCT email
          FROM unnest(ARRAY[
            "sourceUserEmail", "consultantEmail", "sellerEmail", "reportCreatedByEmail"
          ]) AS candidate(email)
          WHERE NULLIF(TRIM(email), '') IS NOT NULL
        ) AS identity
        WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)
          AND NOT "isPaymentPending"
        GROUP BY 1, 2
      ), report_metrics AS (
        SELECT
          LOWER(TRIM(COALESCE("createdByEmail", ''))) AS user_key,
          UPPER(TRIM(COALESCE("storeCode", ''))) AS store_code,
          COUNT(*)::int AS total_reports,
          COUNT(*) FILTER (WHERE "reportType" = 'NOT_PURCHASED')::int AS not_purchased,
          COALESCE(SUM(GREATEST(COALESCE("revenue", 0), 0)), 0) AS report_revenue
        FROM "HomeSummaryReportFact"
        WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)
        GROUP BY 1, 2
      )
      INSERT INTO "HomeSummaryDailyAggregate" (
        "id", "summaryDate", "projectionKind", "dimensionType", "dimensionKey", "storeCode",
        "totalOrders", "reportedOrders", "totalReports",
        "notPurchasedReports", "orderRevenueAmount", "reportRevenueAmount",
        "metrics", "projectionVersion", "sourceUpdatedAt", "generatedAt",
        "createdAt", "updatedAt"
      )
      SELECT gen_random_uuid()::text, CAST(${dateKey} AS date), 'SALES', 'USER_STORE',
        COALESCE(o.user_key, r.user_key), COALESCE(o.store_code, r.store_code),
        COALESCE(o.total_orders, 0), COALESCE(o.reported_orders, 0),
        COALESCE(r.total_reports, 0), COALESCE(r.not_purchased, 0),
        COALESCE(o.order_revenue, 0), COALESCE(r.report_revenue, 0),
        '{}'::jsonb, ${version}, ${sourceUpdatedAt}, ${generatedAt}, ${generatedAt}, ${generatedAt}
      FROM order_metrics o
      FULL OUTER JOIN report_metrics r
        ON r.user_key = o.user_key AND r.store_code = o.store_code
      WHERE COALESCE(o.user_key, r.user_key) <> ''
        AND COALESCE(o.store_code, r.store_code) <> ''
    `);
  }

  private insertFinanceAggregates(
    tx: Prisma.TransactionClient,
    dateKey: string,
    version: bigint,
    sourceUpdatedAt: Date,
    generatedAt: Date,
  ) {
    return tx.$executeRaw(Prisma.sql`
      WITH source_rows AS (
        SELECT transaction.*,
          COALESCE(NULLIF(UPPER(TRIM(transaction."storeCode")), ''), '') AS store_code,
          COALESCE(transaction."paidAt", transaction."firstSeenAt") AS occurred_at
        FROM "MapVietinTransaction" AS transaction
        WHERE COALESCE(transaction."paidAt", transaction."firstSeenAt") >= CAST(${dateKey} AS date) - INTERVAL '7 hours'
          AND COALESCE(transaction."paidAt", transaction."firstSeenAt") < CAST(${dateKey} AS date) + INTERVAL '1 day' - INTERVAL '7 hours'
      ), user_order_grains AS (
        SELECT DISTINCT fact."orderCode" AS order_code,
          LOWER(TRIM(identity.email)) AS user_key,
          UPPER(TRIM(COALESCE(fact."storeCode", ''))) AS store_code
        FROM "HomeSummaryOrderFact" AS fact
        CROSS JOIN LATERAL unnest(ARRAY[
          fact."sourceUserEmail", fact."consultantEmail", fact."sellerEmail",
          fact."reportCreatedByEmail"
        ]) AS identity(email)
        WHERE fact."summaryDate" >= CAST(${dateKey} AS date) - INTERVAL '7 hours'
          AND fact."summaryDate" < CAST(${dateKey} AS date) + INTERVAL '1 day' - INTERVAL '7 hours'
          AND NULLIF(TRIM(identity.email), '') IS NOT NULL
      ), user_transactions AS (
        SELECT DISTINCT source."id", mapping.user_key, mapping.store_code
        FROM source_rows AS source
        JOIN user_order_grains AS mapping ON mapping.order_code = ANY(source."orders")
        WHERE mapping.store_code <> ''
      ), grains AS (
        SELECT 'GLOBAL'::text AS dimension_type, ''::text AS dimension_key,
          ''::text AS grain_store_code, source."id", source."amount", source."orders"
        FROM source_rows AS source
        UNION ALL
        SELECT 'STORE', source.store_code, source.store_code,
          source."id", source."amount", source."orders"
        FROM source_rows AS source
        WHERE source.store_code <> ''
        UNION ALL
        SELECT 'USER_STORE', mapped.user_key, mapped.store_code,
          source."id", source."amount", source."orders"
        FROM user_transactions AS mapped
        JOIN source_rows AS source ON source."id" = mapped."id"
      ), grouped AS (
        SELECT dimension_type, dimension_key, grain_store_code,
          COUNT(*)::int AS statement_count,
          COALESCE(SUM(GREATEST(COALESCE("amount", 0), 0)), 0) AS transferred_amount,
          COUNT(*) FILTER (WHERE cardinality("orders") > 0)::int AS with_order,
          COUNT(*) FILTER (WHERE cardinality("orders") = 0)::int AS without_order
        FROM grains
        GROUP BY dimension_type, dimension_key, grain_store_code
      )
      INSERT INTO "HomeSummaryDailyAggregate" (
        "id", "summaryDate", "projectionKind", "dimensionType", "dimensionKey", "storeCode",
        "totalOrders", "reportedOrders", "totalReports", "notPurchasedReports",
        "orderRevenueAmount", "reportRevenueAmount", "metrics", "projectionVersion",
        "sourceUpdatedAt", "generatedAt", "createdAt", "updatedAt"
      )
      SELECT gen_random_uuid()::text, CAST(${dateKey} AS date), 'FINANCE',
        dimension_type, dimension_key, grain_store_code, 0, 0, 0, 0, 0, 0,
        jsonb_build_object(
          'totalStatements', statement_count,
          'totalTransferredAmount', transferred_amount,
          'totalStatementsWithOrder', with_order,
          'totalStatementsWithoutOrder', without_order
        ),
        ${version}, ${sourceUpdatedAt}, ${generatedAt}, ${generatedAt}, ${generatedAt}
      FROM grouped
    `);
  }

  private async publishPendingEvents() {
    const events = await this.prisma.$queryRaw<
      Array<{
        id: string;
        payload: Prisma.JsonValue;
        occurredAt: Date;
        attempts: number;
        claimToken: string;
      }>
    >(Prisma.sql`
      WITH candidates AS (
        SELECT "id"
        FROM "DomainOutboxEvent"
        WHERE "eventType" = ${HOME_SUMMARY_UPDATED_EVENT}
          AND "publishedAt" IS NULL
          AND "availableAt" <= CURRENT_TIMESTAMP
          AND ("claimToken" IS NULL OR "leaseExpiresAt" < CURRENT_TIMESTAMP)
        ORDER BY "occurredAt" ASC
        FOR UPDATE SKIP LOCKED
        LIMIT ${OUTBOX_BATCH_SIZE}
      )
      UPDATE "DomainOutboxEvent" AS event
      SET "claimedAt" = CURRENT_TIMESTAMP,
          "claimToken" = gen_random_uuid()::text,
          "leaseExpiresAt" = CURRENT_TIMESTAMP + (${OUTBOX_LEASE_SECONDS} * INTERVAL '1 second'),
          "updatedAt" = CURRENT_TIMESTAMP
      FROM candidates
      WHERE event."id" = candidates."id"
      RETURNING event."id", event."payload", event."occurredAt",
                event."attempts", event."claimToken"
    `);
    let published = 0;
    if (events.length > 0) {
      this.homeSummary.invalidateSummaryResponseCache(
        events.map((event) => {
          const payload = event.payload as Record<string, unknown>;
          return {
            affectedDates: Array.isArray(payload.affectedDates)
              ? payload.affectedDates.map(String).slice(0, 366)
              : [],
            projectionVersion: Number(payload.projectionVersion),
          };
        }),
        'projection_event_batch',
      );
    }
    for (const event of events) {
      const payload = event.payload as Record<string, unknown>;
      const affectedDates = Array.isArray(payload.affectedDates)
        ? payload.affectedDates.map(String).slice(0, 366)
        : [];
      const projectionVersion = Number(payload.projectionVersion);
      try {
        await this.redis.publishMessageOrThrow(HOME_SUMMARY_UPDATED_CHANNEL, {
          schemaVersion: 2,
          type: HOME_SUMMARY_UPDATED_EVENT,
          eventId: event.id,
          occurredAt: event.occurredAt.toISOString(),
          audience: { kind: 'AUTHENTICATED' },
          payload: { affectedDates, projectionVersion },
        });
        await this.prisma.domainOutboxEvent.updateMany({
          where: {
            id: event.id,
            publishedAt: null,
            claimToken: event.claimToken,
          },
          data: {
            publishedAt: new Date(),
            attempts: { increment: 1 },
            lastError: null,
            claimedAt: null,
            claimToken: null,
            leaseExpiresAt: null,
          },
        });
        published += 1;
        this.logger.log(
          `Home projection event publish succeeded: eventId=${event.id} dates=${affectedDates.length} projectionVersion=${projectionVersion}`,
        );
      } catch (error) {
        const attempts = event.attempts + 1;
        const retrySeconds = this.retrySeconds(attempts);
        const sanitizedError = safeLogError(error).slice(0, 500);
        await this.prisma.domainOutboxEvent.updateMany({
          where: {
            id: event.id,
            publishedAt: null,
            claimToken: event.claimToken,
          },
          data: {
            attempts,
            availableAt: new Date(Date.now() + retrySeconds * 1000),
            lastError: sanitizedError,
            claimedAt: null,
            claimToken: null,
            leaseExpiresAt: null,
          },
        });
        this.logger.error(
          `Home projection event publish failed: eventId=${event.id} attempt=${attempts} retrySeconds=${retrySeconds} error=${sanitizedError}`,
        );
      }
    }
    return published;
  }

  private async enqueueReconciliationDates(
    days: number,
    source: string,
    force = true,
  ) {
    const startedAt = Date.now();
    const today = this.vietnamDateKey(new Date());
    const todayUtc = this.dateOnlyUtc(today);
    const dates: string[] = [];
    for (let offset = days - 1; offset >= 0; offset -= 1) {
      const date = new Date(todayUtc);
      date.setUTCDate(date.getUTCDate() - offset);
      dates.push(this.dateKey(date));
    }
    this.logger.log(
      `Home projection reconciliation started: source=${source} dates=${dates.length} force=${force}`,
    );
    let datesToEnqueue = dates;
    let skippedStable = 0;
    let skippedQueued = 0;
    if (!force) {
      const dateValues = dates.map((date) => this.dateOnlyUtc(date));
      const [states, queuedRows] = await Promise.all([
        this.prisma.homeSummaryProjectionState.findMany({
          where: { summaryDate: { in: dateValues } },
          select: {
            summaryDate: true,
            status: true,
            salesStatus: true,
            financeStatus: true,
            sourceUpdatedAt: true,
            salesReportSourceUpdatedAt: true,
            erpOrderCacheSourceUpdatedAt: true,
            mapVietinSourceUpdatedAt: true,
            salesGeneratedAt: true,
            financeGeneratedAt: true,
            generatedAt: true,
          },
        }),
        this.prisma.homeSummaryProjectionQueue.findMany({
          where: {
            summaryDate: { in: dateValues },
          },
          select: { summaryDate: true, projectionKind: true },
        }),
      ]);
      const stateByDate = new Map(
        states.map((state) => [this.dateKey(state.summaryDate), state]),
      );
      const queuedKindsByDate = new Map<string, Set<ProjectionKind>>();
      for (const row of queuedRows) {
        const date = this.dateKey(row.summaryDate);
        const kinds = queuedKindsByDate.get(date) ?? new Set<ProjectionKind>();
        kinds.add(row.projectionKind as ProjectionKind);
        queuedKindsByDate.set(date, kinds);
      }
      datesToEnqueue = dates.filter((date) => {
        const queuedKinds = queuedKindsByDate.get(date);
        if (queuedKinds?.has('SALES') && queuedKinds.has('FINANCE')) {
          skippedQueued += 1;
          return false;
        }
        const state = stateByDate.get(date);
        const salesSourceUpdatedAt = [
          state?.salesReportSourceUpdatedAt,
          state?.erpOrderCacheSourceUpdatedAt,
        ]
          .filter(
            (value): value is Date => value !== null && value !== undefined,
          )
          .reduce<Date | null>(
            (latest, value) => (!latest || value > latest ? value : latest),
            null,
          );
        const financeSourceUpdatedAt = state?.mapVietinSourceUpdatedAt ?? null;
        const hasSpecificSourceWatermark =
          salesSourceUpdatedAt !== null || financeSourceUpdatedAt !== null;
        const salesBaseline =
          salesSourceUpdatedAt ??
          (!hasSpecificSourceWatermark
            ? (state?.sourceUpdatedAt ?? null)
            : null);
        const financeBaseline =
          financeSourceUpdatedAt ??
          (!hasSpecificSourceWatermark
            ? (state?.sourceUpdatedAt ?? null)
            : null);
        const salesCurrent =
          state?.salesGeneratedAt !== null &&
          state?.salesGeneratedAt !== undefined &&
          (hasSpecificSourceWatermark
            ? salesBaseline === null || salesBaseline <= state.salesGeneratedAt
            : salesBaseline !== null &&
              salesBaseline <= state.salesGeneratedAt);
        const financeCurrent =
          state?.financeGeneratedAt !== null &&
          state?.financeGeneratedAt !== undefined &&
          (hasSpecificSourceWatermark
            ? financeBaseline === null ||
              financeBaseline <= state.financeGeneratedAt
            : financeBaseline !== null &&
              financeBaseline <= state.financeGeneratedAt);
        const stable =
          state?.status === 'COMPLETE' &&
          state.salesStatus === 'COMPLETE' &&
          state.financeStatus === 'COMPLETE' &&
          salesCurrent &&
          financeCurrent;
        if (stable) {
          skippedStable += 1;
          return false;
        }
        return true;
      });
    }
    for (const dateKey of datesToEnqueue) {
      await this.prisma.$executeRaw(
        Prisma.sql`SELECT opshub_enqueue_home_summary_projection(CAST(${dateKey} AS date), 'RECONCILIATION')`,
      );
    }
    this.logger.log(
      `Home projection reconciliation succeeded: source=${source} requested=${dates.length} enqueued=${datesToEnqueue.length} skippedStable=${skippedStable} skippedQueued=${skippedQueued} durationMs=${Date.now() - startedAt}`,
    );
    if (datesToEnqueue.length > 0) {
      void this.runCycle(`reconciliation_${source}`);
    }
  }

  private retrySeconds(attempts: number) {
    return [2, 4, 8, 16, 30][Math.min(Math.max(attempts - 1, 0), 4)];
  }

  private workerEnabled() {
    const raw = process.env.HOME_SUMMARY_PROJECTION_WORKER_ENABLED;
    if (raw === undefined && process.env.NODE_ENV === 'test') return false;
    return (
      String(raw ?? 'true')
        .trim()
        .toLowerCase() !== 'false'
    );
  }

  private dateKey(value: Date) {
    return new Date(value).toISOString().slice(0, 10);
  }

  private dateOnlyUtc(value: string) {
    return new Date(`${value}T00:00:00.000Z`);
  }

  private vietnamDateKey(value: Date) {
    return new Date(value.getTime() + 7 * 60 * 60 * 1000)
      .toISOString()
      .slice(0, 10);
  }
}
