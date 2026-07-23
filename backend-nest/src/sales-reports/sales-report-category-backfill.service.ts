import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service';
import { SalesReportCategoriesService } from './sales-report-categories.service';
import { SalesReportErpService } from './sales-report-erp.service';
import { SalesReportsBigQuerySyncService } from './sales-reports-bigquery-sync.service';

export type SalesReportCategoryBackfillCandidate = {
  id: string;
  salesReportId: string;
  sellerSku: string | null;
  storeCode: string | null;
  reportDate: Date | null;
};

export type SalesReportCategoryBackfillPlan = {
  version: 2;
  createdAt: string;
  pageSize: number;
  candidateCount: number;
  lastCandidateId: string | null;
  affectedDates: string[];
  planHash: string;
};

export type SalesReportCategoryBackfillDbResult = {
  updated: number;
  stale: number;
  skippedMissingSku: number;
  skippedMissingStore: number;
  unresolved: number;
  affectedReportIds: string[];
  affectedDates: string[];
};

const MAX_PAGE_SIZE = 500;
const MAX_LISTING_BATCH_SIZE = 50;

@Injectable()
export class SalesReportCategoryBackfillService {
  private readonly logger = new Logger(SalesReportCategoryBackfillService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly erp: SalesReportErpService,
    private readonly categories: SalesReportCategoriesService,
    private readonly bigQuerySync: SalesReportsBigQuerySyncService,
  ) {}

  async buildPlan(pageSize = 100): Promise<SalesReportCategoryBackfillPlan> {
    const normalizedPageSize = Math.max(
      1,
      Math.min(MAX_PAGE_SIZE, Math.trunc(Number(pageSize) || 100)),
    );
    const snapshotCutoff = new Date();
    const scan = await this.scanCandidates(normalizedPageSize, {
      createdAtLte: snapshotCutoff,
    });
    const plan: SalesReportCategoryBackfillPlan = {
      version: 2,
      createdAt: snapshotCutoff.toISOString(),
      pageSize: normalizedPageSize,
      candidateCount: scan.count,
      lastCandidateId: scan.lastId,
      affectedDates: scan.affectedDates,
      planHash: scan.planHash,
    };
    this.logger.log(
      `Sales report category backfill plan built: candidates=${scan.count} lastCandidateId=${scan.lastId ?? 'none'} planHash=${plan.planHash}`,
    );
    return plan;
  }

  async *iterateCandidatePages(
    pageSize = 100,
    bounds: { createdAtLte?: Date; idLte?: string | null } = {},
  ): AsyncGenerator<SalesReportCategoryBackfillCandidate[], void, void> {
    const normalizedPageSize = Math.max(
      1,
      Math.min(MAX_PAGE_SIZE, Math.trunc(Number(pageSize) || 100)),
    );
    let lastId: string | undefined;
    for (;;) {
      const idBounds = {
        ...(lastId ? { gt: lastId } : {}),
        ...(bounds.idLte ? { lte: bounds.idLte } : {}),
      };
      const where: any = {
        categoryType: null,
        salesReport: {
          reportType: 'PURCHASED',
          erpExcludedAt: null,
        },
        ...(Object.keys(idBounds).length > 0 ? { id: idBounds } : {}),
        ...(bounds.createdAtLte
          ? { createdAt: { lte: bounds.createdAtLte } }
          : {}),
      };
      const rows = await this.prisma.salesReportOrderItem.findMany({
        where,
        orderBy: { id: 'asc' },
        take: normalizedPageSize,
        select: {
          id: true,
          salesReportId: true,
          sellerSku: true,
          salesReport: {
            select: {
              storeCode: true,
              erpOrderCreatedAt: true,
              submittedAt: true,
            },
          },
        },
      });
      if (rows.length === 0) break;
      const candidates: SalesReportCategoryBackfillCandidate[] = [];
      for (const row of rows) {
        candidates.push({
          id: row.id,
          salesReportId: row.salesReportId,
          sellerSku: row.sellerSku,
          storeCode: row.salesReport.storeCode,
          reportDate:
            row.salesReport.erpOrderCreatedAt ?? row.salesReport.submittedAt,
        });
      }
      yield candidates;
      lastId = rows[rows.length - 1]?.id;
      if (rows.length < normalizedPageSize) break;
    }
  }

  private async scanCandidates(
    pageSize: number,
    bounds: { createdAtLte?: Date; idLte?: string | null } = {},
  ) {
    const hasher = createHash('sha256');
    let count = 0;
    let lastId: string | null = null;
    const affectedDates = new Set<string>();
    for await (const page of this.iterateCandidatePages(pageSize, bounds)) {
      for (const candidate of page) {
        hasher.update(`${this.candidateHashInput(candidate)}\n`);
        count += 1;
        lastId = candidate.id;
        const date = this.vietnamDate(candidate.reportDate);
        if (date) affectedDates.add(date);
      }
    }
    return {
      count,
      lastId,
      affectedDates: Array.from(affectedDates).sort(),
      planHash: hasher.digest('hex'),
    };
  }

  async verifyPlan(plan: SalesReportCategoryBackfillPlan) {
    const snapshotCutoff = new Date(plan.createdAt);
    if (Number.isNaN(snapshotCutoff.getTime())) {
      throw new Error('Sales report category backfill plan cutoff is invalid');
    }
    const snapshot = await this.scanCandidates(plan.pageSize, {
      createdAtLte: snapshotCutoff,
      idLte: plan.lastCandidateId,
    });
    if (
      snapshot.count !== plan.candidateCount ||
      snapshot.lastId !== plan.lastCandidateId ||
      snapshot.planHash !== plan.planHash
    ) {
      throw new Error(
        `Sales report category backfill plan changed: expected=${plan.planHash} actual=${snapshot.planHash}`,
      );
    }
    return snapshot;
  }

  async applyDatabase(
    plan: SalesReportCategoryBackfillPlan,
    batchSize = 50,
    options: { verifyPlan?: boolean; resume?: boolean } = {},
  ): Promise<SalesReportCategoryBackfillDbResult> {
    const normalizedBatchSize = Math.max(
      1,
      Math.min(MAX_LISTING_BATCH_SIZE, Math.trunc(Number(batchSize) || 50)),
    );
    const result: SalesReportCategoryBackfillDbResult = {
      updated: 0,
      stale: 0,
      skippedMissingSku: 0,
      skippedMissingStore: 0,
      unresolved: 0,
      affectedReportIds: [],
      affectedDates: [],
    };
    const affectedReportIds = new Set<string>();
    const affectedDates = new Set<string>(
      options.resume ? plan.affectedDates : [],
    );
    if (options.verifyPlan !== false) await this.verifyPlan(plan);
    const snapshotCutoff = new Date(plan.createdAt);
    for await (const page of this.iterateCandidatePages(plan.pageSize, {
      createdAtLte: snapshotCutoff,
      idLte: plan.lastCandidateId,
    })) {
      const eligibleByStore = new Map<
        string,
        SalesReportCategoryBackfillCandidate[]
      >();
      for (const candidate of page) {
        if (!candidate.sellerSku?.trim()) {
          result.skippedMissingSku += 1;
          continue;
        }
        if (!candidate.storeCode?.trim()) {
          result.skippedMissingStore += 1;
          continue;
        }
        const rows = eligibleByStore.get(candidate.storeCode) ?? [];
        rows.push(candidate);
        eligibleByStore.set(candidate.storeCode, rows);
      }
      for (const [storeCode, candidates] of eligibleByStore) {
        for (
          let offset = 0;
          offset < candidates.length;
          offset += normalizedBatchSize
        ) {
          await this.applyCandidateBatch(
            candidates.slice(offset, offset + normalizedBatchSize),
            storeCode,
            result,
            affectedReportIds,
            affectedDates,
          );
        }
      }
    }
    result.affectedReportIds = Array.from(affectedReportIds).sort();
    result.affectedDates = Array.from(affectedDates).sort();
    this.logger.log(
      `Sales report category backfill database apply succeeded: planHash=${plan.planHash} updated=${result.updated} stale=${result.stale} unresolved=${result.unresolved} missingSku=${result.skippedMissingSku} missingStore=${result.skippedMissingStore} affectedReports=${result.affectedReportIds.length} affectedDates=${result.affectedDates.length}`,
    );
    return result;
  }

  private async applyCandidateBatch(
    batch: SalesReportCategoryBackfillCandidate[],
    storeCode: string,
    result: SalesReportCategoryBackfillDbResult,
    affectedReportIds: Set<string>,
    affectedDates: Set<string>,
  ) {
    const skuList = Array.from(
      new Set(
        batch
          .map((candidate) => candidate.sellerSku?.trim())
          .filter((sku): sku is string => Boolean(sku)),
      ),
    );
    let listingCategories: Map<string, unknown[]>;
    try {
      listingCategories = await this.erp.lookupListingCategories(
        skuList,
        storeCode,
      );
    } catch (error) {
      result.unresolved += batch.length;
      this.logger.warn(
        `Sales report category backfill Listing lookup failed: store=${storeCode} requested=${batch.length} errorType=${this.errorType(error)}`,
      );
      return;
    }
    const updates: Array<{
      candidate: SalesReportCategoryBackfillCandidate;
      categoryType: string;
    }> = [];
    for (const candidate of batch) {
      const categories = listingCategories.get(candidate.sellerSku!.trim());
      let categoryType: string | null;
      try {
        categoryType = await this.categories.matchTypeFromListingCategories(
          categories ?? [],
        );
      } catch (error) {
        result.unresolved += 1;
        this.logger.warn(
          `Sales report category backfill category mapping failed: itemId=${candidate.id} errorType=${this.errorType(error)}`,
        );
        continue;
      }
      if (!categoryType) {
        result.unresolved += 1;
        continue;
      }
      updates.push({ candidate, categoryType });
    }
    if (updates.length === 0) return;

    const writeResults = await this.prisma.$transaction(
      updates.map(({ candidate, categoryType }) =>
        this.prisma.salesReportOrderItem.updateMany({
          where: {
            id: candidate.id,
            salesReportId: candidate.salesReportId,
            sellerSku: candidate.sellerSku,
            categoryType: null,
          },
          data: { categoryType },
        }),
      ),
    );
    const changed = updates.filter(
      (_, index) => writeResults[index]?.count === 1,
    );
    result.updated += changed.length;
    result.stale += updates.length - changed.length;
    for (const { candidate } of changed) {
      affectedReportIds.add(candidate.salesReportId);
      const date = this.vietnamDate(candidate.reportDate);
      if (date) affectedDates.add(date);
    }
    if (changed.length > 0) {
      const verification = await this.prisma.salesReportOrderItem.findMany({
        where: { id: { in: changed.map(({ candidate }) => candidate.id) } },
        select: { id: true, categoryType: true },
      });
      const verified = new Map(
        verification.map((row) => [row.id, row.categoryType]),
      );
      if (
        changed.some(
          ({ candidate, categoryType }) =>
            verified.get(candidate.id) !== categoryType,
        )
      ) {
        throw new Error(
          'Sales report category backfill post-update verification failed',
        );
      }
    }
  }

  async enqueueHomeProjection(dates: string[]) {
    const uniqueDates = Array.from(new Set(dates)).sort();
    for (const date of uniqueDates) {
      await this.prisma.$executeRaw(Prisma.sql`
        SELECT opshub_enqueue_home_summary_projection_kind(
          CAST(${date} AS date), 'SALES_REPORT', 'SALES'
        )
      `);
    }
    this.logger.log(
      `Sales report category backfill Home enqueue succeeded: dates=${uniqueDates.length}`,
    );
    return uniqueDates;
  }

  async syncBigQuery() {
    const result = await this.bigQuerySync.syncAll(
      'sales_report_category_backfill',
      { force: true },
    );
    this.logger.log(
      `Sales report category backfill BigQuery sync succeeded: reports=${result.reportRows} items=${result.itemRows} durationMs=${result.durationMs}`,
    );
    return result;
  }

  hashCandidates(candidates: SalesReportCategoryBackfillCandidate[]) {
    const hasher = createHash('sha256');
    for (const candidate of candidates) {
      hasher.update(`${this.candidateHashInput(candidate)}\n`);
    }
    return hasher.digest('hex');
  }

  private candidateHashInput(candidate: SalesReportCategoryBackfillCandidate) {
    return [
      candidate.id,
      candidate.salesReportId,
      candidate.sellerSku ?? '',
      candidate.storeCode ?? '',
      candidate.reportDate?.toISOString() ?? '',
    ].join('|');
  }

  private vietnamDate(value: Date | null) {
    if (!value || Number.isNaN(value.getTime())) return null;
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Ho_Chi_Minh',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(value);
    const values = Object.fromEntries(
      parts
        .filter((part) => part.type !== 'literal')
        .map((part) => [part.type, part.value]),
    );
    return `${values.year}-${values.month}-${values.day}`;
  }

  private errorType(error: unknown) {
    return error instanceof Error ? error.constructor.name : 'UnknownError';
  }
}
