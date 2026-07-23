import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { safeLogError } from '../common/log-sanitizer';
import { PrismaService } from '../prisma/prisma.service';
import {
  MAP_VIETIN_BIGQUERY_BACKFILL_JOB_KEY,
  resolveMapVietinBigQueryConfig,
} from './map-vietin-bigquery.config';

type Checkpoint = {
  jobKey: string;
  status: string;
  upperBoundFirstSeenAt: Date;
  upperBoundTransactionId: string;
  lastFirstSeenAt: Date | null;
  lastTransactionId: string | null;
  claimToken: string | null;
  leaseExpiresAt: Date | null;
  pagesProcessed: number;
  rowsEnqueued: number;
};

type PageRow = { id: string; firstSeenAt: Date };

@Injectable()
export class MapVietinBigQueryBackfillService implements OnApplicationBootstrap {
  private readonly logger = new Logger(MapVietinBigQueryBackfillService.name);
  private readonly config = resolveMapVietinBigQueryConfig();
  private running = false;

  constructor(private readonly prisma: PrismaService) {}

  onApplicationBootstrap() {
    if (!this.config.backfillEnabled) {
      this.logger.log('MAP BigQuery backfill skipped: reason=disabled');
      return;
    }
    void this.runBackfill();
  }

  async runBackfill() {
    if (!this.config.backfillEnabled || this.running) {
      return { skipped: true };
    }
    this.running = true;
    const startedAt = Date.now();
    let claimToken: string | null = null;
    try {
      const claimed = await this.claimCheckpoint();
      if (!claimed) {
        this.logger.log(
          'MAP BigQuery backfill skipped: reason=another_instance_running',
        );
        return { skipped: true };
      }
      if (claimed.status === 'COMPLETE') {
        this.logger.log(
          `MAP BigQuery backfill skipped: reason=already_complete pages=${claimed.pagesProcessed} rows=${claimed.rowsEnqueued}`,
        );
        return { skipped: true };
      }
      claimToken = claimed.claimToken;
      if (!claimToken)
        throw new Error('Backfill checkpoint claim token missing');

      let checkpoint = claimed;
      this.logger.log(
        `MAP BigQuery backfill started: pageSize=${this.config.backfillPageSize} upperBound=${checkpoint.upperBoundFirstSeenAt.toISOString()}/${checkpoint.upperBoundTransactionId}`,
      );
      while (checkpoint.status !== 'COMPLETE') {
        checkpoint = await this.processPage(checkpoint, claimToken);
      }
      this.logger.log(
        `MAP BigQuery backfill succeeded: pages=${checkpoint.pagesProcessed} rows=${checkpoint.rowsEnqueued} durationMs=${Date.now() - startedAt}`,
      );
      return {
        skipped: false,
        pagesProcessed: checkpoint.pagesProcessed,
        rowsEnqueued: checkpoint.rowsEnqueued,
      };
    } catch (error) {
      const message = safeLogError(error, 500);
      if (claimToken) {
        await this.prisma
          .$executeRaw(
            Prisma.sql`
          UPDATE "MapVietinBigQueryBackfillCheckpoint"
          SET "status" = 'FAILED',
              "lastError" = ${message},
              "claimToken" = NULL,
              "leaseExpiresAt" = NULL,
              "updatedAt" = CURRENT_TIMESTAMP
          WHERE "jobKey" = ${MAP_VIETIN_BIGQUERY_BACKFILL_JOB_KEY}
            AND "claimToken" = ${claimToken}
        `,
          )
          .catch(() => undefined);
      }
      this.logger.error(
        `MAP BigQuery backfill failed: durationMs=${Date.now() - startedAt} error=${message}`,
      );
      return { skipped: false, failed: true };
    } finally {
      this.running = false;
    }
  }

  private async claimCheckpoint(): Promise<Checkpoint | null> {
    return this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw(Prisma.sql`
        INSERT INTO "MapVietinBigQueryBackfillCheckpoint" (
          "jobKey", "status", "upperBoundFirstSeenAt", "upperBoundTransactionId"
        )
        SELECT
          ${MAP_VIETIN_BIGQUERY_BACKFILL_JOB_KEY},
          CASE WHEN latest."id" IS NULL THEN 'COMPLETE' ELSE 'PENDING' END,
          COALESCE(latest."firstSeenAt", CURRENT_TIMESTAMP),
          COALESCE(latest."id", '')
        FROM (SELECT 1) AS seed
        LEFT JOIN LATERAL (
          SELECT "id", "firstSeenAt"
          FROM "MapVietinTransaction"
          ORDER BY "firstSeenAt" DESC, "id" DESC
          LIMIT 1
        ) AS latest ON TRUE
        ON CONFLICT ("jobKey") DO NOTHING
      `);
      const rows = await tx.$queryRaw<Checkpoint[]>(Prisma.sql`
        SELECT "jobKey", "status", "upperBoundFirstSeenAt", "upperBoundTransactionId",
               "lastFirstSeenAt", "lastTransactionId", "claimToken", "leaseExpiresAt",
               "pagesProcessed", "rowsEnqueued"
        FROM "MapVietinBigQueryBackfillCheckpoint"
        WHERE "jobKey" = ${MAP_VIETIN_BIGQUERY_BACKFILL_JOB_KEY}
        FOR UPDATE
      `);
      const checkpoint = rows[0];
      if (!checkpoint) throw new Error('Backfill checkpoint was not created');
      if (checkpoint.status === 'COMPLETE') return checkpoint;
      if (
        checkpoint.claimToken &&
        checkpoint.leaseExpiresAt &&
        checkpoint.leaseExpiresAt.getTime() > Date.now()
      ) {
        return null;
      }
      const tokenRows = await tx.$queryRaw<Array<{ claimToken: string }>>(
        Prisma.sql`
          UPDATE "MapVietinBigQueryBackfillCheckpoint"
          SET "status" = 'RUNNING',
              "claimToken" = gen_random_uuid()::text,
              "leaseExpiresAt" = CURRENT_TIMESTAMP + (${this.config.backfillLeaseSeconds} * INTERVAL '1 second'),
              "lastError" = NULL,
              "updatedAt" = CURRENT_TIMESTAMP
          WHERE "jobKey" = ${MAP_VIETIN_BIGQUERY_BACKFILL_JOB_KEY}
          RETURNING "claimToken"
        `,
      );
      return {
        ...checkpoint,
        status: 'RUNNING',
        claimToken: tokenRows[0].claimToken,
      };
    });
  }

  private async processPage(
    checkpoint: Checkpoint,
    claimToken: string,
  ): Promise<Checkpoint> {
    return this.prisma.$transaction(async (tx) => {
      const cursorClause =
        checkpoint.lastFirstSeenAt && checkpoint.lastTransactionId
          ? Prisma.sql`
              AND ("firstSeenAt" > ${checkpoint.lastFirstSeenAt}
                OR ("firstSeenAt" = ${checkpoint.lastFirstSeenAt}
                  AND "id" > ${checkpoint.lastTransactionId}))
            `
          : Prisma.empty;
      const rows = await tx.$queryRaw<PageRow[]>(Prisma.sql`
        SELECT "id", "firstSeenAt"
        FROM "MapVietinTransaction"
        WHERE ("firstSeenAt" < ${checkpoint.upperBoundFirstSeenAt}
          OR ("firstSeenAt" = ${checkpoint.upperBoundFirstSeenAt}
            AND "id" <= ${checkpoint.upperBoundTransactionId}))
          ${cursorClause}
        ORDER BY "firstSeenAt" ASC, "id" ASC
        LIMIT ${this.config.backfillPageSize}
      `);
      if (rows.length > 0) {
        for (const row of rows) {
          await tx.$queryRaw(Prisma.sql`
            SELECT opshub_enqueue_map_vietin_bigquery_transaction(${row.id})
          `);
        }
      }
      const last = rows.at(-1);
      const complete = rows.length < this.config.backfillPageSize;
      const updated = await tx.$queryRaw<Checkpoint[]>(Prisma.sql`
        UPDATE "MapVietinBigQueryBackfillCheckpoint"
        SET "status" = ${complete ? 'COMPLETE' : 'RUNNING'},
            "lastFirstSeenAt" = ${last?.firstSeenAt ?? checkpoint.lastFirstSeenAt},
            "lastTransactionId" = ${last?.id ?? checkpoint.lastTransactionId},
            "pagesProcessed" = "pagesProcessed" + 1,
            "rowsEnqueued" = "rowsEnqueued" + ${rows.length},
            "claimToken" = ${complete ? null : claimToken},
            "leaseExpiresAt" = ${complete ? null : new Date(Date.now() + this.config.backfillLeaseSeconds * 1000)},
            "updatedAt" = CURRENT_TIMESTAMP
        WHERE "jobKey" = ${MAP_VIETIN_BIGQUERY_BACKFILL_JOB_KEY}
          AND "claimToken" = ${claimToken}
        RETURNING "jobKey", "status", "upperBoundFirstSeenAt", "upperBoundTransactionId",
                  "lastFirstSeenAt", "lastTransactionId", "claimToken", "leaseExpiresAt",
                  "pagesProcessed", "rowsEnqueued"
      `);
      if (!updated[0]) throw new Error('Backfill checkpoint lease was lost');
      this.logger.log(
        `MAP BigQuery backfill page succeeded: count=${rows.length} complete=${complete} pages=${updated[0].pagesProcessed} rows=${updated[0].rowsEnqueued}`,
      );
      return updated[0];
    });
  }
}
