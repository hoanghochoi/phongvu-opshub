import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { GetHomeSummaryDetailsV2QueryDto } from './home-summary.dto';
import {
  HomeSummaryScopeRequest,
  SalesReportSummaryScopeDescriptor,
} from '../sales-reports/sales-reports.service';

type SummaryDateRange = {
  start: Date;
  end: Date;
  startDate: string;
  endDate: string;
};

type DetailsV2Kind = 'NOT_PURCHASED' | 'UNREPORTED_ORDER' | 'INSTALLMENT_NEED';

type SelectedSalesScope = {
  scope: SalesReportSummaryScopeDescriptor;
  selectedUserId: string | null;
};

export type HomeSummaryBehaviorDetailsV2Response = {
  kind: DetailsV2Kind;
  startDate: string;
  endDate: string;
  scope: string;
  scopeLabel: string;
  selectedSalesProgressUserId: string | null;
  limit: number;
  total: number;
  items: unknown[];
  nextCursor: string | null;
};

export type HomeSummaryBehaviorDetailsV2Callbacks = {
  parseSummaryRange(query: GetHomeSummaryDetailsV2QueryDto): SummaryDateRange;
  parseScopeParam(value?: string | null): HomeSummaryScopeRequest;
  optionalText(value: unknown, maxLength: number): string | null;
  normalizeOrderCode(value: unknown): string | null;
  safeUserLabel(user: any): string;
  resolveSectionAccess(user: any): Promise<{ salesAvailable: boolean }>;
  describeHomeSummaryScope(
    user: any,
    requestedScope: HomeSummaryScopeRequest,
    organizationNodeId: string | null,
  ): Promise<SalesReportSummaryScopeDescriptor>;
  resolveSelectedSalesMetricsScope(
    user: any,
    scope: SalesReportSummaryScopeDescriptor,
    requestedUserId: string | null,
  ): Promise<SelectedSalesScope>;
  reportScopeWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: Pick<SummaryDateRange, 'start' | 'end'>,
  ): Prisma.HomeSummaryReportFactWhereInput;
  orderScopeWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: Pick<SummaryDateRange, 'start' | 'end'>,
  ): Prisma.HomeSummaryOrderFactWhereInput;
  salesReportMainKpiWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: Pick<SummaryDateRange, 'start' | 'end'>,
  ): Prisma.SalesReportWhereInput;
  mapNotPurchased(row: any): unknown;
  mapUnreportedOrder(row: any, employeeNames: Map<string, string>): unknown;
  mapInstallmentNeed(row: any): unknown;
  unreportedEmployeeNamesByEmail(rows: any[]): Promise<Map<string, string>>;
  logger: {
    log(message: string): void;
  };
};

/** Owns Home Summary behavior-details V2 query, cursor and page orchestration. */
export class HomeSummaryBehaviorDetailsV2Runtime {
  constructor(
    private readonly prisma: PrismaService,
    private readonly callbacks: HomeSummaryBehaviorDetailsV2Callbacks,
  ) {}

  async load(
    user: any,
    query: GetHomeSummaryDetailsV2QueryDto,
  ): Promise<HomeSummaryBehaviorDetailsV2Response> {
    const startedAt = Date.now();
    const range = this.callbacks.parseSummaryRange(query);
    const requestedScope = this.callbacks.parseScopeParam(query.scope);
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 50)));
    const cursorId = this.decodeCursor(query.cursor, query.kind);
    const requestedSalesProgressUserId = this.callbacks.optionalText(
      query.salesProgressUserId,
      80,
    );
    this.callbacks.logger.log(
      `Home summary details v2 load started: user=${this.callbacks.safeUserLabel(user)} kind=${query.kind} startDate=${range.startDate} endDate=${range.endDate} limit=${limit} hasCursor=${Boolean(cursorId)}`,
    );

    const { salesAvailable } = await this.callbacks.resolveSectionAccess(user);
    if (!salesAvailable) {
      throw new ForbiddenException(
        'Bạn chưa có quyền xem chi tiết bán hàng trên dashboard.',
      );
    }

    const scope = await this.callbacks.describeHomeSummaryScope(
      user,
      requestedScope,
      this.callbacks.optionalText(query.organizationNodeId, 80),
    );
    if (!scope.available) {
      throw new ForbiddenException(
        scope.unavailableMessage ||
          'Tài khoản hiện chưa có phạm vi dữ liệu để xem chi tiết.',
      );
    }

    const selectedSalesScope =
      await this.callbacks.resolveSelectedSalesMetricsScope(
        user,
        scope,
        requestedSalesProgressUserId,
      );
    const salesMetricsScope = selectedSalesScope.scope;
    const base = {
      kind: query.kind,
      startDate: range.startDate,
      endDate: range.endDate,
      scope: salesMetricsScope.scope,
      scopeLabel: salesMetricsScope.scopeLabel,
      selectedSalesProgressUserId: selectedSalesScope.selectedUserId,
      limit,
    };

    if (query.kind === 'NOT_PURCHASED') {
      return this.loadNotPurchased(
        base,
        salesMetricsScope,
        range,
        cursorId,
        startedAt,
      );
    }

    if (query.kind === 'UNREPORTED_ORDER') {
      return this.loadUnreportedOrders(
        base,
        salesMetricsScope,
        range,
        cursorId,
        startedAt,
      );
    }

    return this.loadInstallmentNeeds(
      base,
      salesMetricsScope,
      range,
      cursorId,
      startedAt,
    );
  }

  private async loadNotPurchased(
    base: Omit<
      HomeSummaryBehaviorDetailsV2Response,
      'total' | 'items' | 'nextCursor'
    >,
    scope: SalesReportSummaryScopeDescriptor,
    range: SummaryDateRange,
    cursorId: string | null,
    startedAt: number,
  ) {
    const where: Prisma.HomeSummaryReportFactWhereInput = {
      ...this.callbacks.reportScopeWhere(scope, range),
      reportType: 'NOT_PURCHASED',
    };
    const [total, facts] = await this.prisma.$transaction([
      this.prisma.homeSummaryReportFact.count({ where }),
      this.prisma.homeSummaryReportFact.findMany({
        where,
        orderBy: { salesReportId: 'asc' },
        take: base.limit + 1,
        ...(cursorId ? { cursor: { salesReportId: cursorId }, skip: 1 } : {}),
        select: { salesReportId: true },
      }),
    ]);
    const page = facts.slice(0, base.limit);
    const ids = page.map((row: { salesReportId: string }) => row.salesReportId);
    const reports = ids.length
      ? await this.prisma.salesReport.findMany({
          where: { id: { in: ids } },
          select: {
            id: true,
            submittedAt: true,
            storeCode: true,
            createdByName: true,
            createdByEmail: true,
            customerName: true,
            customerType: true,
            categoryGroupName: true,
            categoryGroupNameVi: true,
            notPurchasedReason: true,
            notPurchasedOtherReason: true,
          },
        })
      : [];
    const byId = new Map(reports.map((row) => [row.id, row]));
    return this.response(
      base,
      page
        .map((row: { salesReportId: string }) => byId.get(row.salesReportId))
        .filter(Boolean)
        .map((row: any) => this.callbacks.mapNotPurchased(row)),
      total,
      facts.length > base.limit ? (ids.at(-1) ?? null) : null,
      startedAt,
    );
  }

  private async loadUnreportedOrders(
    base: Omit<
      HomeSummaryBehaviorDetailsV2Response,
      'total' | 'items' | 'nextCursor'
    >,
    scope: SalesReportSummaryScopeDescriptor,
    range: SummaryDateRange,
    cursorId: string | null,
    startedAt: number,
  ) {
    const salesOrderWhere = this.callbacks.orderScopeWhere(scope, range);
    const reportedCodeRows = await this.prisma.homeSummaryReportFact.findMany({
      where: {
        ...this.callbacks.reportScopeWhere(scope, range),
        reportType: 'PURCHASED',
        orderCode: { not: null },
      },
      select: { orderCode: true },
    });
    const reportedCodes = reportedCodeRows
      .map((row: { orderCode: string | null }) =>
        this.callbacks.normalizeOrderCode(row.orderCode),
      )
      .filter((value: string | null): value is string => Boolean(value));
    const where: Prisma.HomeSummaryOrderFactWhereInput = reportedCodes.length
      ? { AND: [salesOrderWhere, { orderCode: { notIn: reportedCodes } }] }
      : salesOrderWhere;
    const [total, rows] = await this.prisma.$transaction([
      this.prisma.homeSummaryOrderFact.count({ where }),
      this.prisma.homeSummaryOrderFact.findMany({
        where,
        orderBy: { orderCode: 'asc' },
        take: base.limit + 1,
        ...(cursorId ? { cursor: { orderCode: cursorId }, skip: 1 } : {}),
        select: {
          orderCode: true,
          grandTotal: true,
          orderCreatedAt: true,
          fetchedAt: true,
          storeCode: true,
          consultantName: true,
          consultantEmail: true,
          sellerName: true,
          sellerEmail: true,
          sourceUserEmail: true,
        },
      }),
    ]);
    const page = rows.slice(0, base.limit);
    const employeeNames =
      await this.callbacks.unreportedEmployeeNamesByEmail(page);
    return this.response(
      base,
      page.map((row: any) =>
        this.callbacks.mapUnreportedOrder(row, employeeNames),
      ),
      total,
      rows.length > base.limit ? (page.at(-1)?.orderCode ?? null) : null,
      startedAt,
    );
  }

  private async loadInstallmentNeeds(
    base: Omit<
      HomeSummaryBehaviorDetailsV2Response,
      'total' | 'items' | 'nextCursor'
    >,
    scope: SalesReportSummaryScopeDescriptor,
    range: SummaryDateRange,
    cursorId: string | null,
    startedAt: number,
  ) {
    const where: Prisma.SalesReportWhereInput = {
      AND: [
        this.callbacks.salesReportMainKpiWhere(scope, range),
        { installmentNeed: true },
      ],
    };
    const [total, rows] = await this.prisma.$transaction([
      this.prisma.salesReport.count({ where }),
      this.prisma.salesReport.findMany({
        where,
        orderBy: { id: 'asc' },
        take: base.limit + 1,
        ...(cursorId ? { cursor: { id: cursorId }, skip: 1 } : {}),
        select: {
          id: true,
          submittedAt: true,
          storeCode: true,
          createdByName: true,
          createdByEmail: true,
          orderCode: true,
          erpOrderId: true,
          installmentStatus: true,
          installmentFailureReason: true,
          installmentNoInstallmentReason: true,
          installmentPartnerCodes: true,
        },
      }),
    ]);
    const page = rows.slice(0, base.limit);
    return this.response(
      base,
      page.map((row: any) => this.callbacks.mapInstallmentNeed(row)),
      total,
      rows.length > base.limit ? (page.at(-1)?.id ?? null) : null,
      startedAt,
    );
  }

  private response(
    base: Omit<
      HomeSummaryBehaviorDetailsV2Response,
      'total' | 'items' | 'nextCursor'
    >,
    items: unknown[],
    total: number,
    nextId: string | null,
    startedAt: number,
  ): HomeSummaryBehaviorDetailsV2Response {
    const response = {
      ...base,
      total,
      items,
      nextCursor: nextId ? this.encodeCursor(base.kind, nextId) : null,
    };
    this.callbacks.logger.log(
      `Home summary details v2 load succeeded: kind=${base.kind} count=${items.length}/${total} hasNext=${Boolean(nextId)} durationMs=${Date.now() - startedAt}`,
    );
    return response;
  }

  private encodeCursor(kind: DetailsV2Kind, id: string) {
    return Buffer.from(JSON.stringify({ v: 1, kind, id }), 'utf8').toString(
      'base64url',
    );
  }

  private decodeCursor(cursor: string | undefined, kind: DetailsV2Kind) {
    if (!cursor) return null;
    try {
      const decoded = JSON.parse(
        Buffer.from(cursor, 'base64url').toString('utf8'),
      );
      const id = this.callbacks.optionalText(decoded?.id, 120);
      if (decoded?.v !== 1 || decoded?.kind !== kind || !id) throw new Error();
      return id;
    } catch {
      throw new BadRequestException(
        'Vị trí tải tiếp không hợp lệ. Vui lòng tải lại danh sách.',
      );
    }
  }
}
