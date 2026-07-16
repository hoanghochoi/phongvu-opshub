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

type ClaimedProjectionJob = {
  id: string;
  summaryDate: Date;
  dimensionType: string;
  dimensionKey: string;
  storeCode: string;
  sourceUpdatedAt: Date;
  claimedAt: Date;
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
    void this.runCycle('startup');
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
          AND (
            "claimedAt" IS NULL
            OR "claimedAt" < CURRENT_TIMESTAMP - INTERVAL '2 minutes'
          )
        ORDER BY "availableAt" ASC, "firstEnqueuedAt" ASC
        FOR UPDATE SKIP LOCKED
        LIMIT ${MAX_PARALLEL_JOBS}
      )
      UPDATE "HomeSummaryProjectionQueue" AS queue
      SET "claimedAt" = CURRENT_TIMESTAMP,
          "attempts" = queue."attempts" + 1,
          "updatedAt" = CURRENT_TIMESTAMP
      FROM candidates
      WHERE queue."id" = candidates."id"
      RETURNING queue."id", queue."summaryDate", queue."dimensionType",
                queue."dimensionKey", queue."storeCode",
                queue."sourceUpdatedAt", queue."claimedAt",
                queue."attempts", queue."firstEnqueuedAt"
    `);
    return rows.map((row) => ({
      ...row,
      summaryDate: new Date(row.summaryDate),
      sourceUpdatedAt: new Date(row.sourceUpdatedAt),
      claimedAt: new Date(row.claimedAt),
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
      `Home projection rebuild started: date=${dateKey} grain=${job.dimensionType} sourceCommitAt=${job.sourceUpdatedAt.toISOString()} queueDelayMs=${queueDelayMs} attempt=${job.attempts}`,
    );
    try {
      await this.homeSummary.rebuildProjectionDate(dateKey);
      const version = await this.finalizeProjection(job, dateKey);
      if (version === null) {
        this.logger.log(
          `Home projection rebuild superseded: date=${dateKey} grain=${job.dimensionType} durationMs=${Date.now() - startedAt}`,
        );
        return;
      }
      this.logger.log(
        `Home projection rebuild succeeded: date=${dateKey} grain=${job.dimensionType} grainCount=3 sourceCommitAt=${job.sourceUpdatedAt.toISOString()} projectionVersion=${version.toString()} queueDelayMs=${queueDelayMs} rebuildDurationMs=${Date.now() - startedAt}`,
      );
    } catch (error) {
      const retrySeconds = this.retrySeconds(job.attempts);
      const sanitizedError = safeLogError(error).slice(0, 500);
      await this.prisma.$transaction([
        this.prisma.homeSummaryProjectionQueue.updateMany({
          where: { id: job.id, sourceUpdatedAt: job.sourceUpdatedAt },
          data: {
            claimedAt: null,
            availableAt: new Date(Date.now() + retrySeconds * 1000),
            lastError: sanitizedError,
          },
        }),
        this.prisma.homeSummaryProjectionState.updateMany({
          where: { summaryDate: job.summaryDate },
          data: { status: 'ERROR', lastError: sanitizedError },
        }),
      ]);
      this.logger.error(
        `Home projection rebuild failed: date=${dateKey} grain=${job.dimensionType} attempt=${job.attempts} retrySeconds=${retrySeconds} durationMs=${Date.now() - startedAt} error=${sanitizedError}`,
      );
    }
  }

  private async finalizeProjection(
    job: ClaimedProjectionJob,
    dateKey: string,
  ): Promise<bigint | null> {
    return this.prisma.$transaction(async (tx) => {
      const currentRows = await tx.$queryRaw<
        Array<{ sourceUpdatedAt: Date }>
      >(Prisma.sql`
        SELECT "sourceUpdatedAt"
        FROM "HomeSummaryProjectionQueue"
        WHERE "id" = ${job.id}
        FOR UPDATE
      `);
      const current = currentRows[0];
      if (
        !current ||
        current.sourceUpdatedAt.getTime() !==
          new Date(job.sourceUpdatedAt).getTime()
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
        where: { summaryDate: job.summaryDate },
      });
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

      await tx.homeSummaryProjectionState.upsert({
        where: { summaryDate: job.summaryDate },
        create: {
          summaryDate: job.summaryDate,
          status: 'COMPLETE',
          projectionVersion: version,
          sourceUpdatedAt: job.sourceUpdatedAt,
          generatedAt,
          lastError: null,
        },
        update: {
          status: 'COMPLETE',
          projectionVersion: version,
          sourceUpdatedAt: job.sourceUpdatedAt,
          generatedAt,
          lastError: null,
        },
      });
      await tx.domainOutboxEvent.create({
        data: {
          eventType: HOME_SUMMARY_UPDATED_EVENT,
          aggregateType: 'HOME_SUMMARY_DATE',
          aggregateId: dateKey,
          dedupeKey: `home-summary-updated:${version.toString()}`,
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
        },
        data: { publishedAt: generatedAt, lastError: null },
      });
      await tx.homeSummaryProjectionQueue.delete({ where: { id: job.id } });
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
        "id", "summaryDate", "dimensionType", "dimensionKey", "storeCode",
        "totalOrders", "reportedOrders", "totalReports",
        "notPurchasedReports", "orderRevenueAmount", "reportRevenueAmount",
        "projectionVersion", "sourceUpdatedAt", "generatedAt",
        "createdAt", "updatedAt"
      )
      SELECT gen_random_uuid()::text, CAST(${dateKey} AS date), 'GLOBAL', '', '',
        (SELECT COUNT(*)::int FROM "HomeSummaryOrderFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)),
        (SELECT COUNT(*) FILTER (WHERE "hasValidReport")::int
          FROM "HomeSummaryOrderFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)),
        (SELECT COUNT(*)::int FROM "HomeSummaryReportFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)),
        (SELECT COUNT(*) FILTER (WHERE "reportType" = 'NOT_PURCHASED')::int
          FROM "HomeSummaryReportFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)),
        (SELECT COALESCE(SUM(GREATEST(COALESCE("grandTotal", 0), 0)), 0)
          FROM "HomeSummaryOrderFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)),
        (SELECT COALESCE(SUM(GREATEST(COALESCE("revenue", 0), 0)), 0)
          FROM "HomeSummaryReportFact"
          WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)),
        ${version}, ${sourceUpdatedAt}, ${generatedAt}, ${generatedAt}, ${generatedAt}
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
        "id", "summaryDate", "dimensionType", "dimensionKey", "storeCode",
        "totalOrders", "reportedOrders", "totalReports",
        "notPurchasedReports", "orderRevenueAmount", "reportRevenueAmount",
        "projectionVersion", "sourceUpdatedAt", "generatedAt",
        "createdAt", "updatedAt"
      )
      SELECT gen_random_uuid()::text, CAST(${dateKey} AS date), 'STORE',
        COALESCE(o.store_code, r.store_code), COALESCE(o.store_code, r.store_code),
        COALESCE(o.total_orders, 0), COALESCE(o.reported_orders, 0),
        COALESCE(r.total_reports, 0), COALESCE(r.not_purchased, 0),
        COALESCE(o.order_revenue, 0), COALESCE(r.report_revenue, 0),
        ${version}, ${sourceUpdatedAt}, ${generatedAt}, ${generatedAt}, ${generatedAt}
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
          TRIM(COALESCE("sourceUserId", LOWER("sourceUserEmail"),
            LOWER("consultantEmail"), LOWER("sellerEmail"), '')) AS user_key,
          UPPER(TRIM(COALESCE("storeCode", ''))) AS store_code,
          COUNT(*)::int AS total_orders,
          COUNT(*) FILTER (WHERE "hasValidReport")::int AS reported_orders,
          COALESCE(SUM(GREATEST(COALESCE("grandTotal", 0), 0)), 0) AS order_revenue
        FROM "HomeSummaryOrderFact"
        WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)
        GROUP BY 1, 2
      ), report_metrics AS (
        SELECT
          TRIM(COALESCE("createdByUserId", LOWER("createdByEmail"), '')) AS user_key,
          UPPER(TRIM(COALESCE("storeCode", ''))) AS store_code,
          COUNT(*)::int AS total_reports,
          COUNT(*) FILTER (WHERE "reportType" = 'NOT_PURCHASED')::int AS not_purchased,
          COALESCE(SUM(GREATEST(COALESCE("revenue", 0), 0)), 0) AS report_revenue
        FROM "HomeSummaryReportFact"
        WHERE ("summaryDate" + INTERVAL '7 hours')::date = CAST(${dateKey} AS date)
        GROUP BY 1, 2
      )
      INSERT INTO "HomeSummaryDailyAggregate" (
        "id", "summaryDate", "dimensionType", "dimensionKey", "storeCode",
        "totalOrders", "reportedOrders", "totalReports",
        "notPurchasedReports", "orderRevenueAmount", "reportRevenueAmount",
        "projectionVersion", "sourceUpdatedAt", "generatedAt",
        "createdAt", "updatedAt"
      )
      SELECT gen_random_uuid()::text, CAST(${dateKey} AS date), 'USER_STORE',
        COALESCE(o.user_key, r.user_key), COALESCE(o.store_code, r.store_code),
        COALESCE(o.total_orders, 0), COALESCE(o.reported_orders, 0),
        COALESCE(r.total_reports, 0), COALESCE(r.not_purchased, 0),
        COALESCE(o.order_revenue, 0), COALESCE(r.report_revenue, 0),
        ${version}, ${sourceUpdatedAt}, ${generatedAt}, ${generatedAt}, ${generatedAt}
      FROM order_metrics o
      FULL OUTER JOIN report_metrics r
        ON r.user_key = o.user_key AND r.store_code = o.store_code
      WHERE COALESCE(o.user_key, r.user_key) <> ''
        AND COALESCE(o.store_code, r.store_code) <> ''
    `);
  }

  private async publishPendingEvents() {
    const events = await this.prisma.domainOutboxEvent.findMany({
      where: {
        eventType: HOME_SUMMARY_UPDATED_EVENT,
        publishedAt: null,
        availableAt: { lte: new Date() },
      },
      orderBy: [{ occurredAt: 'asc' }],
      take: OUTBOX_BATCH_SIZE,
    });
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
          where: { id: event.id, publishedAt: null },
          data: {
            publishedAt: new Date(),
            attempts: { increment: 1 },
            lastError: null,
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
          where: { id: event.id, publishedAt: null },
          data: {
            attempts,
            availableAt: new Date(Date.now() + retrySeconds * 1000),
            lastError: sanitizedError,
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
            sourceUpdatedAt: true,
            generatedAt: true,
          },
        }),
        this.prisma.homeSummaryProjectionQueue.findMany({
          where: {
            summaryDate: { in: dateValues },
            dimensionType: 'GLOBAL',
            dimensionKey: '',
            storeCode: '',
          },
          select: { summaryDate: true },
        }),
      ]);
      const stateByDate = new Map(
        states.map((state) => [this.dateKey(state.summaryDate), state]),
      );
      const queuedDates = new Set(
        queuedRows.map((row) => this.dateKey(row.summaryDate)),
      );
      datesToEnqueue = dates.filter((date) => {
        if (queuedDates.has(date)) {
          skippedQueued += 1;
          return false;
        }
        const state = stateByDate.get(date);
        const stable =
          state?.status === 'COMPLETE' &&
          state.generatedAt !== null &&
          state.sourceUpdatedAt !== null &&
          state.sourceUpdatedAt <= state.generatedAt;
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
