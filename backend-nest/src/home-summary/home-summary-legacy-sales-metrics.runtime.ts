import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { isSalesReportErpPendingPaymentStatus } from '../sales-reports/sales-report-erp.service';
import {
  canonicalRevenueForOrder,
  canonicalVatIncludedRevenue,
  CanonicalRevenueLookup,
} from '../sales-reports/sales-report-revenue';
import { SalesReportSummaryScopeDescriptor } from '../sales-reports/sales-reports.service';

type DateRange = {
  start: Date;
  end: Date;
};

export type HomeSummaryLegacySalesBehaviorYesCounts = {
  consultedSolution: number;
  experienced: number;
  zalo: number;
  appDownload: number;
};

export type HomeSummaryLegacySalesMetricsCallbacks = {
  salesProgressReportWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Prisma.SalesReportWhereInput;
  orderCacheRevenueWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Prisma.SalesReportErpOrderCacheWhereInput;
  salesReportBehaviorWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Prisma.SalesReportWhereInput;
  loadCanonicalRevenueForRows(
    rows: Array<{ orderCode?: unknown }>,
    source: string,
  ): Promise<CanonicalRevenueLookup>;
  logger: {
    log(message: string): void;
  };
};

/** Owns the remaining legacy Home Summary sales-metric calculations. */
export class HomeSummaryLegacySalesMetricsRuntime {
  constructor(
    private readonly prisma: PrismaService,
    private readonly callbacks: HomeSummaryLegacySalesMetricsCallbacks,
  ) {}

  async completedRevenue(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Promise<number> {
    const rows = await this.prisma.salesReport.findMany({
      where: this.callbacks.salesProgressReportWhere(scope, range),
      select: {
        orderCode: true,
      },
    });
    const canonicalRevenue = await this.callbacks.loadCanonicalRevenueForRows(
      rows,
      'completed_revenue',
    );
    return rows.reduce(
      (sum, row) =>
        sum + canonicalRevenueForOrder(canonicalRevenue, row.orderCode),
      0,
    );
  }

  async totalCacheRevenue(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Promise<number> {
    const rows = await this.prisma.salesReportErpOrderCache.findMany({
      where: this.callbacks.orderCacheRevenueWhere(scope, range),
      select: {
        grandTotal: true,
        paymentStatus: true,
        lifecycleStatus: true,
        hasReturnedFullItems: true,
      },
    });
    let skippedPendingPayment = 0;
    let invalidCanonicalTotal = 0;
    const revenue = rows.reduce((sum, row) => {
      if (isSalesReportErpPendingPaymentStatus(row.paymentStatus)) {
        skippedPendingPayment += 1;
        return sum;
      }
      if (canonicalVatIncludedRevenue(row.grandTotal) === null) {
        invalidCanonicalTotal += 1;
      }
      return sum + this.netCacheRevenue(row);
    }, 0);
    this.callbacks.logger.log(
      `Home summary cache revenue calculated: source=cache scope=${scope.scope} rows=${rows.length} skippedPendingPayment=${skippedPendingPayment} invalidCanonicalTotals=${invalidCanonicalTotal} revenue=${revenue}`,
    );
    return revenue;
  }

  async countBehaviorYesReports(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Promise<HomeSummaryLegacySalesBehaviorYesCounts> {
    const where = this.callbacks.salesReportBehaviorWhere(scope, range);
    const [consultedSolution, experienced, zalo, appDownload] =
      await this.prisma.$transaction([
        this.prisma.salesReport.count({
          where: { ...where, consultedSolutionAnswer: 'YES' },
        }),
        this.prisma.salesReport.count({
          where: { ...where, experiencedAnswer: 'YES' },
        }),
        this.prisma.salesReport.count({
          where: { ...where, zaloAnswer: 'YES' },
        }),
        this.prisma.salesReport.count({
          where: { ...where, appDownloadAnswer: 'YES' },
        }),
      ]);
    return { consultedSolution, experienced, zalo, appDownload };
  }

  empty(): HomeSummaryLegacySalesBehaviorYesCounts {
    return {
      consultedSolution: 0,
      experienced: 0,
      zalo: 0,
      appDownload: 0,
    };
  }

  netCacheRevenue(row: {
    grandTotal: number | null;
    paymentStatus?: string | null;
    lifecycleStatus: string;
    hasReturnedFullItems: boolean;
  }): number {
    if (isSalesReportErpPendingPaymentStatus(row.paymentStatus)) return 0;
    const status = String(row.lifecycleStatus || '')
      .trim()
      .toUpperCase();
    if (
      status === 'CANCELLED' ||
      status === 'RETURNED_FULL' ||
      row.hasReturnedFullItems === true
    ) {
      return 0;
    }
    return canonicalVatIncludedRevenue(row.grandTotal) ?? 0;
  }
}
