import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { safeLogError } from '../common/log-sanitizer';
import { PrismaService } from '../prisma/prisma.service';
import {
  MAP_VIETIN_BIGQUERY_EVENT_TYPE,
  resolveMapVietinBigQueryConfig,
} from './map-vietin-bigquery.config';
import { MapVietinBigQueryRowMapper } from './map-vietin-bigquery-row.mapper';
import { MapVietinBigQueryStorageWriterService } from './map-vietin-bigquery-storage-writer.service';
import {
  ClaimedMapVietinBigQueryEvent,
  MapVietinBigQueryRow,
} from './map-vietin-bigquery.types';

type PreparedEvent = {
  event: ClaimedMapVietinBigQueryEvent;
  row: MapVietinBigQueryRow;
};

@Injectable()
export class MapVietinBigQueryWorkerService
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(MapVietinBigQueryWorkerService.name);
  private readonly config = resolveMapVietinBigQueryConfig();
  private running = false;
  private destroyed = false;
  private timer: NodeJS.Timeout | null = null;
  private lastMetricsAt = 0;

  constructor(
    private readonly prisma: PrismaService,
    private readonly writer: MapVietinBigQueryStorageWriterService,
    private readonly mapper: MapVietinBigQueryRowMapper,
  ) {}

  onModuleInit() {
    if (!this.config.enabled) {
      this.logger.log('MAP BigQuery worker skipped: reason=disabled');
      return;
    }
    this.logger.log(
      `MAP BigQuery worker started: batchSize=${this.config.batchSize} pollIntervalMs=${this.config.pollIntervalMs} leaseSeconds=${this.config.leaseSeconds} maxAttempts=${this.config.maxAttempts}`,
    );
    void this.runCycle('startup').finally(() => this.scheduleNext());
  }

  onModuleDestroy() {
    this.destroyed = true;
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
  }

  async runCycle(source = 'manual') {
    if (!this.config.enabled || this.destroyed || this.running) return;
    this.running = true;
    const startedAt = Date.now();
    try {
      const recoveredDeadLetters = await this.deadLetterExpiredClaims();
      const events = await this.claimEvents();
      if (events.length === 0) {
        await this.logMetricsIfDue(recoveredDeadLetters);
        return;
      }
      this.logger.log(
        `MAP BigQuery batch started: source=${source} batch=${events.length}`,
      );

      const prepared: PreparedEvent[] = [];
      const invalid: Array<{
        event: ClaimedMapVietinBigQueryEvent;
        reason: string;
      }> = [];
      for (const event of events) {
        try {
          prepared.push({ event, row: this.mapper.toRow(event) });
        } catch (error) {
          invalid.push({ event, reason: safeLogError(error) });
        }
      }
      if (invalid.length > 0) await this.failEvents(invalid);

      let written = 0;
      let failed = invalid.length;
      if (prepared.length > 0) {
        try {
          const result = await this.writer.appendRows(
            prepared.map((item) => item.row),
          );
          const successful = result.successfulIndexes
            .map((index) => prepared[index]?.event)
            .filter(Boolean) as ClaimedMapVietinBigQueryEvent[];
          const rowFailures = result.failed
            .map((item) => ({
              event: prepared[item.index]?.event,
              reason: item.reason,
            }))
            .filter(
              (
                item,
              ): item is {
                event: ClaimedMapVietinBigQueryEvent;
                reason: string;
              } => Boolean(item.event),
            );
          if (successful.length > 0) await this.ackEvents(successful);
          if (rowFailures.length > 0) await this.failEvents(rowFailures);
          written += successful.length;
          failed += rowFailures.length;
        } catch (error) {
          const reason = safeLogError(error);
          await this.failEvents(
            prepared.map((item) => ({ event: item.event, reason })),
          );
          failed += prepared.length;
          this.logger.warn(
            `MAP BigQuery append failed: source=${source} batch=${prepared.length} durationMs=${Date.now() - startedAt} error=${reason}`,
          );
        }
      }

      this.logger.log(
        `MAP BigQuery batch succeeded: source=${source} claimed=${events.length} written=${written} failed=${failed} durationMs=${Date.now() - startedAt}`,
      );
      await this.logMetricsIfDue(recoveredDeadLetters);
    } catch (error) {
      this.logger.error(
        `MAP BigQuery cycle failed: source=${source} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
    } finally {
      this.running = false;
    }
  }

  private scheduleNext() {
    if (this.destroyed || !this.config.enabled) return;
    this.timer = setTimeout(() => {
      void this.runCycle('poll').finally(() => this.scheduleNext());
    }, this.config.pollIntervalMs);
    this.timer.unref?.();
  }

  private async claimEvents(): Promise<ClaimedMapVietinBigQueryEvent[]> {
    const rows = await this.prisma.$queryRaw<ClaimedMapVietinBigQueryEvent[]>(
      Prisma.sql`
        WITH candidates AS (
          SELECT "id"
          FROM "DomainOutboxEvent"
          WHERE "eventType" = ${MAP_VIETIN_BIGQUERY_EVENT_TYPE}
            AND "publishedAt" IS NULL
            AND "deadLetteredAt" IS NULL
            AND "availableAt" <= CURRENT_TIMESTAMP
            AND ("claimToken" IS NULL OR "leaseExpiresAt" < CURRENT_TIMESTAMP)
            AND "attempts" < ${this.config.maxAttempts}
          ORDER BY "availableAt" ASC, "occurredAt" ASC
          FOR UPDATE SKIP LOCKED
          LIMIT ${this.config.batchSize}
        )
        UPDATE "DomainOutboxEvent" AS event
        SET "claimedAt" = CURRENT_TIMESTAMP,
            "claimToken" = gen_random_uuid()::text,
            "leaseExpiresAt" = CURRENT_TIMESTAMP
              + (${this.config.leaseSeconds} * INTERVAL '1 second'),
            "attempts" = event."attempts" + 1,
            "updatedAt" = CURRENT_TIMESTAMP
        FROM candidates
        WHERE event."id" = candidates."id"
        RETURNING event."id", event."aggregateId", event."schemaVersion",
                  event."payload", event."occurredAt", event."attempts",
                  event."claimToken"
      `,
    );
    return rows.map((row) => ({
      ...row,
      occurredAt: new Date(row.occurredAt),
    }));
  }

  private async ackEvents(events: ClaimedMapVietinBigQueryEvent[]) {
    const claimed = events.map(
      (event) =>
        Prisma.sql`(CAST(${event.id} AS text), CAST(${event.claimToken} AS text))`,
    );
    await this.prisma.$executeRaw(Prisma.sql`
      UPDATE "DomainOutboxEvent" AS event
      SET "publishedAt" = CURRENT_TIMESTAMP,
          "claimedAt" = NULL,
          "claimToken" = NULL,
          "leaseExpiresAt" = NULL,
          "lastError" = NULL,
          "updatedAt" = CURRENT_TIMESTAMP
      FROM (VALUES ${Prisma.join(claimed)}) AS claimed("id", "claimToken")
      WHERE event."id" = claimed."id"
        AND event."claimToken" = claimed."claimToken"
        AND event."eventType" = ${MAP_VIETIN_BIGQUERY_EVENT_TYPE}
        AND event."publishedAt" IS NULL
        AND event."deadLetteredAt" IS NULL
    `);
  }

  private async failEvents(
    failures: Array<{
      event: ClaimedMapVietinBigQueryEvent;
      reason: string;
    }>,
  ) {
    if (failures.length === 0) return;
    const now = Date.now();
    let deadLetters = 0;
    const values = failures.map(({ event, reason }) => {
      const deadLettered = event.attempts >= this.config.maxAttempts;
      if (deadLettered) deadLetters += 1;
      const availableAt = new Date(
        now + (deadLettered ? 0 : this.retryDelayMs(event.attempts)),
      );
      const deadLetteredAt = deadLettered ? new Date(now) : null;
      return Prisma.sql`(
        CAST(${event.id} AS text),
        CAST(${event.claimToken} AS text),
        CAST(${availableAt} AS timestamp),
        CAST(${deadLetteredAt} AS timestamp),
        CAST(${safeLogError(reason, 500)} AS text)
      )`;
    });
    await this.prisma.$executeRaw(Prisma.sql`
      UPDATE "DomainOutboxEvent" AS event
      SET "availableAt" = failed."availableAt",
          "deadLetteredAt" = failed."deadLetteredAt",
          "lastError" = failed."lastError",
          "claimedAt" = NULL,
          "claimToken" = NULL,
          "leaseExpiresAt" = NULL,
          "updatedAt" = CURRENT_TIMESTAMP
      FROM (VALUES ${Prisma.join(values)}) AS failed(
        "id", "claimToken", "availableAt", "deadLetteredAt", "lastError"
      )
      WHERE event."id" = failed."id"
        AND event."claimToken" = failed."claimToken"
        AND event."eventType" = ${MAP_VIETIN_BIGQUERY_EVENT_TYPE}
        AND event."publishedAt" IS NULL
        AND event."deadLetteredAt" IS NULL
    `);
    this.logger.warn(
      `MAP BigQuery batch retry scheduled: failed=${failures.length} deadLetters=${deadLetters} retrying=${failures.length - deadLetters}`,
    );
  }

  private retryDelayMs(attempts: number) {
    const exponent = Math.min(Math.max(attempts - 1, 0), 20);
    const baseDelay = Math.min(
      this.config.retryMaxMs,
      this.config.retryBaseMs * 2 ** exponent,
    );
    const jitterLimit = Math.max(
      1,
      Math.min(this.config.retryBaseMs, baseDelay),
    );
    return Math.min(
      this.config.retryMaxMs,
      baseDelay + Math.floor(Math.random() * jitterLimit),
    );
  }

  private async deadLetterExpiredClaims() {
    return this.prisma.$executeRaw(Prisma.sql`
      UPDATE "DomainOutboxEvent"
      SET "deadLetteredAt" = CURRENT_TIMESTAMP,
          "claimToken" = NULL,
          "claimedAt" = NULL,
          "leaseExpiresAt" = NULL,
          "lastError" = 'retry_exhausted_after_lease_expiry',
          "updatedAt" = CURRENT_TIMESTAMP
      WHERE "eventType" = ${MAP_VIETIN_BIGQUERY_EVENT_TYPE}
        AND "publishedAt" IS NULL
        AND "deadLetteredAt" IS NULL
        AND "attempts" >= ${this.config.maxAttempts}
        AND "leaseExpiresAt" < CURRENT_TIMESTAMP
    `);
  }

  private async logMetricsIfDue(recoveredDeadLetters: number) {
    const now = Date.now();
    if (now - this.lastMetricsAt < this.config.metricsIntervalMs) return;
    this.lastMetricsAt = now;
    const [metrics] = await this.prisma.$queryRaw<
      Array<{
        pending: number;
        deadLetters: number;
        oldestOccurredAt: Date | null;
      }>
    >(Prisma.sql`
      SELECT
        COUNT(*) FILTER (
          WHERE "publishedAt" IS NULL AND "deadLetteredAt" IS NULL
        )::int AS "pending",
        COUNT(*) FILTER (WHERE "deadLetteredAt" IS NOT NULL)::int AS "deadLetters",
        MIN("occurredAt") FILTER (
          WHERE "publishedAt" IS NULL AND "deadLetteredAt" IS NULL
        ) AS "oldestOccurredAt"
      FROM "DomainOutboxEvent"
      WHERE "eventType" = ${MAP_VIETIN_BIGQUERY_EVENT_TYPE}
    `);
    const oldestLagMs = metrics?.oldestOccurredAt
      ? Math.max(0, now - new Date(metrics.oldestOccurredAt).getTime())
      : 0;
    this.logger.log(
      `MAP BigQuery metrics: pending=${metrics?.pending || 0} oldestLagMs=${oldestLagMs} deadLetters=${metrics?.deadLetters || 0} recoveredDeadLetters=${recoveredDeadLetters}`,
    );
  }
}
