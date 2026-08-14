import { Prisma } from '@prisma/client';
import type { PrismaService } from '../prisma/prisma.service';
import type { SalesReportSummaryScopeDescriptor } from '../sales-reports/sales-reports.service';
import type { SummaryDateRange } from './home-summary.service';

export const HOME_SALES_COMPARISON_METRIC_KEYS = [
  'totalRevenue',
  'totalOrders',
  'averageOrderValue',
  'completedRevenue',
  'pendingRevenue',
  'conversionRate',
  'businessCustomerRevenue',
  'personalCustomerRevenue',
  'examScorePromotionCount',
  'studentPromotionCount',
  'installmentNeedCount',
  'successfulInstallmentCount',
  'extendedInsuranceQuantity',
  'laptopQuantity',
  'pcQuantity',
  'assembledPcQuantity',
  'appleQuantity',
  'monitorQuantity',
  'printerQuantity',
  'accessoriesQuantity',
  'notPurchasedReports',
  'unreportedOrders',
  'reportedOrders',
  'coverageRate',
  'consultedSolutionRate',
  'experiencedRate',
  'zaloRate',
  'appDownloadRate',
] as const;

export type HomeSalesComparisonMetricKey =
  (typeof HOME_SALES_COMPARISON_METRIC_KEYS)[number];

export const CSV_SUPPORTED_COMPARISON_METRICS =
  new Set<HomeSalesComparisonMetricKey>([
    'totalRevenue',
    'totalOrders',
    'averageOrderValue',
    'extendedInsuranceQuantity',
    'laptopQuantity',
    'pcQuantity',
    'assembledPcQuantity',
    'appleQuantity',
    'monitorQuantity',
    'printerQuantity',
    'accessoriesQuantity',
  ]);

export const METRIC_COMPARISON_QUANTITY_KEYS = [
  'extendedInsuranceQuantity',
  'laptopQuantity',
  'pcQuantity',
  'assembledPcQuantity',
  'appleQuantity',
  'monitorQuantity',
  'printerQuantity',
  'accessoriesQuantity',
] as const;

export type HomeSummaryCsvComparison = {
  values: Record<HomeSalesComparisonMetricKey, number>;
  source: 'HYBRID_CSV';
  unavailable: Set<HomeSalesComparisonMetricKey>;
};

type HomeSummaryCsvComparisonCallbacks = {
  normalizedStoreCodes: (values: Array<string | null | undefined>) => string[];
  dateOnlyUtc: (value: string) => Date;
  dateOnlyKey: (value: Date) => string;
  rangeDateKeys: (startDate: string, endDate: string) => string[];
  personalEmail: (scope: SalesReportSummaryScopeDescriptor) => string | null;
  optionalText: (value: unknown, maxLength: number) => string | null;
};

/**
 * Owns active historical-import coverage and hybrid CSV/projection comparison
 * aggregation. HomeSummaryService keeps the stable comparison facade and
 * fallback/orchestration behavior.
 */
export class HomeSummaryCsvComparisonRuntime {
  constructor(
    private readonly prisma: PrismaService,
    private readonly callbacks: HomeSummaryCsvComparisonCallbacks,
  ) {}

  async overlayActiveCsvHistory(
    range: SummaryDateRange,
    scope: SalesReportSummaryScopeDescriptor,
  ): Promise<HomeSummaryCsvComparison | null> {
    let stores = this.callbacks.normalizedStoreCodes(scope.allowedStoreCodes);
    if (scope.scope === 'ALL') {
      stores = this.callbacks.normalizedStoreCodes(
        (await this.prisma.store.findMany({ select: { storeId: true } })).map(
          (store) => store.storeId,
        ),
      );
    }
    const storeDimension =
      scope.scope === 'ALL' || scope.scope === 'MANAGED_SCOPE';
    const active = await this.prisma.salesHistoryActiveGrain.findMany({
      where: {
        summaryDate: {
          gte: this.callbacks.dateOnlyUtc(range.startDate),
          lte: this.callbacks.dateOnlyUtc(range.endDate),
        },
        ...(stores.length > 0 ? { storeCode: { in: stores } } : {}),
      },
      select: {
        summaryDate: true,
        storeCode: true,
        currentVersionId: true,
      },
    });
    if (active.length === 0) return null;

    const unavailable = new Set<HomeSalesComparisonMetricKey>(
      HOME_SALES_COMPARISON_METRIC_KEYS.filter(
        (key) => !CSV_SUPPORTED_COMPARISON_METRICS.has(key),
      ),
    );
    const csvDimensionType = storeDimension ? 'STORE' : 'USER_STORE';
    const csvDimensionKey = storeDimension
      ? ''
      : this.callbacks.optionalText(scope.ownUserId, 120) || '__NO_CSV_USER__';
    const projectionDimensionKey = storeDimension
      ? ''
      : this.callbacks.personalEmail(scope) || '__NO_PROJECTED_USER__';
    const versionIds = Array.from(
      new Set(active.map((grain) => grain.currentVersionId)),
    );
    const expectedStores = stores.length
      ? stores
      : Array.from(new Set(active.map((grain) => grain.storeCode))).sort();
    const expectedGrains = new Set(
      this.callbacks
        .rangeDateKeys(range.startDate, range.endDate)
        .flatMap((date) =>
          expectedStores.map((storeCode) => `${date}|${storeCode}`),
        ),
    );
    const activeVersionByGrain = new Map(
      active.map((grain) => [
        `${this.callbacks.dateOnlyKey(grain.summaryDate)}|${grain.storeCode}`,
        grain.currentVersionId,
      ]),
    );
    const covered = new Set(
      Array.from(expectedGrains).filter((key) => activeVersionByGrain.has(key)),
    );
    const incompletePersonalCoverage = storeDimension
      ? []
      : await this.prisma.salesHistoryCoverage.findMany({
          where: {
            versionId: { in: versionIds },
            summaryDate: {
              gte: this.callbacks.dateOnlyUtc(range.startDate),
              lte: this.callbacks.dateOnlyUtc(range.endDate),
            },
            storeCode: { in: expectedStores },
            reasonCodes: { has: 'PERSONAL_COVERAGE_INCOMPLETE' },
          },
          select: {
            versionId: true,
            summaryDate: true,
            storeCode: true,
          },
        });
    const personalCoverageIncomplete = incompletePersonalCoverage.some(
      (coverage) =>
        activeVersionByGrain.get(
          `${this.callbacks.dateOnlyKey(coverage.summaryDate)}|${coverage.storeCode}`,
        ) === coverage.versionId,
    );
    if (personalCoverageIncomplete) {
      CSV_SUPPORTED_COMPARISON_METRICS.forEach((key) => unavailable.add(key));
    }
    const uncovered = new Set(
      Array.from(expectedGrains).filter((key) => !covered.has(key)),
    );
    const csvRows = await this.prisma.salesHistoryAggregate.findMany({
      where: {
        versionId: { in: versionIds },
        summaryDate: {
          gte: this.callbacks.dateOnlyUtc(range.startDate),
          lte: this.callbacks.dateOnlyUtc(range.endDate),
        },
        storeCode: { in: expectedStores },
        dimensionType: csvDimensionType,
        dimensionKey: csvDimensionKey,
      },
    });
    const projectionRows =
      uncovered.size === 0
        ? []
        : await this.prisma.homeSummaryDailyAggregate.findMany({
            where: {
              summaryDate: {
                gte: this.callbacks.dateOnlyUtc(range.startDate),
                lte: this.callbacks.dateOnlyUtc(range.endDate),
              },
              projectionKind: 'SALES',
              dimensionType: csvDimensionType,
              dimensionKey: projectionDimensionKey,
              storeCode: { in: expectedStores },
            },
            select: {
              summaryDate: true,
              storeCode: true,
              totalOrders: true,
              metrics: true,
            },
          });
    const csvByGrain = new Map(
      csvRows
        .filter(
          (row) =>
            activeVersionByGrain.get(
              `${this.callbacks.dateOnlyKey(row.summaryDate)}|${row.storeCode}`,
            ) === row.versionId,
        )
        .map((row) => [
          `${this.callbacks.dateOnlyKey(row.summaryDate)}|${row.storeCode}`,
          row,
        ]),
    );
    if (
      storeDimension &&
      Array.from(covered).some((key) => !csvByGrain.has(key))
    ) {
      CSV_SUPPORTED_COMPARISON_METRICS.forEach((key) => unavailable.add(key));
    }
    const projectionByGrain = new Map(
      projectionRows.map((row) => [
        `${this.callbacks.dateOnlyKey(row.summaryDate)}|${row.storeCode}`,
        row,
      ]),
    );
    if (Array.from(uncovered).some((key) => !projectionByGrain.has(key))) {
      CSV_SUPPORTED_COMPARISON_METRICS.forEach((key) => unavailable.add(key));
    }

    const csvTotals = this.emptyCsvComparisonTotals();
    for (const row of csvByGrain.values()) {
      csvTotals.totalRevenue += Number(row.totalRevenue);
      csvTotals.totalOrders += row.totalOrders;
      for (const key of METRIC_COMPARISON_QUANTITY_KEYS) {
        csvTotals[key] += row[key];
      }
    }
    const projectionTotals = this.emptyCsvComparisonTotals();
    for (const [key, row] of projectionByGrain) {
      if (!uncovered.has(key)) continue;
      if (
        typeof row.totalOrders !== 'number' ||
        !Number.isFinite(row.totalOrders)
      ) {
        unavailable.add('totalOrders');
      } else {
        projectionTotals.totalOrders += row.totalOrders;
      }
      const metrics = this.jsonMetricRecord(row.metrics);
      const totalRevenue = metrics.totalRevenue;
      if (typeof totalRevenue !== 'number' || !Number.isFinite(totalRevenue)) {
        unavailable.add('totalRevenue');
      } else {
        projectionTotals.totalRevenue += totalRevenue;
      }
      for (const metricKey of METRIC_COMPARISON_QUANTITY_KEYS) {
        const value = metrics[metricKey];
        if (typeof value !== 'number' || !Number.isFinite(value)) {
          unavailable.add(metricKey);
        } else {
          projectionTotals[metricKey] += value;
        }
      }
    }
    if (unavailable.has('totalRevenue') || unavailable.has('totalOrders')) {
      unavailable.add('averageOrderValue');
    }
    const values = Object.fromEntries(
      HOME_SALES_COMPARISON_METRIC_KEYS.map((key) => [key, 0]),
    ) as Record<HomeSalesComparisonMetricKey, number>;
    values.totalRevenue = Math.max(
      0,
      projectionTotals.totalRevenue + csvTotals.totalRevenue,
    );
    values.totalOrders = Math.max(
      0,
      projectionTotals.totalOrders + csvTotals.totalOrders,
    );
    for (const key of METRIC_COMPARISON_QUANTITY_KEYS) {
      values[key] = Math.max(0, projectionTotals[key] + csvTotals[key]);
    }
    values.averageOrderValue = values.totalOrders
      ? Math.round(values.totalRevenue / values.totalOrders)
      : 0;
    if (personalCoverageIncomplete) {
      CSV_SUPPORTED_COMPARISON_METRICS.forEach((key) => {
        values[key] = 0;
      });
    }
    return { values, source: 'HYBRID_CSV' as const, unavailable };
  }

  private emptyCsvComparisonTotals() {
    return {
      totalRevenue: 0,
      totalOrders: 0,
      extendedInsuranceQuantity: 0,
      laptopQuantity: 0,
      pcQuantity: 0,
      assembledPcQuantity: 0,
      appleQuantity: 0,
      monitorQuantity: 0,
      printerQuantity: 0,
      accessoriesQuantity: 0,
    };
  }

  private jsonMetricRecord(value: Prisma.JsonValue) {
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  }
}
