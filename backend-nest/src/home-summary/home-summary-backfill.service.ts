import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { safeLogError } from '../common/log-sanitizer';
import { PrismaService } from '../prisma/prisma.service';
import { SalesReportsService } from '../sales-reports/sales-reports.service';

const BACKFILL_JOB_KEY = 'home-summary-erp-90d-v1';
const BACKFILL_PAGE_SIZE = 50;
const BACKFILL_PAGE_DELAY_MS = 1000;
const BACKFILL_RETRY_DELAYS_MS = [2000, 4000, 8000, 16000, 30000];

@Injectable()
export class HomeSummaryBackfillService implements OnApplicationBootstrap {
  private readonly logger = new Logger(HomeSummaryBackfillService.name);
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly salesReports: SalesReportsService,
  ) {}

  onApplicationBootstrap() {
    if (!this.enabled()) {
      this.logger.log('Home ERP backfill skipped: reason=disabled');
      return;
    }
    void this.runBackfill();
  }

  async runBackfill() {
    if (this.running) {
      this.logger.warn('Home ERP backfill skipped: reason=already_running');
      return { skipped: true };
    }
    this.running = true;
    const startedAt = Date.now();
    try {
      let checkpoint = await this.ensureCheckpoint();
      if (checkpoint.status === 'COMPLETE') {
        this.logger.log(
          `Home ERP backfill skipped: reason=already_complete pages=${checkpoint.pagesProcessed} rows=${checkpoint.rowsProcessed}`,
        );
        return { skipped: true };
      }
      await this.prisma.erpOrderCacheBackfillCheckpoint.update({
        where: { jobKey: BACKFILL_JOB_KEY },
        data: { status: 'RUNNING', lastError: null },
      });
      this.logger.log(
        `Home ERP backfill started: startDate=${this.dateKey(checkpoint.startDate)} endDate=${this.dateKey(checkpoint.endDate)} currentDate=${this.dateKey(checkpoint.currentDate)} nextOffset=${checkpoint.nextOffset} pageSize=${BACKFILL_PAGE_SIZE}`,
      );

      let previousPageFingerprint: string | null = null;
      while (checkpoint.currentDate <= checkpoint.endDate) {
        const date = this.dateKey(checkpoint.currentDate);
        const pageOffset = checkpoint.nextOffset;
        const result = await this.fetchPageWithRetry(date, pageOffset);
        const fingerprint = result.orderCodes
          .map((value) =>
            String(value ?? '')
              .trim()
              .toUpperCase(),
          )
          .filter(Boolean)
          .sort()
          .join('|');
        const providerIgnoredOffset: boolean =
          checkpoint.nextOffset > 0 &&
          fingerprint.length > 0 &&
          fingerprint === previousPageFingerprint;
        const dateComplete: boolean =
          result.count < BACKFILL_PAGE_SIZE || providerIgnoredOffset;
        const nextDate = new Date(checkpoint.currentDate);
        if (dateComplete) nextDate.setUTCDate(nextDate.getUTCDate() + 1);
        const nextOffset = dateComplete
          ? 0
          : checkpoint.nextOffset + BACKFILL_PAGE_SIZE;
        checkpoint = await this.prisma.erpOrderCacheBackfillCheckpoint.update({
          where: { jobKey: BACKFILL_JOB_KEY },
          data: {
            currentDate: dateComplete ? nextDate : checkpoint.currentDate,
            nextOffset,
            status: 'RUNNING',
            pagesProcessed: { increment: 1 },
            rowsProcessed: { increment: result.count },
            lastError: providerIgnoredOffset
              ? 'ERP không áp dụng offset; đã giữ trang đầu và chuyển sang ngày kế tiếp.'
              : null,
          },
        });
        this.logger.log(
          `Home ERP backfill page succeeded: date=${date} offset=${pageOffset} count=${result.count} dateComplete=${dateComplete} providerIgnoredOffset=${providerIgnoredOffset} pages=${checkpoint.pagesProcessed} rows=${checkpoint.rowsProcessed}`,
        );
        previousPageFingerprint = dateComplete ? null : fingerprint;
        if (checkpoint.currentDate > checkpoint.endDate) break;
        await this.delay(BACKFILL_PAGE_DELAY_MS);
      }

      checkpoint = await this.prisma.erpOrderCacheBackfillCheckpoint.update({
        where: { jobKey: BACKFILL_JOB_KEY },
        data: { status: 'COMPLETE', nextOffset: 0, lastError: null },
      });
      this.logger.log(
        `Home ERP backfill succeeded: pages=${checkpoint.pagesProcessed} rows=${checkpoint.rowsProcessed} durationMs=${Date.now() - startedAt}`,
      );
      return {
        skipped: false,
        pagesProcessed: checkpoint.pagesProcessed,
        rowsProcessed: checkpoint.rowsProcessed,
      };
    } catch (error) {
      const sanitizedError = safeLogError(error).slice(0, 500);
      await this.prisma.erpOrderCacheBackfillCheckpoint
        .updateMany({
          where: { jobKey: BACKFILL_JOB_KEY },
          data: { status: 'FAILED', lastError: sanitizedError },
        })
        .catch(() => undefined);
      this.logger.error(
        `Home ERP backfill failed: durationMs=${Date.now() - startedAt} error=${sanitizedError}`,
      );
      return { skipped: false, failed: true };
    } finally {
      this.running = false;
    }
  }

  private async fetchPageWithRetry(date: string, offset: number) {
    let lastError: unknown;
    for (
      let attempt = 0;
      attempt <= BACKFILL_RETRY_DELAYS_MS.length;
      attempt += 1
    ) {
      try {
        return await this.salesReports.syncErpOrderCachePage({
          date,
          limit: BACKFILL_PAGE_SIZE,
          offset,
          source: 'home_projection_backfill',
        });
      } catch (error) {
        lastError = error;
        if (attempt >= BACKFILL_RETRY_DELAYS_MS.length) break;
        const delayMs = BACKFILL_RETRY_DELAYS_MS[attempt];
        this.logger.warn(
          `Home ERP backfill page retry scheduled: date=${date} offset=${offset} attempt=${attempt + 1} delayMs=${delayMs} errorType=${error instanceof Error ? error.name : typeof error}`,
        );
        await this.delay(delayMs);
      }
    }
    throw lastError instanceof Error
      ? lastError
      : new Error('ERP backfill page failed');
  }

  private async ensureCheckpoint() {
    const existing =
      await this.prisma.erpOrderCacheBackfillCheckpoint.findUnique({
        where: { jobKey: BACKFILL_JOB_KEY },
      });
    if (existing) return existing;
    const endDate = this.dateOnlyUtc(this.vietnamDateKey(new Date()));
    const startDate = new Date(endDate);
    startDate.setUTCDate(startDate.getUTCDate() - (this.days() - 1));
    return this.prisma.erpOrderCacheBackfillCheckpoint.create({
      data: {
        jobKey: BACKFILL_JOB_KEY,
        startDate,
        endDate,
        currentDate: startDate,
        nextOffset: 0,
        status: 'PENDING',
      },
    });
  }

  private enabled() {
    return (
      String(process.env.HOME_SUMMARY_ERP_BACKFILL_ENABLED ?? 'false')
        .trim()
        .toLowerCase() === 'true'
    );
  }

  private days() {
    const value = Number(process.env.HOME_SUMMARY_ERP_BACKFILL_DAYS ?? 90);
    return Math.min(90, Math.max(1, Math.floor(value) || 90));
  }

  private delay(milliseconds: number) {
    return new Promise<void>((resolve) => setTimeout(resolve, milliseconds));
  }

  private dateKey(value: Date) {
    return value.toISOString().slice(0, 10);
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
