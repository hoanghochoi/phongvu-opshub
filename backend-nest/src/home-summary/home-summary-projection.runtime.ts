import { Logger, ServiceUnavailableException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash } from 'crypto';
import { safeLogError } from '../common/log-sanitizer';
import type { PrismaService } from '../prisma/prisma.service';
import type { SalesReportSummaryScopeDescriptor } from '../sales-reports/sales-reports.service';
import type {
  HomeProjectionKind,
  HomeProjectionLoadResult,
  HomeProjectionMetrics,
  HomeSummaryDailyPoint,
  HomeSummaryFreshnessResponse,
  HomeSummaryProjectionSnapshot,
  SummaryDateRange,
} from './home-summary.service';

type ProjectionRuntimeCallbacks = {
  getOrLoadSupportValue: <T>(
    cacheName: 'projection_freshness',
    key: string,
    label: string,
    loader: () => Promise<T>,
  ) => Promise<T>;
  rangeDateKeys: (startDate: string, endDate: string) => string[];
  dateOnlyUtc: (value: string) => Date;
  dateOnlyKey: (value: Date) => string;
  normalizedStoreCodes: (values: Array<string | null | undefined>) => string[];
  personalEmail: (scope: SalesReportSummaryScopeDescriptor) => string | null;
  loadProjectionFreshness: (
    range: SummaryDateRange,
    requireSales: boolean,
    requireFinance: boolean,
  ) => Promise<HomeSummaryProjectionSnapshot>;
};

/**
 * Owns Home Summary projection feature gating, freshness and aggregate reads.
 * HomeSummaryService remains the stable facade and keeps orchestration,
 * comparison and legacy-sync behavior unchanged.
 */
export class HomeSummaryProjectionRuntime {
  constructor(
    private readonly prisma: PrismaService,
    private readonly logger: Logger,
    private readonly callbacks: ProjectionRuntimeCallbacks,
  ) {}

  isEnabled() {
    const raw = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    if (raw === undefined && process.env.NODE_ENV === 'test') return false;
    return (
      String(raw ?? 'true')
        .trim()
        .toLowerCase() !== 'false'
    );
  }

  loadProjectionFreshnessCached(
    range: SummaryDateRange,
    requireSales: boolean,
    requireFinance: boolean,
  ) {
    const canonical = JSON.stringify([
      'v1',
      range.startDate,
      range.endDate,
      requireSales,
      requireFinance,
    ]);
    const key = createHash('sha256').update(canonical).digest('hex');
    return this.callbacks.getOrLoadSupportValue(
      'projection_freshness',
      key,
      'projection_freshness',
      () =>
        this.callbacks.loadProjectionFreshness(
          range,
          requireSales,
          requireFinance,
        ),
    );
  }

  async loadProjectionFreshness(
    range: SummaryDateRange,
    requireSales = true,
    requireFinance = true,
  ): Promise<HomeSummaryProjectionSnapshot> {
    const startDate = this.callbacks.dateOnlyUtc(range.startDate);
    const endDate = this.callbacks.dateOnlyUtc(range.endDate);
    const states = await this.prisma.homeSummaryProjectionState.findMany({
      where: { summaryDate: { gte: startDate, lte: endDate } },
      orderBy: { summaryDate: 'asc' },
    });
    const stateByDate = new Map(
      states.map((state: any) => [
        this.callbacks.dateOnlyKey(state.summaryDate),
        state,
      ]),
    );
    const expectedDates = this.callbacks.rangeDateKeys(
      range.startDate,
      range.endDate,
    );
    const missingDates = expectedDates.filter((date) => {
      const state = stateByDate.get(date) as any;
      if (!state) return true;
      // A source write marks its projection kind PENDING immediately, while the
      // previous aggregate snapshot remains complete and readable. Only return
      // 503 when that kind has never produced a complete snapshot.
      if (requireSales && !state.salesGeneratedAt) return true;
      if (requireFinance && !state.financeGeneratedAt) return true;
      return false;
    });
    if (missingDates.length > 0) {
      this.logger.warn(
        `Home summary projection unavailable: startDate=${range.startDate} endDate=${range.endDate} missingCompleteDates=${missingDates.length}`,
      );
      throw new ServiceUnavailableException(
        'Dữ liệu Trang chủ đang được chuẩn bị. Vui lòng thử lại sau ít phút.',
      );
    }

    const nowMs = Date.now();
    let projectionGeneratedAt = new Date(nowMs);
    let projectionVersion = 0;
    let projectionLagSeconds = 0;
    let isStale = false;
    const sourceUpdatedAtBySource: Record<string, Date> = {};
    const setLatest = (source: string, value: Date | null) => {
      if (!value) return;
      const current = sourceUpdatedAtBySource[source];
      if (!current || value > current) sourceUpdatedAtBySource[source] = value;
    };
    for (const date of expectedDates) {
      const state = stateByDate.get(date) as any;
      const generatedCandidates = [
        ...(requireSales && state.salesGeneratedAt
          ? [state.salesGeneratedAt]
          : []),
        ...(requireFinance && state.financeGeneratedAt
          ? [state.financeGeneratedAt]
          : []),
      ];
      const generatedAt = generatedCandidates.reduce<Date>(
        (oldest, value) => (value < oldest ? value : oldest),
        generatedCandidates[0] as Date,
      );
      if (generatedAt < projectionGeneratedAt) {
        projectionGeneratedAt = generatedAt;
      }
      projectionVersion = Math.max(
        projectionVersion,
        requireSales ? Number(state.salesProjectionVersion) : 0,
        requireFinance ? Number(state.financeProjectionVersion) : 0,
      );
      setLatest('SALES_REPORT', state.salesReportSourceUpdatedAt);
      setLatest('ERP_ORDER_CACHE', state.erpOrderCacheSourceUpdatedAt);
      setLatest('MAP_VIETIN', state.mapVietinSourceUpdatedAt);
      const freshnessPairs = [
        ...(requireSales
          ? [
              {
                generatedAt: state.salesGeneratedAt as Date,
                sourceWatermarks: [
                  state.salesReportSourceUpdatedAt,
                  state.erpOrderCacheSourceUpdatedAt,
                ],
              },
            ]
          : []),
        ...(requireFinance
          ? [
              {
                generatedAt: state.financeGeneratedAt as Date,
                sourceWatermarks: [state.mapVietinSourceUpdatedAt],
              },
            ]
          : []),
      ];
      for (const pair of freshnessPairs) {
        const sourceUpdatedAt = pair.sourceWatermarks
          .filter((value: Date | null): value is Date => value !== null)
          .reduce<Date | null>(
            (latest, value) => (!latest || value > latest ? value : latest),
            null,
          );
        if (!sourceUpdatedAt) continue;
        const projectedAfterSourceMs =
          pair.generatedAt.getTime() - sourceUpdatedAt.getTime();
        const pendingMs =
          sourceUpdatedAt > pair.generatedAt
            ? nowMs - sourceUpdatedAt.getTime()
            : 0;
        projectionLagSeconds = Math.max(
          projectionLagSeconds,
          Math.ceil(Math.max(projectedAfterSourceMs, pendingMs, 0) / 1000),
        );
        if (sourceUpdatedAt > pair.generatedAt && pendingMs > 15_000) {
          isStale = true;
        }
      }
    }
    const freshness: HomeSummaryFreshnessResponse = {
      projectionGeneratedAt,
      projectionLagSeconds,
      projectionVersion,
      sourceUpdatedAtBySource,
      isStale,
    };
    return {
      freshness,
      versionsByDate: new Map(
        expectedDates.map((date) => {
          const state = stateByDate.get(date) as any;
          return [
            date,
            Math.max(
              requireSales ? Number(state.salesProjectionVersion) : 0,
              requireFinance ? Number(state.financeProjectionVersion) : 0,
            ),
          ];
        }),
      ),
    };
  }

  emptyProjectionMetrics(): HomeProjectionMetrics {
    return {
      totalOrders: 0,
      reportedOrders: 0,
      totalReports: 0,
      notPurchasedReports: 0,
      totalRevenue: 0,
      completedRevenue: 0,
      businessCustomerRevenue: 0,
      personalCustomerRevenue: 0,
      examScorePromotionCount: 0,
      studentPromotionCount: 0,
      installmentNeedCount: 0,
      successfulInstallmentCount: 0,
      extendedInsuranceQuantity: 0,
      laptopQuantity: 0,
      pcQuantity: 0,
      assembledPcQuantity: 0,
      appleQuantity: 0,
      monitorQuantity: 0,
      printerQuantity: 0,
      accessoriesQuantity: 0,
      consultedSolutionYes: 0,
      experiencedYes: 0,
      zaloYes: 0,
      appDownloadYes: 0,
      totalTransferredAmount: 0,
      totalStatements: 0,
      totalStatementsTracked: 0,
      totalStatementsUnfollowed: 0,
      totalStatementsWithOrder: 0,
      totalStatementsWithoutOrder: 0,
    };
  }

  async loadProjectionMetrics(
    range: SummaryDateRange,
    scope: SalesReportSummaryScopeDescriptor,
    projectionKind: HomeProjectionKind,
    includeDailySeries = false,
  ): Promise<HomeProjectionLoadResult> {
    const startedAt = Date.now();
    const startDate = this.callbacks.dateOnlyUtc(range.startDate);
    const endDate = this.callbacks.dateOnlyUtc(range.endDate);
    const base = {
      summaryDate: { gte: startDate, lte: endDate },
      projectionKind,
    };
    let where: Prisma.HomeSummaryDailyAggregateWhereInput;
    if (scope.scope === 'ALL') {
      where = {
        ...base,
        dimensionType: 'GLOBAL',
        dimensionKey: '',
        storeCode: '',
      };
    } else if (scope.scope === 'MANAGED_SCOPE') {
      const stores = this.callbacks.normalizedStoreCodes(
        scope.allowedStoreCodes,
      );
      where = {
        ...base,
        dimensionType: 'STORE',
        storeCode: { in: stores.length ? stores : ['__NO_PROJECTED_STORE__'] },
      };
    } else {
      const email = this.callbacks.personalEmail(scope);
      const stores = this.callbacks.normalizedStoreCodes(
        scope.allowedStoreCodes,
      );
      where = {
        ...base,
        dimensionType: 'USER_STORE',
        dimensionKey: email ?? '__NO_PROJECTED_USER__',
        ...(stores.length > 0 ? { storeCode: { in: stores } } : {}),
      };
    }
    if (includeDailySeries) {
      this.logger.log(
        `Home summary daily series load started: kind=${projectionKind} scope=${scope.scope} startDate=${range.startDate} endDate=${range.endDate}`,
      );
    }
    let rows: Array<{
      summaryDate?: Date;
      totalOrders: number;
      reportedOrders: number;
      totalReports: number;
      notPurchasedReports: number;
      metrics: Prisma.JsonValue;
    }>;
    try {
      rows = await this.prisma.homeSummaryDailyAggregate.findMany({
        where,
        select: {
          ...(includeDailySeries ? { summaryDate: true } : {}),
          totalOrders: true,
          reportedOrders: true,
          totalReports: true,
          notPurchasedReports: true,
          metrics: true,
        },
      });
    } catch (error) {
      if (includeDailySeries) {
        this.logger.warn(
          `Home summary daily series load failed: kind=${projectionKind} scope=${scope.scope} error=${safeLogError(error)} durationMs=${Date.now() - startedAt}`,
        );
      }
      throw error;
    }
    const result: HomeProjectionLoadResult = this.emptyProjectionMetrics();
    const metricKeys = Object.keys(result) as Array<
      keyof HomeProjectionMetrics
    >;
    const dailyByDate = includeDailySeries
      ? new Map(
          this.callbacks
            .rangeDateKeys(range.startDate, range.endDate)
            .map((date) => [
              date,
              {
                date,
                totalRevenue: 0,
                totalOrders: 0,
                reportedOrders: 0,
                totalReports: 0,
              } satisfies HomeSummaryDailyPoint,
            ]),
        )
      : null;
    for (const row of rows) {
      result.totalOrders += row.totalOrders;
      result.reportedOrders += row.reportedOrders;
      result.totalReports += row.totalReports;
      result.notPurchasedReports += row.notPurchasedReports;
      const metrics =
        row.metrics &&
        typeof row.metrics === 'object' &&
        !Array.isArray(row.metrics)
          ? (row.metrics as Record<string, unknown>)
          : {};
      const dailyPoint =
        row.summaryDate && dailyByDate
          ? dailyByDate.get(this.callbacks.dateOnlyKey(row.summaryDate))
          : undefined;
      if (dailyPoint) {
        dailyPoint.totalOrders += row.totalOrders;
        dailyPoint.reportedOrders += row.reportedOrders;
        dailyPoint.totalReports += row.totalReports;
        const dailyRevenue = Number(metrics.totalRevenue ?? 0);
        if (Number.isFinite(dailyRevenue))
          dailyPoint.totalRevenue += dailyRevenue;
      }
      for (const key of metricKeys) {
        if (
          key === 'totalOrders' ||
          key === 'reportedOrders' ||
          key === 'totalReports' ||
          key === 'notPurchasedReports'
        ) {
          continue;
        }
        const value = Number(metrics[key] ?? 0);
        if (Number.isFinite(value)) result[key] += value;
      }
    }
    if (dailyByDate) result.dailySeries = Array.from(dailyByDate.values());
    this.logger.log(
      `Home projection metrics loaded: kind=${projectionKind} scope=${scope.scope} grains=${rows.length} startDate=${range.startDate} endDate=${range.endDate} includeDailySeries=${includeDailySeries} dailySeriesPoints=${result.dailySeries?.length ?? 0} durationMs=${Date.now() - startedAt}`,
    );
    return result;
  }
}
