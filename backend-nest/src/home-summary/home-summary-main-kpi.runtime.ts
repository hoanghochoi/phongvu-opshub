import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { SalesReportSummaryScopeDescriptor } from '../sales-reports/sales-reports.service';
import { SalesReportsRevenueAggregationSummary } from '../sales-reports/sales-reports-revenue-aggregation.runtime';
import { CanonicalRevenueLookup } from '../sales-reports/sales-report-revenue';

type DateRange = {
  start: Date;
  end: Date;
};

export type HomeSalesMainKpiSummary = {
  businessCustomerRevenue: number;
  personalCustomerRevenue: number;
  examScorePromotionCount: number;
  studentPromotionCount: number;
  installmentNeedCount: number;
  successfulInstallmentCount: number;
  extendedInsuranceQuantity: number;
  laptopQuantity: number;
  pcQuantity: number;
  assembledPcQuantity: number;
  appleQuantity: number;
  monitorQuantity: number;
  printerQuantity: number;
  accessoriesQuantity: number;
};

export type HomeSummaryMainKpiCallbacks = {
  salesReportMainKpiWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Prisma.SalesReportWhereInput;
  loadCanonicalRevenueForRows(
    rows: Array<{ orderCode?: unknown }>,
    source: string,
  ): Promise<CanonicalRevenueLookup>;
  summarizeSalesRevenueRows(
    rows: any[],
    canonicalRevenue: CanonicalRevenueLookup,
  ): SalesReportsRevenueAggregationSummary;
};

/** Owns Home Summary main KPI row loading and revenue/category aggregation. */
export class HomeSummaryMainKpiRuntime {
  constructor(
    private readonly prisma: PrismaService,
    private readonly callbacks: HomeSummaryMainKpiCallbacks,
  ) {}

  async build(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Promise<HomeSalesMainKpiSummary> {
    const rows = await this.prisma.salesReport.findMany({
      where: this.callbacks.salesReportMainKpiWhere(scope, range),
      select: {
        id: true,
        reportType: true,
        orderCode: true,
        erpOrderId: true,
        customerType: true,
        promotionCodes: true,
        installmentNeed: true,
        installmentStatus: true,
        installmentNoInstallmentReason: true,
        items: {
          orderBy: { createdAt: 'asc' },
          select: {
            name: true,
            productTypeName: true,
            productGroupName: true,
            categoryType: true,
            quantity: true,
            finalSellPrice: true,
            rowTotal: true,
          },
        },
      },
    });
    const canonicalRevenue = await this.callbacks.loadCanonicalRevenueForRows(
      rows,
      'main_kpis',
    );
    const summary = this.callbacks.summarizeSalesRevenueRows(
      rows,
      canonicalRevenue,
    );
    return this.fromSummary(summary);
  }

  empty(): HomeSalesMainKpiSummary {
    return {
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
    };
  }

  private fromSummary(
    summary: SalesReportsRevenueAggregationSummary,
  ): HomeSalesMainKpiSummary {
    return {
      businessCustomerRevenue: summary.businessRevenue,
      personalCustomerRevenue: summary.personalRevenue,
      examScorePromotionCount: summary.examScorePromotionCount,
      studentPromotionCount: summary.studentPromotionCount,
      installmentNeedCount: summary.installmentNeedTotalCount,
      successfulInstallmentCount: summary.successfulInstallmentOrderCount,
      extendedInsuranceQuantity: summary.extendedInsuranceQuantity,
      laptopQuantity: summary.laptopQuantity,
      pcQuantity: summary.pcQuantity,
      assembledPcQuantity: summary.assembledPcQuantity,
      appleQuantity: summary.appleQuantity,
      monitorQuantity: summary.monitorQuantity,
      printerQuantity: summary.printerQuantity,
      accessoriesQuantity: summary.accessoriesQuantity,
    };
  }
}
