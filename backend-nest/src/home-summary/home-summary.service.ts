import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  SalesReportOperatingSummary,
  SalesReportSummaryScopeDescriptor,
  SalesReportsService,
} from '../sales-reports/sales-reports.service';
import { GetHomeSummaryQueryDto } from './home-summary.dto';

const REPORT_TYPE_PURCHASED = 'PURCHASED';
const COVERAGE_LABEL = 'Tỷ lệ phủ báo cáo';

type DateRange = {
  start: Date;
  end: Date;
};

type HomeSummaryResponse = SalesReportOperatingSummary & {
  unavailableMessage: string | null;
};

type HomeSummaryScopeRequest =
  | 'AUTO'
  | 'ALL'
  | 'MANAGED_SCOPE'
  | 'OWN';

@Injectable()
export class HomeSummaryService {
  private readonly logger = new Logger(HomeSummaryService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly salesReports: SalesReportsService,
  ) {}

  private get homeSummaryOrderFact() {
    return (this.prisma as any).homeSummaryOrderFact;
  }

  private get homeSummaryReportFact() {
    return (this.prisma as any).homeSummaryReportFact;
  }

  async getSummary(
    user: any,
    query: GetHomeSummaryQueryDto,
  ): Promise<HomeSummaryResponse> {
    const startedAt = Date.now();
    const date = this.parseDateParam(query.date) ?? this.todayVietnamDate();
    const requestedScope = this.parseScopeParam(query.scope);
    const summaryDate = this.parseDateOnly(date) ?? new Date();
    this.logger.log(
      `Home summary load started: user=${this.safeUserLabel(user)} date=${date} scopeFilter=${requestedScope}`,
    );
    const scope = await this.salesReports.describeHomeSummaryScope(
      user,
      requestedScope,
    );
    if (!scope.available) {
      const response = this.emptySummary(
        date,
        scope,
        new Date(),
        scope.unavailableMessage,
      );
      this.logger.log(
        `Home summary unavailable: user=${this.safeUserLabel(user)} date=${date} scopeFilter=${requestedScope} message=${scope.unavailableMessage || 'none'} durationMs=${Date.now() - startedAt}`,
      );
      return response;
    }

    const refreshedAt = await this.syncFacts(date, summaryDate);
    const reportWhere = this.reportScopeWhere(scope, summaryDate);
    const orderWhere = this.orderScopeWhere(scope, summaryDate);
    const [totalOrders, totalReports, revenueSummary, reportedCodeRows] =
      await this.prisma.$transaction([
        this.homeSummaryOrderFact.count({ where: orderWhere }),
        this.homeSummaryReportFact.count({ where: reportWhere }),
        this.homeSummaryReportFact.aggregate({
          where: {
            ...reportWhere,
            reportType: REPORT_TYPE_PURCHASED,
          },
          _sum: { revenue: true },
        }),
        this.homeSummaryReportFact.findMany({
          where: {
            ...reportWhere,
            reportType: REPORT_TYPE_PURCHASED,
            orderCode: { not: null },
          },
          select: { orderCode: true },
        }),
      ]);
    const reportedCodes = Array.from(
      new Set(
        reportedCodeRows
          .map((row: { orderCode: string | null }) =>
            this.normalizeOrderCode(row.orderCode),
          )
          .filter((value: string | null): value is string => Boolean(value)),
      ),
    );
    const reportedOrders =
      reportedCodes.length > 0
        ? await this.homeSummaryOrderFact.count({
            where: {
              ...orderWhere,
              orderCode: { in: reportedCodes },
            },
          })
        : 0;
    const unreportedOrders = Math.max(totalOrders - reportedOrders, 0);
    const coverageRate = totalOrders
      ? Number(((reportedOrders / totalOrders) * 100).toFixed(2))
      : 0;
    const response: HomeSummaryResponse = {
      date,
      available: true,
      scope: scope.scope,
      scopeLabel: scope.scopeLabel,
      scopeDetail: scope.scopeDetail,
      coverageLabel: COVERAGE_LABEL,
      totalRevenue: revenueSummary._sum.revenue ?? 0,
      totalOrders,
      totalReports,
      reportedOrders,
      unreportedOrders,
      coverageRate,
      refreshedAt,
      unavailableMessage: null,
    };
    this.logger.log(
      `Home summary load succeeded: user=${this.safeUserLabel(user)} date=${date} scopeFilter=${requestedScope} scope=${scope.scope} totalOrders=${totalOrders} totalReports=${totalReports} reportedOrders=${reportedOrders} durationMs=${Date.now() - startedAt}`,
    );
    return response;
  }

  private parseScopeParam(value?: string | null): HomeSummaryScopeRequest {
    const normalized = String(value || '')
      .trim()
      .toUpperCase();
    if (
      normalized === 'ALL' ||
      normalized === 'MANAGED_SCOPE' ||
      normalized === 'OWN'
    ) {
      return normalized;
    }
    return 'AUTO';
  }

  private async syncFacts(date: string, summaryDate: Date) {
    const startedAt = Date.now();
    const dateRange = this.dateRangeFor(summaryDate);
    this.logger.log(`Home summary sync started: date=${date}`);
    const [reports, orders] = await this.prisma.$transaction([
      this.prisma.salesReport.findMany({
        where: {
          erpExcludedAt: null,
          ...this.reportedOrderDateWhere(dateRange),
        },
        select: {
          id: true,
          reportType: true,
          orderCode: true,
          createdByUserId: true,
          createdByEmail: true,
          createdByPersonnelCode: true,
          storeCode: true,
          storeName: true,
          organizationNodeId: true,
          erpGrandTotal: true,
          erpConsultantCustomId: true,
          erpConsultantName: true,
          erpOrderCreatedAt: true,
          erpFetchedAt: true,
          submittedAt: true,
        },
      }),
      this.prisma.salesReportErpOrderCache.findMany({
        where: {
          excludedAt: null,
          ...this.orderCacheDateWhere(dateRange),
        },
        select: {
          orderCode: true,
          orderCreatedAt: true,
          fetchedAt: true,
          storeCode: true,
          storeName: true,
          organizationNodeId: true,
          sourceUserId: true,
          sourceUserEmail: true,
          consultantCustomId: true,
          consultantName: true,
          consultantEmail: true,
          sellerId: true,
          sellerName: true,
          sellerEmail: true,
          grandTotal: true,
        },
      }),
    ]);

    const refreshedAt = new Date();
    const purchaseReportsByOrderCode = new Map<
      string,
      {
        id: string;
        createdByUserId: string | null;
        createdByEmail: string | null;
        createdByPersonnelCode: string | null;
        revenue: number | null;
        submittedAt: Date;
        storeCode: string | null;
        storeName: string | null;
        organizationNodeId: string | null;
        consultantCustomId: string | null;
        consultantName: string | null;
        orderCreatedAt: Date | null;
        fetchedAt: Date | null;
      }
    >();
    const reportIds: string[] = [];
    const reportWrites = reports.map((row) => {
      reportIds.push(row.id);
      const orderCode = this.normalizeOrderCode(row.orderCode);
      if (row.reportType === REPORT_TYPE_PURCHASED && orderCode) {
        purchaseReportsByOrderCode.set(orderCode, {
          id: row.id,
          createdByUserId: this.optionalText(row.createdByUserId, 80),
          createdByEmail: this.normalizeEmail(row.createdByEmail),
          createdByPersonnelCode: this.optionalText(
            row.createdByPersonnelCode,
            120,
          ),
          revenue:
            typeof row.erpGrandTotal === 'number' ? row.erpGrandTotal : null,
          submittedAt: row.submittedAt,
          storeCode: this.normalizeStoreCode(row.storeCode),
          storeName: this.optionalText(row.storeName, 120),
          organizationNodeId: this.optionalText(row.organizationNodeId, 80),
          consultantCustomId: this.optionalText(row.erpConsultantCustomId, 120),
          consultantName: this.optionalText(row.erpConsultantName, 120),
          orderCreatedAt: row.erpOrderCreatedAt,
          fetchedAt: row.erpFetchedAt,
        });
      }
      return this.homeSummaryReportFact.upsert({
        where: { salesReportId: row.id },
        create: {
          summaryDate,
          salesReportId: row.id,
          reportType: row.reportType,
          orderCode,
          createdByUserId: this.optionalText(row.createdByUserId, 80),
          createdByEmail: this.normalizeEmail(row.createdByEmail),
          createdByPersonnelCode: this.optionalText(
            row.createdByPersonnelCode,
            120,
          ),
          storeCode: this.normalizeStoreCode(row.storeCode),
          storeName: this.optionalText(row.storeName, 120),
          organizationNodeId: this.optionalText(row.organizationNodeId, 80),
          revenue:
            typeof row.erpGrandTotal === 'number' ? row.erpGrandTotal : null,
          submittedAt: row.submittedAt,
          refreshedAt,
        },
        update: {
          summaryDate,
          reportType: row.reportType,
          orderCode,
          createdByUserId: this.optionalText(row.createdByUserId, 80),
          createdByEmail: this.normalizeEmail(row.createdByEmail),
          createdByPersonnelCode: this.optionalText(
            row.createdByPersonnelCode,
            120,
          ),
          storeCode: this.normalizeStoreCode(row.storeCode),
          storeName: this.optionalText(row.storeName, 120),
          organizationNodeId: this.optionalText(row.organizationNodeId, 80),
          revenue:
            typeof row.erpGrandTotal === 'number' ? row.erpGrandTotal : null,
          submittedAt: row.submittedAt,
          refreshedAt,
        },
      });
    });

    const orderCodes = new Set<string>();
    const orderWrites = orders.map((row) => {
      const orderCode = this.normalizeOrderCode(row.orderCode) ?? '';
      orderCodes.add(orderCode);
      return this.upsertOrderFactFromCacheRow(
        summaryDate,
        refreshedAt,
        row,
        purchaseReportsByOrderCode.get(orderCode) ?? null,
      );
    });

    for (const [orderCode, report] of purchaseReportsByOrderCode.entries()) {
      if (orderCodes.has(orderCode)) continue;
      orderCodes.add(orderCode);
      orderWrites.push(
        this.homeSummaryOrderFact.upsert({
          where: { orderCode },
          create: {
            summaryDate,
            orderCode,
            orderCreatedAt: report.orderCreatedAt,
            fetchedAt: report.fetchedAt ?? report.submittedAt,
            storeCode: report.storeCode,
            storeName: report.storeName,
            organizationNodeId: report.organizationNodeId,
            sourceUserId: report.createdByUserId,
            sourceUserEmail: report.createdByEmail,
            consultantCustomId: report.consultantCustomId,
            consultantName: report.consultantName,
            consultantEmail: null,
            sellerId: null,
            sellerName: null,
            sellerEmail: null,
            grandTotal: report.revenue,
            hasValidReport: true,
            reportId: report.id,
            reportSubmittedAt: report.submittedAt,
            reportRevenue: report.revenue,
            reportCreatedByUserId: report.createdByUserId,
            reportCreatedByEmail: report.createdByEmail,
            reportCreatedByPersonnelCode: report.createdByPersonnelCode,
            refreshedAt,
          },
          update: {
            summaryDate,
            orderCreatedAt: report.orderCreatedAt,
            fetchedAt: report.fetchedAt ?? report.submittedAt,
            storeCode: report.storeCode,
            storeName: report.storeName,
            organizationNodeId: report.organizationNodeId,
            sourceUserId: report.createdByUserId,
            sourceUserEmail: report.createdByEmail,
            consultantCustomId: report.consultantCustomId,
            consultantName: report.consultantName,
            consultantEmail: null,
            sellerId: null,
            sellerName: null,
            sellerEmail: null,
            grandTotal: report.revenue,
            hasValidReport: true,
            reportId: report.id,
            reportSubmittedAt: report.submittedAt,
            reportRevenue: report.revenue,
            reportCreatedByUserId: report.createdByUserId,
            reportCreatedByEmail: report.createdByEmail,
            reportCreatedByPersonnelCode: report.createdByPersonnelCode,
            refreshedAt,
          },
        }),
      );
    }

    await this.flushWrites(reportWrites);
    await this.flushWrites(orderWrites);
    await this.prisma.$transaction([
      this.homeSummaryReportFact.deleteMany({
        where: {
          summaryDate,
          ...(reportIds.length > 0
            ? { salesReportId: { notIn: reportIds } }
            : {}),
        },
      }),
      this.homeSummaryOrderFact.deleteMany({
        where: {
          summaryDate,
          ...(orderCodes.size > 0
            ? { orderCode: { notIn: Array.from(orderCodes) } }
            : {}),
        },
      }),
    ]);
    this.logger.log(
      `Home summary sync succeeded: date=${date} orderFacts=${orderCodes.size} reportFacts=${reportIds.length} durationMs=${Date.now() - startedAt}`,
    );
    return refreshedAt;
  }

  private upsertOrderFactFromCacheRow(
    summaryDate: Date,
    refreshedAt: Date,
    row: {
      orderCode: string;
      orderCreatedAt: Date | null;
      fetchedAt: Date;
      storeCode: string | null;
      storeName: string | null;
      organizationNodeId: string | null;
      sourceUserId: string | null;
      sourceUserEmail: string | null;
      consultantCustomId: string | null;
      consultantName: string | null;
      consultantEmail: string | null;
      sellerId: string | null;
      sellerName: string | null;
      sellerEmail: string | null;
      grandTotal: number | null;
    },
    report: {
      id: string;
      createdByUserId: string | null;
      createdByEmail: string | null;
      createdByPersonnelCode: string | null;
      revenue: number | null;
      submittedAt: Date;
    } | null,
  ) {
    const orderCode = this.normalizeOrderCode(row.orderCode) ?? '';
    return this.homeSummaryOrderFact.upsert({
      where: { orderCode },
      create: {
        summaryDate,
        orderCode,
        orderCreatedAt: row.orderCreatedAt,
        fetchedAt: row.fetchedAt,
        storeCode: this.normalizeStoreCode(row.storeCode),
        storeName: this.optionalText(row.storeName, 120),
        organizationNodeId: this.optionalText(row.organizationNodeId, 80),
        sourceUserId: this.optionalText(row.sourceUserId, 80),
        sourceUserEmail: this.normalizeEmail(row.sourceUserEmail),
        consultantCustomId: this.optionalText(row.consultantCustomId, 120),
        consultantName: this.optionalText(row.consultantName, 120),
        consultantEmail: this.normalizeEmail(row.consultantEmail),
        sellerId: this.optionalText(row.sellerId, 120),
        sellerName: this.optionalText(row.sellerName, 120),
        sellerEmail: this.normalizeEmail(row.sellerEmail),
        grandTotal: typeof row.grandTotal === 'number' ? row.grandTotal : null,
        hasValidReport: Boolean(report),
        reportId: report?.id ?? null,
        reportSubmittedAt: report?.submittedAt ?? null,
        reportRevenue: report?.revenue ?? null,
        reportCreatedByUserId: report?.createdByUserId ?? null,
        reportCreatedByEmail: report?.createdByEmail ?? null,
        reportCreatedByPersonnelCode: report?.createdByPersonnelCode ?? null,
        refreshedAt,
      },
      update: {
        summaryDate,
        orderCreatedAt: row.orderCreatedAt,
        fetchedAt: row.fetchedAt,
        storeCode: this.normalizeStoreCode(row.storeCode),
        storeName: this.optionalText(row.storeName, 120),
        organizationNodeId: this.optionalText(row.organizationNodeId, 80),
        sourceUserId: this.optionalText(row.sourceUserId, 80),
        sourceUserEmail: this.normalizeEmail(row.sourceUserEmail),
        consultantCustomId: this.optionalText(row.consultantCustomId, 120),
        consultantName: this.optionalText(row.consultantName, 120),
        consultantEmail: this.normalizeEmail(row.consultantEmail),
        sellerId: this.optionalText(row.sellerId, 120),
        sellerName: this.optionalText(row.sellerName, 120),
        sellerEmail: this.normalizeEmail(row.sellerEmail),
        grandTotal: typeof row.grandTotal === 'number' ? row.grandTotal : null,
        hasValidReport: Boolean(report),
        reportId: report?.id ?? null,
        reportSubmittedAt: report?.submittedAt ?? null,
        reportRevenue: report?.revenue ?? null,
        reportCreatedByUserId: report?.createdByUserId ?? null,
        reportCreatedByEmail: report?.createdByEmail ?? null,
        reportCreatedByPersonnelCode: report?.createdByPersonnelCode ?? null,
        refreshedAt,
      },
    });
  }

  private async flushWrites(writes: Prisma.PrismaPromise<unknown>[]) {
    const chunkSize = 100;
    for (let index = 0; index < writes.length; index += chunkSize) {
      await this.prisma.$transaction(writes.slice(index, index + chunkSize));
    }
  }

  private reportScopeWhere(
    scope: SalesReportSummaryScopeDescriptor,
    summaryDate: Date,
  ) {
    const base = { summaryDate };
    if (scope.scope === 'ALL') return base;
    if (scope.scope === 'MANAGED_SCOPE') {
      return {
        AND: [
          base,
          { storeCode: { in: scope.allowedStoreCodes } },
        ],
      };
    }
    const or: Record<string, unknown>[] = [];
    if (scope.ownUserId) or.push({ createdByUserId: scope.ownUserId });
    if (scope.ownEmail) {
      or.push({
        createdByEmail: { equals: scope.ownEmail, mode: 'insensitive' },
      });
    }
    if (scope.ownPersonnelCode) {
      or.push({
        createdByPersonnelCode: {
          equals: scope.ownPersonnelCode,
          mode: 'insensitive',
        },
      });
    }
    return { AND: [base, { OR: or }] };
  }

  private orderScopeWhere(
    scope: SalesReportSummaryScopeDescriptor,
    summaryDate: Date,
  ) {
    const base = { summaryDate };
    if (scope.scope === 'ALL') return base;
    if (scope.scope === 'MANAGED_SCOPE') {
      return {
        AND: [
          base,
          { storeCode: { in: scope.allowedStoreCodes } },
        ],
      };
    }
    const or: Record<string, unknown>[] = [];
    if (scope.ownUserId) or.push({ sourceUserId: scope.ownUserId });
    if (scope.ownEmail) {
      or.push(
        { sourceUserEmail: { equals: scope.ownEmail, mode: 'insensitive' } },
        { consultantEmail: { equals: scope.ownEmail, mode: 'insensitive' } },
        { sellerEmail: { equals: scope.ownEmail, mode: 'insensitive' } },
      );
    }
    if (scope.ownPersonnelCode) {
      or.push(
        {
          consultantCustomId: {
            equals: scope.ownPersonnelCode,
            mode: 'insensitive',
          },
        },
        { sellerId: { equals: scope.ownPersonnelCode, mode: 'insensitive' } },
      );
    }
    return { AND: [base, { OR: or }] };
  }

  private reportedOrderDateWhere(dateRange: DateRange) {
    return {
      OR: [
        {
          erpOrderCreatedAt: {
            gte: dateRange.start,
            lt: dateRange.end,
          },
        },
        {
          AND: [
            { erpOrderCreatedAt: null },
            {
              submittedAt: {
                gte: dateRange.start,
                lt: dateRange.end,
              },
            },
          ],
        },
      ],
    };
  }

  private orderCacheDateWhere(dateRange: DateRange) {
    return {
      OR: [
        {
          orderCreatedAt: {
            gte: dateRange.start,
            lt: dateRange.end,
          },
        },
        {
          AND: [
            { orderCreatedAt: null },
            {
              fetchedAt: {
                gte: dateRange.start,
                lt: dateRange.end,
              },
            },
          ],
        },
      ],
    };
  }

  private emptySummary(
    date: string,
    scope: SalesReportSummaryScopeDescriptor,
    refreshedAt: Date,
    unavailableMessage: string | null,
  ): HomeSummaryResponse {
    return {
      date,
      available: false,
      scope: scope.scope,
      scopeLabel: scope.scopeLabel,
      scopeDetail: scope.scopeDetail,
      coverageLabel: COVERAGE_LABEL,
      totalRevenue: 0,
      totalOrders: 0,
      totalReports: 0,
      reportedOrders: 0,
      unreportedOrders: 0,
      coverageRate: 0,
      refreshedAt,
      unavailableMessage,
    };
  }

  private dateRangeFor(summaryDate: Date): DateRange {
    const end = new Date(summaryDate);
    end.setUTCDate(end.getUTCDate() + 1);
    return { start: summaryDate, end };
  }

  private parseDateParam(value?: string) {
    const text = String(value || '').trim();
    return /^\d{4}-\d{2}-\d{2}$/.test(text) ? text : null;
  }

  private parseDateOnly(value?: string) {
    const text = String(value || '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null;
    const date = new Date(`${text}T00:00:00.000+07:00`);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  private todayVietnamDate() {
    const vnNow = new Date(Date.now() + 7 * 60 * 60 * 1000);
    const two = (part: number) => String(part).padStart(2, '0');
    return `${vnNow.getUTCFullYear()}-${two(vnNow.getUTCMonth() + 1)}-${two(vnNow.getUTCDate())}`;
  }

  private normalizeOrderCode(value: unknown) {
    const text = String(value || '')
      .trim()
      .replace(/\s+/g, '');
    return text || null;
  }

  private normalizeStoreCode(value: unknown) {
    const text = String(value || '').trim().toUpperCase();
    return text || null;
  }

  private normalizeEmail(value: unknown) {
    const text = String(value || '').trim().toLowerCase();
    return text || null;
  }

  private optionalText(value: unknown, maxLength: number) {
    const text = String(value || '').trim();
    if (!text) return null;
    return text.slice(0, maxLength);
  }

  private safeUserLabel(user: any) {
    return this.normalizeEmail(user?.email) || this.optionalText(user?.id, 80) || 'missing';
  }
}
