import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { SalesReportSummaryScopeDescriptor } from '../sales-reports/sales-reports.service';

type DateRange = {
  start: Date;
  end: Date;
};

export type HomeSummaryFinanceMetrics = {
  totalStatements: number;
  totalStatementsTracked: number;
  totalStatementsUnfollowed: number;
  totalTransferredAmount: number;
  totalStatementsWithOrder: number;
  totalStatementsWithoutOrder: number;
};

export type HomeSummaryFinanceMetricsCallbacks = {
  financeScopeWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
    personalOrderCodes: string[],
  ): Prisma.MapVietinTransactionWhereInput;
  orderScopeWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Prisma.HomeSummaryOrderFactWhereInput;
  normalizeOrderCode(value: unknown): string | null;
};

/** Owns the remaining legacy Home Summary finance-metric calculations. */
export class HomeSummaryFinanceMetricsRuntime {
  constructor(
    private readonly prisma: PrismaService,
    private readonly callbacks: HomeSummaryFinanceMetricsCallbacks,
  ) {}

  async calculate(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Promise<HomeSummaryFinanceMetrics> {
    const personalOrderCodes =
      scope.scope === 'OWN'
        ? (
            await this.prisma.homeSummaryOrderFact.findMany({
              where: this.callbacks.orderScopeWhere(scope, range),
              select: { orderCode: true },
            })
          )
            .map((row: { orderCode: string | null }) =>
              this.callbacks.normalizeOrderCode(row.orderCode),
            )
            .filter((value: string | null): value is string => Boolean(value))
        : [];
    const financeWhere = this.callbacks.financeScopeWhere(
      scope,
      range,
      personalOrderCodes,
    );
    const [
      totalStatements,
      totalStatementsTracked,
      totalStatementsUnfollowed,
      transferredAmountSummary,
      totalStatementsWithOrder,
      totalStatementsWithoutOrder,
    ] = await this.prisma.$transaction([
      this.prisma.mapVietinTransaction.count({ where: financeWhere }),
      this.prisma.mapVietinTransaction.count({
        where: this.andMapTransactionWhere(financeWhere, {
          orderTrackingStatus: 'FOLLOWING',
        }),
      }),
      this.prisma.mapVietinTransaction.count({
        where: this.andMapTransactionWhere(financeWhere, {
          orderTrackingStatus: 'UNFOLLOWED',
        }),
      }),
      this.prisma.mapVietinTransaction.aggregate({
        where: financeWhere,
        _sum: { amount: true },
      }),
      this.prisma.mapVietinTransaction.count({
        where: this.andMapTransactionWhere(financeWhere, {
          orderTrackingStatus: 'FOLLOWING',
          orders: { isEmpty: false },
        }),
      }),
      this.prisma.mapVietinTransaction.count({
        where: this.andMapTransactionWhere(financeWhere, {
          orderTrackingStatus: 'FOLLOWING',
          orders: { isEmpty: true },
        }),
      }),
    ]);
    return {
      totalStatements,
      totalStatementsTracked,
      totalStatementsUnfollowed,
      totalTransferredAmount: transferredAmountSummary._sum.amount ?? 0,
      totalStatementsWithOrder,
      totalStatementsWithoutOrder,
    };
  }

  empty(): HomeSummaryFinanceMetrics {
    return {
      totalStatements: 0,
      totalStatementsTracked: 0,
      totalStatementsUnfollowed: 0,
      totalTransferredAmount: 0,
      totalStatementsWithOrder: 0,
      totalStatementsWithoutOrder: 0,
    };
  }

  private andMapTransactionWhere(
    ...parts: Prisma.MapVietinTransactionWhereInput[]
  ): Prisma.MapVietinTransactionWhereInput {
    const compact = parts.filter((part) => Object.keys(part).length > 0);
    if (compact.length === 0) return {};
    if (compact.length === 1) return compact[0];
    return { AND: compact };
  }
}
