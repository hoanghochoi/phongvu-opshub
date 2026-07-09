import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { FeatureService } from '../feature/feature.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import {
  SalesReportOperatingSummary,
  SalesReportSummaryScopeDescriptor,
  SalesReportsService,
} from '../sales-reports/sales-reports.service';
import {
  GetHomeSummaryDetailsQueryDto,
  GetHomeSummaryQueryDto,
} from './home-summary.dto';

const REPORT_TYPE_PURCHASED = 'PURCHASED';
const REPORT_TYPE_NOT_PURCHASED = 'NOT_PURCHASED';
const COVERAGE_LABEL = 'Tỉ lệ báo cáo';
const DEFAULT_HOME_SUMMARY_RANGE_DAYS = 30;
const DEFAULT_HOME_SUMMARY_DETAIL_LIMIT = 200;
const INSTALLMENT_SUCCESS = 'SUCCESS';
const INSTALLMENT_FAILED = 'FAILED';

const NOT_PURCHASED_LABELS: Record<string, string> = {
  NOT_SOLD: 'Chưa kinh doanh',
  SERVICE: 'Dịch vụ',
  CUSTOMER_BROWSING: 'Khách tham khảo',
  NO_DEMO_STOCK: 'Không có hàng trải nghiệm',
  NO_AVAILABLE_STOCK: 'Không có sẵn hàng',
  PRICE_HESITATION: 'Phân vân giá',
  COMPARE_COMPETITOR: 'So sánh đối thủ',
  SPEC_NOT_COMPATIBLE: 'Thông số kỹ thuật chưa tương thích',
  OTHER: 'Khác',
};

const CUSTOMER_TYPE_LABELS: Record<string, string> = {
  BUSINESS: 'Doanh nghiệp',
  PERSONAL: 'Cá nhân',
};

const INSTALLMENT_PARTNER_LABELS: Record<string, string> = {
  VNPAY_POS: 'VNPAY - POS',
  PAYOO_POS: 'PAYOO - POS',
  HOMECREDIT_CTTC: 'HomeCredit - CTTC',
  SHINHAN_CTTC: 'Shinhan - CTTC',
  HDSAISON_CTTC: 'HDSaison - CTTC',
  AEON_FINANCE_CTTC: 'AEON Finance - CTTC',
  MIRAE_ASSET: 'Mirae Asset',
  MPOS: 'MPOS',
};

const INSTALLMENT_NO_INSTALLMENT_REASON_LABELS: Record<string, string> = {
  NORMAL_INSTALLMENT: 'Khách chốt trả góp bình thường (Không có lý do)',
  BAD_CREDIT_HISTORY: 'Rớt hồ sơ: Tín dụng xấu (Nợ cũ, CIC...)',
  APPRAISAL_OR_INFO_ERROR: 'Rớt hồ sơ: Lỗi thẩm định/Thông tin',
  HIGH_INTEREST_OR_FEE: 'Khách từ chối: Lãi suất/Phí trả góp cao',
  MISSING_DOCUMENT_OR_CARD: 'Khách từ chối: Không đủ điều kiện giấy tờ/thẻ',
  PRICE_COMPETITOR_COMPARISON:
    'Khách từ chối: Giá cao/So sánh đối thủ (TGDĐ, FPT, CPS...)',
  BROWSING_OR_COME_BACK_LATER: 'Khách từ chối: Chỉ tham khảo/Hẹn quay lại',
};

type DateRange = {
  start: Date;
  end: Date;
};

type SummaryDateRange = DateRange & {
  startDate: string;
  endDate: string;
  legacyDate: string | null;
};

type HomeSummaryResponse = SalesReportOperatingSummary & {
  startDate: string;
  endDate: string;
  unavailableMessage: string | null;
  salesProgress: SalesProgressResponse;
  personalSalesProgress: SalesProgressResponse;
  scopeSalesProgress: SalesProgressResponse;
  salesProgressAssignees: SalesProgressAssigneeResponse[];
  selectedSalesProgressUserId: string | null;
  averageOrderValue: number;
  completedRevenue: number;
  pendingRevenue: number;
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
  consultedSolutionRate: number;
  experiencedRate: number;
  zaloRate: number;
  appDownloadRate: number;
};

type SalesProgressPeriod = {
  actual: number;
  target: number | null;
  percentage: number | null;
};

type SalesProgressResponse = {
  status: 'AVAILABLE' | 'MISSING' | 'PARTIAL' | 'NOT_APPLICABLE';
  scope: 'PERSONAL_SA' | 'MANAGED' | 'ALL' | null;
  missingStoreCodes: string[];
  range: SalesProgressPeriod;
  day: SalesProgressPeriod;
  week: SalesProgressPeriod;
  month: SalesProgressPeriod;
};

type SalesProgressAssigneeResponse = {
  userId: string;
  label: string;
  email: string | null;
  storeCodes: string[];
  isSelected: boolean;
  isCurrentUser: boolean;
};

type SalesProgressAssignee = SalesProgressAssigneeResponse & {
  firstName: string | null;
  lastName: string | null;
};

type SalesProgressBundle = {
  personal: SalesProgressResponse;
  scope: SalesProgressResponse;
  assignees: SalesProgressAssigneeResponse[];
  selectedUserId: string | null;
  selectedScope: SalesReportSummaryScopeDescriptor | null;
};

type HomeSummaryScopeRequest = 'AUTO' | 'ALL' | 'MANAGED_SCOPE' | 'OWN';

type HomeSummaryScopeOptionResponse = {
  value: string;
  label: string;
  scope: HomeSummaryScopeRequest;
  organizationNodeId: string | null;
  organizationNodeType: string | null;
  storeCount: number | null;
  isDefault: boolean;
};

type HomeSummaryNotPurchasedDetail = {
  id: string;
  submittedAt: Date;
  salesName: string | null;
  customerName: string | null;
  customerType: string | null;
  customerTypeLabel: string | null;
  categoryName: string | null;
  notPurchasedReason: string | null;
  notPurchasedReasonLabel: string | null;
};

type HomeSummaryUnreportedOrderDetail = {
  orderCode: string;
  soldAt: Date | null;
  salesName: string | null;
};

type HomeSummaryInstallmentNeedDetail = {
  id: string;
  submittedAt: Date;
  storeCode: string | null;
  salesName: string | null;
  orderCode: string | null;
  installmentPartnerLabels: string[];
  successful: boolean;
  note: string | null;
};

type HomeSummaryBehaviorDetailsResponse = {
  startDate: string;
  endDate: string;
  scope: string;
  scopeLabel: string;
  selectedSalesProgressUserId: string | null;
  limit: number;
  notPurchasedTotal: number;
  unreportedTotal: number;
  installmentNeedTotal: number;
  notPurchasedReports: HomeSummaryNotPurchasedDetail[];
  unreportedOrders: HomeSummaryUnreportedOrderDetail[];
  installmentNeedReports: HomeSummaryInstallmentNeedDetail[];
};

type SalesBehaviorYesCounts = {
  consultedSolution: number;
  experienced: number;
  zalo: number;
  appDownload: number;
};

type HomeSalesMainKpiSummary = {
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

@Injectable()
export class HomeSummaryService {
  private readonly logger = new Logger(HomeSummaryService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly salesReports: SalesReportsService,
    private readonly featureService: FeatureService,
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
    const range = this.parseSummaryRange(query);
    const date = range.endDate;
    const requestedScope = this.parseScopeParam(query.scope);
    const summaryDate = this.parseDateOnly(date) ?? new Date();
    const requestedSalesProgressUserId = this.optionalText(
      query.salesProgressUserId,
      80,
    );
    this.logger.log(
      `Home summary load started: user=${this.safeUserLabel(user)} startDate=${range.startDate} endDate=${range.endDate} scopeFilter=${requestedScope} salesProgressUserId=${requestedSalesProgressUserId || 'none'}`,
    );
    const { salesAvailable, financeAvailable } =
      await this.resolveSectionAccess(user);
    if (!salesAvailable && !financeAvailable) {
      const scope: SalesReportSummaryScopeDescriptor = {
        available: false,
        scope: 'UNAVAILABLE',
        scopeLabel: 'Chưa được cấp quyền',
        scopeDetail: null,
        unavailableMessage:
          'Tài khoản hiện chưa được cấp khu vực dashboard để xem.',
        ownUserId: null,
        ownEmail: null,
        ownPersonnelCode: null,
        allowedStoreCodes: [],
      };
      this.logger.log(
        `Home summary unavailable: user=${this.safeUserLabel(user)} startDate=${range.startDate} endDate=${range.endDate} scopeFilter=${requestedScope} reason=no_section_access durationMs=${Date.now() - startedAt}`,
      );
      return this.emptySummary(
        date,
        range,
        scope,
        new Date(),
        scope.unavailableMessage,
      );
    }
    const scope = await this.salesReports.describeHomeSummaryScope(
      user,
      requestedScope,
      this.optionalText(query.organizationNodeId, 80),
      { allowOwnScope: salesAvailable || financeAvailable },
    );
    if (!scope.available) {
      const response = this.emptySummary(
        date,
        range,
        scope,
        new Date(),
        scope.unavailableMessage,
      );
      this.logger.log(
        `Home summary unavailable: user=${this.safeUserLabel(user)} startDate=${range.startDate} endDate=${range.endDate} scopeFilter=${requestedScope} message=${scope.unavailableMessage || 'none'} durationMs=${Date.now() - startedAt}`,
      );
      return response;
    }

    let refreshedAt = new Date();
    if (salesAvailable || (financeAvailable && scope.scope === 'OWN')) {
      refreshedAt = await this.syncFactsForRange(range);
    }
    const salesProgressBundle = salesAvailable
      ? await this.buildSalesProgressBundle(
          user,
          scope,
          summaryDate,
          range,
          requestedSalesProgressUserId,
        )
      : this.emptySalesProgressBundle();
    const salesMetricsScope = salesProgressBundle.selectedScope ?? scope;
    const salesOrderWhere = this.orderScopeWhere(salesMetricsScope, range);

    let totalRevenue = 0;
    let totalOrders = 0;
    let totalReports = 0;
    let reportedOrders = 0;
    let notPurchasedReports = 0;
    let completedRevenue = 0;
    let mainKpis = this.emptyMainKpis();
    let behaviorYesCounts = this.emptyBehaviorYesCounts();
    if (salesAvailable) {
      const reportWhere = this.reportScopeWhere(salesMetricsScope, range);
      const [
        orderCount,
        reportCount,
        notPurchasedReportCount,
        reportedCodeRows,
      ] = await this.prisma.$transaction([
        this.homeSummaryOrderFact.count({ where: salesOrderWhere }),
        this.homeSummaryReportFact.count({ where: reportWhere }),
        this.homeSummaryReportFact.count({
          where: {
            ...reportWhere,
            reportType: REPORT_TYPE_NOT_PURCHASED,
          },
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
      totalOrders = orderCount;
      totalReports = reportCount;
      notPurchasedReports = notPurchasedReportCount;
      const reportedCodes = Array.from(
        new Set(
          reportedCodeRows
            .map((row: { orderCode: string | null }) =>
              this.normalizeOrderCode(row.orderCode),
            )
            .filter((value: string | null): value is string => Boolean(value)),
        ),
      );
      reportedOrders =
        reportedCodes.length > 0
          ? await this.homeSummaryOrderFact.count({
              where: {
                ...salesOrderWhere,
                orderCode: { in: reportedCodes },
              },
            })
          : 0;
      [totalRevenue, completedRevenue, behaviorYesCounts, mainKpis] =
        await Promise.all([
          this.totalCacheRevenue(salesMetricsScope, range),
          this.completedRevenue(salesMetricsScope, range),
          this.countBehaviorYesReports(salesMetricsScope, range),
          this.buildSalesMainKpis(salesMetricsScope, range),
        ]);
    }

    let totalStatements = 0;
    let totalTransferredAmount = 0;
    let totalStatementsWithOrder = 0;
    let totalStatementsWithoutOrder = 0;
    if (financeAvailable) {
      const financeOrderWhere = this.orderScopeWhere(scope, range);
      const personalOrderCodes =
        scope.scope === 'OWN'
          ? (
              await this.homeSummaryOrderFact.findMany({
                where: financeOrderWhere,
                select: { orderCode: true },
              })
            )
              .map((row: { orderCode: string | null }) =>
                this.normalizeOrderCode(row.orderCode),
              )
              .filter((value: string | null): value is string => Boolean(value))
          : [];
      const financeWhere = this.financeScopeWhere(
        scope,
        range,
        personalOrderCodes,
      );
      const [
        statementCount,
        transferredAmountSummary,
        statementWithOrderCount,
        statementWithoutOrderCount,
      ] = await this.prisma.$transaction([
        this.prisma.mapVietinTransaction.count({ where: financeWhere }),
        this.prisma.mapVietinTransaction.aggregate({
          where: financeWhere,
          _sum: { amount: true },
        }),
        this.prisma.mapVietinTransaction.count({
          where: this.andMapTransactionWhere(financeWhere, {
            orders: { isEmpty: false },
          }),
        }),
        this.prisma.mapVietinTransaction.count({
          where: this.andMapTransactionWhere(financeWhere, {
            orders: { isEmpty: true },
          }),
        }),
      ]);
      totalStatements = statementCount;
      totalTransferredAmount = transferredAmountSummary._sum.amount ?? 0;
      totalStatementsWithOrder = statementWithOrderCount;
      totalStatementsWithoutOrder = statementWithoutOrderCount;
    }
    const unreportedOrders = Math.max(totalOrders - reportedOrders, 0);
    const averageOrderValue = totalOrders
      ? Math.round(totalRevenue / totalOrders)
      : 0;
    const pendingRevenue = Math.max(totalRevenue - completedRevenue, 0);
    const coverageRate = totalOrders
      ? Number(((reportedOrders / totalOrders) * 100).toFixed(2))
      : 0;
    const conversionRate = totalReports
      ? Number(((totalOrders / totalReports) * 100).toFixed(2))
      : 0;
    const consultedSolutionRate = this.percentOf(
      behaviorYesCounts.consultedSolution,
      totalReports,
    );
    const experiencedRate = this.percentOf(
      behaviorYesCounts.experienced,
      totalReports,
    );
    const zaloRate = this.percentOf(behaviorYesCounts.zalo, totalReports);
    const appDownloadRate = this.percentOf(
      behaviorYesCounts.appDownload,
      totalReports,
    );
    const statementOrderRate = totalStatements
      ? Number(((totalStatementsWithOrder / totalStatements) * 100).toFixed(2))
      : 0;
    const response: HomeSummaryResponse = {
      date,
      startDate: range.startDate,
      endDate: range.endDate,
      available: true,
      scope: scope.scope,
      scopeLabel: scope.scopeLabel,
      scopeDetail: scope.scopeDetail,
      coverageLabel: COVERAGE_LABEL,
      totalRevenue,
      totalOrders,
      totalReports,
      reportedOrders,
      notPurchasedReports,
      unreportedOrders,
      averageOrderValue,
      completedRevenue,
      pendingRevenue,
      ...mainKpis,
      coverageRate,
      conversionRate,
      consultedSolutionRate,
      experiencedRate,
      zaloRate,
      appDownloadRate,
      salesAvailable,
      financeAvailable,
      totalTransferredAmount,
      totalStatements,
      totalStatementsWithOrder,
      totalStatementsWithoutOrder,
      statementOrderRate,
      salesProgress: salesProgressBundle.personal,
      personalSalesProgress: salesProgressBundle.personal,
      scopeSalesProgress: salesProgressBundle.scope,
      salesProgressAssignees: salesProgressBundle.assignees,
      selectedSalesProgressUserId: salesProgressBundle.selectedUserId,
      refreshedAt,
      unavailableMessage: null,
    };
    this.logger.log(
      `Home summary load succeeded: user=${this.safeUserLabel(user)} startDate=${range.startDate} endDate=${range.endDate} scopeFilter=${requestedScope} scope=${scope.scope} salesMetricsScope=${salesMetricsScope.scope} selectedSalesProgressUserId=${salesProgressBundle.selectedUserId || 'none'} salesProgressAssignees=${salesProgressBundle.assignees.length} salesAvailable=${salesAvailable} financeAvailable=${financeAvailable} totalRevenue=${totalRevenue} completedRevenue=${completedRevenue} pendingRevenue=${pendingRevenue} businessCustomerRevenue=${mainKpis.businessCustomerRevenue} personalCustomerRevenue=${mainKpis.personalCustomerRevenue} installmentNeedCount=${mainKpis.installmentNeedCount} successfulInstallmentCount=${mainKpis.successfulInstallmentCount} laptopQuantity=${mainKpis.laptopQuantity} pcQuantity=${mainKpis.pcQuantity} assembledPcQuantity=${mainKpis.assembledPcQuantity} appleQuantity=${mainKpis.appleQuantity} totalOrders=${totalOrders} averageOrderValue=${averageOrderValue} totalReports=${totalReports} reportedOrders=${reportedOrders} notPurchasedReports=${notPurchasedReports} consultedYes=${behaviorYesCounts.consultedSolution} experiencedYes=${behaviorYesCounts.experienced} zaloYes=${behaviorYesCounts.zalo} appDownloadYes=${behaviorYesCounts.appDownload} totalStatements=${totalStatements} statementsWithOrder=${totalStatementsWithOrder} durationMs=${Date.now() - startedAt}`,
    );
    return response;
  }

  async getBehaviorDetails(
    user: any,
    query: GetHomeSummaryDetailsQueryDto,
  ): Promise<HomeSummaryBehaviorDetailsResponse> {
    const startedAt = Date.now();
    const range = this.parseSummaryRange(query);
    const requestedScope = this.parseScopeParam(query.scope);
    const limit = this.normalizeDetailLimit(query.limit);
    const requestedSalesProgressUserId = this.optionalText(
      query.salesProgressUserId,
      80,
    );
    this.logger.log(
      `Home summary behavior details load started: user=${this.safeUserLabel(user)} startDate=${range.startDate} endDate=${range.endDate} scopeFilter=${requestedScope} salesProgressUserId=${requestedSalesProgressUserId || 'none'} limit=${limit}`,
    );

    const { salesAvailable } = await this.resolveSectionAccess(user);
    if (!salesAvailable) {
      this.logger.warn(
        `Home summary behavior details rejected: user=${this.safeUserLabel(user)} reason=no_sales_dashboard_access durationMs=${Date.now() - startedAt}`,
      );
      throw new ForbiddenException(
        'Bạn chưa có quyền xem chi tiết bán hàng trên dashboard.',
      );
    }

    const scope = await this.salesReports.describeHomeSummaryScope(
      user,
      requestedScope,
      this.optionalText(query.organizationNodeId, 80),
      { allowOwnScope: true },
    );
    if (!scope.available) {
      this.logger.warn(
        `Home summary behavior details unavailable: user=${this.safeUserLabel(user)} startDate=${range.startDate} endDate=${range.endDate} scopeFilter=${requestedScope} message=${scope.unavailableMessage || 'none'} durationMs=${Date.now() - startedAt}`,
      );
      throw new ForbiddenException(
        scope.unavailableMessage ||
          'Tài khoản hiện chưa có phạm vi dữ liệu để xem chi tiết.',
      );
    }

    const selectedSalesScope = await this.resolveSelectedSalesMetricsScope(
      user,
      scope,
      requestedSalesProgressUserId,
    );
    const salesMetricsScope = selectedSalesScope.scope;
    const reportWhere = this.reportScopeWhere(salesMetricsScope, range);
    const salesOrderWhere = this.orderScopeWhere(salesMetricsScope, range);
    const notPurchasedFactWhere = {
      ...reportWhere,
      reportType: REPORT_TYPE_NOT_PURCHASED,
    };
    const installmentNeedWhere: Prisma.SalesReportWhereInput = {
      AND: [
        this.salesReportMainKpiWhere(salesMetricsScope, range),
        { installmentNeed: true },
      ],
    };
    const reportedCodeRows = await this.homeSummaryReportFact.findMany({
      where: {
        ...reportWhere,
        reportType: REPORT_TYPE_PURCHASED,
        orderCode: { not: null },
      },
      select: { orderCode: true },
    });
    const reportedCodes = Array.from(
      new Set(
        reportedCodeRows
          .map((row: { orderCode: string | null }) =>
            this.normalizeOrderCode(row.orderCode),
          )
          .filter((value: string | null): value is string => Boolean(value)),
      ),
    );
    const unreportedWhere =
      reportedCodes.length > 0
        ? { AND: [salesOrderWhere, { orderCode: { notIn: reportedCodes } }] }
        : salesOrderWhere;

    const [
      notPurchasedTotal,
      notPurchasedFacts,
      unreportedTotal,
      unreportedOrders,
      installmentNeedTotal,
      installmentNeedReports,
    ] = await this.prisma.$transaction([
      this.homeSummaryReportFact.count({ where: notPurchasedFactWhere }),
      this.homeSummaryReportFact.findMany({
        where: notPurchasedFactWhere,
        orderBy: [{ submittedAt: 'desc' }],
        take: limit,
        select: { salesReportId: true },
      }),
      this.homeSummaryOrderFact.count({ where: unreportedWhere }),
      this.homeSummaryOrderFact.findMany({
        where: unreportedWhere,
        orderBy: [
          { orderCreatedAt: 'desc' },
          { fetchedAt: 'desc' },
          { updatedAt: 'desc' },
        ],
        take: limit,
        select: {
          orderCode: true,
          orderCreatedAt: true,
          fetchedAt: true,
          consultantName: true,
          consultantEmail: true,
          sellerName: true,
          sellerEmail: true,
          sourceUserEmail: true,
        },
      }),
      this.prisma.salesReport.count({ where: installmentNeedWhere }),
      this.prisma.salesReport.findMany({
        where: installmentNeedWhere,
        orderBy: [{ submittedAt: 'desc' }],
        take: limit,
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
    const reportIds = notPurchasedFacts
      .map((row: { salesReportId: string | null }) =>
        this.optionalText(row.salesReportId, 80),
      )
      .filter((value: string | null): value is string => Boolean(value));
    const notPurchasedReports =
      reportIds.length === 0
        ? []
        : await this.prisma.salesReport.findMany({
            where: { id: { in: reportIds } },
            orderBy: { submittedAt: 'desc' },
            select: {
              id: true,
              submittedAt: true,
              createdByName: true,
              createdByEmail: true,
              customerName: true,
              customerType: true,
              categoryGroupName: true,
              categoryGroupNameVi: true,
              notPurchasedReason: true,
              notPurchasedOtherReason: true,
            },
          });

    const response: HomeSummaryBehaviorDetailsResponse = {
      startDate: range.startDate,
      endDate: range.endDate,
      scope: salesMetricsScope.scope,
      scopeLabel: salesMetricsScope.scopeLabel,
      selectedSalesProgressUserId: selectedSalesScope.selectedUserId,
      limit,
      notPurchasedTotal,
      unreportedTotal,
      installmentNeedTotal,
      notPurchasedReports: notPurchasedReports.map((row: any) =>
        this.toHomeNotPurchasedDetail(row),
      ),
      unreportedOrders: unreportedOrders.map((row: any) =>
        this.toHomeUnreportedOrderDetail(row),
      ),
      installmentNeedReports: installmentNeedReports.map((row: any) =>
        this.toHomeInstallmentNeedDetail(row),
      ),
    };
    this.logger.log(
      `Home summary behavior details load succeeded: user=${this.safeUserLabel(user)} startDate=${range.startDate} endDate=${range.endDate} scope=${salesMetricsScope.scope} selectedSalesProgressUserId=${selectedSalesScope.selectedUserId || 'none'} notPurchased=${response.notPurchasedReports.length}/${notPurchasedTotal} unreported=${response.unreportedOrders.length}/${unreportedTotal} installmentNeed=${response.installmentNeedReports.length}/${installmentNeedTotal} limit=${limit} durationMs=${Date.now() - startedAt}`,
    );
    return response;
  }

  async listScopeOptions(user: any): Promise<HomeSummaryScopeOptionResponse[]> {
    this.logger.log(
      `Home summary scope options requested: user=${this.safeUserLabel(user)}`,
    );
    const { salesAvailable, financeAvailable } =
      await this.resolveSectionAccess(user);
    if (!salesAvailable && !financeAvailable) return [];
    return this.salesReports.listHomeSummaryScopeOptions(user, {
      allowOwnScope: salesAvailable || financeAvailable,
    });
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

  private async syncFactsForRange(range: SummaryDateRange) {
    let refreshedAt = new Date();
    for (
      const cursor = new Date(range.start);
      cursor < range.end;
      cursor.setUTCDate(cursor.getUTCDate() + 1)
    ) {
      const dayStart = new Date(cursor);
      refreshedAt = await this.syncFacts(
        this.formatVietnamDate(dayStart),
        dayStart,
      );
    }
    return refreshedAt;
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

  private personalStoreGuard(scope: SalesReportSummaryScopeDescriptor) {
    if (scope.scope !== 'OWN') return null;
    const storeCodes = this.normalizedStoreCodes(scope.allowedStoreCodes);
    return storeCodes.length > 0 ? { storeCode: { in: storeCodes } } : null;
  }

  private personalEmail(scope: SalesReportSummaryScopeDescriptor) {
    return this.normalizeEmail(scope.ownEmail);
  }

  private reportScopeWhere(
    scope: SalesReportSummaryScopeDescriptor,
    dateRange: DateRange,
  ) {
    const base = {
      summaryDate: { gte: dateRange.start, lt: dateRange.end },
    };
    if (scope.scope === 'ALL') return base;
    if (scope.scope === 'MANAGED_SCOPE') {
      return {
        AND: [base, { storeCode: { in: scope.allowedStoreCodes } }],
      };
    }
    const email = this.personalEmail(scope);
    if (!email) {
      return { AND: [base, { id: '__NO_PERSONAL_REPORT_FACT__' }] };
    }
    const filters: Record<string, unknown>[] = [
      base,
      { createdByEmail: { equals: email, mode: 'insensitive' } },
    ];
    const storeGuard = this.personalStoreGuard(scope);
    if (storeGuard) filters.push(storeGuard);
    return { AND: filters };
  }

  private orderScopeWhere(
    scope: SalesReportSummaryScopeDescriptor,
    dateRange: DateRange,
  ) {
    const base = {
      summaryDate: { gte: dateRange.start, lt: dateRange.end },
    };
    if (scope.scope === 'ALL') return base;
    if (scope.scope === 'MANAGED_SCOPE') {
      return {
        AND: [base, { storeCode: { in: scope.allowedStoreCodes } }],
      };
    }
    const email = this.personalEmail(scope);
    if (!email) {
      return { AND: [base, { id: '__NO_PERSONAL_ORDER_FACT__' }] };
    }
    const or: Record<string, unknown>[] = [
      { sourceUserEmail: { equals: email, mode: 'insensitive' } },
      { consultantEmail: { equals: email, mode: 'insensitive' } },
      { sellerEmail: { equals: email, mode: 'insensitive' } },
      { reportCreatedByEmail: { equals: email, mode: 'insensitive' } },
    ];
    const filters: Record<string, unknown>[] = [base, { OR: or }];
    const storeGuard = this.personalStoreGuard(scope);
    if (storeGuard) filters.push(storeGuard);
    return { AND: filters };
  }

  private orderCacheRevenueWhere(
    scope: SalesReportSummaryScopeDescriptor,
    dateRange: DateRange,
  ): Prisma.SalesReportErpOrderCacheWhereInput {
    const base: Prisma.SalesReportErpOrderCacheWhereInput = {
      excludedAt: null,
      ...this.orderCacheDateWhere(dateRange),
    };
    if (scope.scope === 'ALL') return base;
    if (scope.scope === 'MANAGED_SCOPE') {
      return { AND: [base, { storeCode: { in: scope.allowedStoreCodes } }] };
    }
    const email = this.personalEmail(scope);
    if (!email) {
      return { AND: [base, { id: '__NO_PERSONAL_ORDER_CACHE__' }] };
    }
    const or: Prisma.SalesReportErpOrderCacheWhereInput[] = [
      { sourceUserEmail: { equals: email, mode: 'insensitive' } },
      { consultantEmail: { equals: email, mode: 'insensitive' } },
      { sellerEmail: { equals: email, mode: 'insensitive' } },
    ];
    const filters: Prisma.SalesReportErpOrderCacheWhereInput[] = [
      base,
      { OR: or },
    ];
    const storeGuard = this.personalStoreGuard(scope);
    if (storeGuard) {
      filters.push(storeGuard as Prisma.SalesReportErpOrderCacheWhereInput);
    }
    return { AND: filters };
  }

  private financeScopeWhere(
    scope: SalesReportSummaryScopeDescriptor,
    dateRange: DateRange,
    personalOrderCodes: string[],
  ): Prisma.MapVietinTransactionWhereInput {
    const dateWhere: Prisma.MapVietinTransactionWhereInput = {
      OR: [
        { paidAt: { gte: dateRange.start, lt: dateRange.end } },
        {
          paidAt: null,
          firstSeenAt: { gte: dateRange.start, lt: dateRange.end },
        },
      ],
    };
    if (scope.scope === 'ALL') return dateWhere;
    if (scope.scope === 'OWN') {
      return this.andMapTransactionWhere(dateWhere, {
        orders: {
          hasSome:
            personalOrderCodes.length > 0
              ? personalOrderCodes
              : ['__NO_PERSONAL_ORDER__'],
        },
      });
    }
    return this.andMapTransactionWhere(dateWhere, {
      storeCode: { in: scope.allowedStoreCodes },
    });
  }

  private andMapTransactionWhere(
    ...parts: Prisma.MapVietinTransactionWhereInput[]
  ): Prisma.MapVietinTransactionWhereInput {
    const compact = parts.filter((part) => Object.keys(part).length > 0);
    if (compact.length === 0) return {};
    if (compact.length === 1) return compact[0];
    return { AND: compact };
  }

  private async buildSalesProgress(
    user: any,
    scope: SalesReportSummaryScopeDescriptor,
    summaryDate: Date,
    selectedRange: DateRange,
  ): Promise<SalesProgressResponse> {
    const ranges = this.salesProgressRanges(summaryDate);
    const progressRange = {
      start: selectedRange.start,
      end: selectedRange.end,
    };
    const queryRange = {
      start: new Date(
        Math.min(progressRange.start.getTime(), ranges.month.start.getTime()),
      ),
      end: new Date(
        Math.max(progressRange.end.getTime(), ranges.month.end.getTime()),
      ),
    };
    const rows = await this.prisma.salesReport.findMany({
      where: this.salesProgressReportWhere(scope, queryRange),
      select: {
        erpOrderCreatedAt: true,
        submittedAt: true,
        erpGrandTotal: true,
        erpReturnedAfterTaxAmount: true,
      },
    });
    const actualFor = (range: DateRange) =>
      rows.reduce((sum, row) => {
        const occurredAt = row.erpOrderCreatedAt ?? row.submittedAt;
        if (occurredAt < range.start || occurredAt >= range.end) return sum;
        const gross = Math.max(
          0,
          (row.erpGrandTotal ?? 0) - (row.erpReturnedAfterTaxAmount ?? 0),
        );
        return sum + Math.round(gross / 1.08);
      }, 0);
    const actuals = {
      range: actualFor(progressRange),
      day: actualFor(ranges.day),
      week: actualFor(ranges.week),
      month: actualFor(ranges.month),
    };

    let jobRoleCode = String(user?.jobRoleCode || '')
      .trim()
      .toUpperCase();
    if (scope.scope === 'OWN' && !jobRoleCode && user?.id) {
      const saved = await this.prisma.user.findUnique({
        where: { id: user.id },
        select: { jobRoleCode: true },
      });
      jobRoleCode = String(saved?.jobRoleCode || '')
        .trim()
        .toUpperCase();
    }
    if (scope.scope === 'OWN' && jobRoleCode !== 'SA') {
      return this.salesProgressWithActuals('NOT_APPLICABLE', null, [], actuals);
    }

    const stores = await this.prisma.store.findMany({
      where: {
        organizationNodeId: { not: null },
        organizationNode: { isActive: true },
        ...(scope.scope === 'ALL'
          ? {}
          : { storeId: { in: scope.allowedStoreCodes } }),
      },
      orderBy: { storeId: 'asc' },
      select: {
        storeId: true,
        organizationNodeId: true,
      },
    });
    const nodeIds = stores
      .map((store) => store.organizationNodeId)
      .filter((value): value is string => Boolean(value));
    const targets = nodeIds.length
      ? await this.prisma.salesTarget.findMany({
          where: {
            organizationNodeId: { in: nodeIds },
            monthStart: ranges.targetMonthStart,
          },
        })
      : [];
    const targetByNode = new Map(
      targets.map((target) => [
        target.organizationNodeId,
        Number(target.targetBeforeTax),
      ]),
    );
    const saCountByStore =
      scope.scope === 'OWN'
        ? await this.activeSaCountByStore(stores.map((store) => store.storeId))
        : new Map<string, number>();
    const missingStoreCodes: string[] = [];
    let monthlyTarget = 0;
    for (const store of stores) {
      const target = store.organizationNodeId
        ? targetByNode.get(store.organizationNodeId)
        : null;
      const saCount =
        scope.scope === 'OWN' ? (saCountByStore.get(store.storeId) ?? 0) : 1;
      if (target == null || saCount <= 0) {
        missingStoreCodes.push(store.storeId);
        continue;
      }
      monthlyTarget +=
        scope.scope === 'OWN' ? Math.round(target / saCount) : target;
    }
    if (stores.length === 0 || missingStoreCodes.length > 0) {
      return this.salesProgressWithActuals(
        targets.length === 0 ? 'MISSING' : 'PARTIAL',
        scope.scope === 'OWN'
          ? 'PERSONAL_SA'
          : scope.scope === 'ALL'
            ? 'ALL'
            : 'MANAGED',
        missingStoreCodes,
        actuals,
      );
    }
    const dayTarget = Math.round(monthlyTarget / ranges.daysInMonth);
    const weekTarget = Math.round(
      (monthlyTarget * ranges.weekDaysInMonth) / ranges.daysInMonth,
    );
    const selectedRangeDays = Math.max(
      1,
      Math.round(
        (progressRange.end.getTime() - progressRange.start.getTime()) /
          86_400_000,
      ),
    );
    const rangeTarget = Math.round(
      (monthlyTarget * selectedRangeDays) / ranges.daysInMonth,
    );
    const period = (actual: number, target: number): SalesProgressPeriod => ({
      actual,
      target,
      percentage: target > 0 ? Number(((actual / target) * 100).toFixed(2)) : 0,
    });
    return {
      status: 'AVAILABLE',
      scope:
        scope.scope === 'OWN'
          ? 'PERSONAL_SA'
          : scope.scope === 'ALL'
            ? 'ALL'
            : 'MANAGED',
      missingStoreCodes: [],
      range: period(actuals.range, rangeTarget),
      day: period(actuals.day, dayTarget),
      week: period(actuals.week, weekTarget),
      month: period(actuals.month, Math.round(monthlyTarget)),
    };
  }

  private async completedRevenue(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ) {
    const rows = await this.prisma.salesReport.findMany({
      where: this.salesProgressReportWhere(scope, range),
      select: {
        erpGrandTotal: true,
        erpReturnedAfterTaxAmount: true,
      },
    });
    return rows.reduce((sum, row) => {
      const gross = Math.max(
        0,
        (row.erpGrandTotal ?? 0) - (row.erpReturnedAfterTaxAmount ?? 0),
      );
      return sum + gross;
    }, 0);
  }

  private async totalCacheRevenue(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ) {
    const rows = await this.prisma.salesReportErpOrderCache.findMany({
      where: this.orderCacheRevenueWhere(scope, range),
      select: {
        grandTotal: true,
        lifecycleStatus: true,
        hasReturnedFullItems: true,
        returnedAfterTaxAmount: true,
      },
    });
    return rows.reduce((sum, row) => sum + this.netCacheRevenue(row), 0);
  }

  private netCacheRevenue(row: {
    grandTotal: number | null;
    lifecycleStatus: string;
    hasReturnedFullItems: boolean;
    returnedAfterTaxAmount: number;
  }) {
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
    return Math.max(0, (row.grandTotal ?? 0) - row.returnedAfterTaxAmount);
  }

  private async countBehaviorYesReports(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Promise<SalesBehaviorYesCounts> {
    const where = this.salesReportBehaviorWhere(scope, range);
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

  private emptyBehaviorYesCounts(): SalesBehaviorYesCounts {
    return {
      consultedSolution: 0,
      experienced: 0,
      zalo: 0,
      appDownload: 0,
    };
  }

  private percentOf(count: number, total: number) {
    return total ? Number(((count / total) * 100).toFixed(2)) : 0;
  }

  private async buildSalesMainKpis(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Promise<HomeSalesMainKpiSummary> {
    const rows = await this.prisma.salesReport.findMany({
      where: this.salesReportMainKpiWhere(scope, range),
      select: {
        id: true,
        reportType: true,
        orderCode: true,
        erpOrderId: true,
        customerType: true,
        erpGrandTotal: true,
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
    const summary = this.salesReports.summarizeSalesRevenueRows(rows);
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

  private emptyMainKpis(): HomeSalesMainKpiSummary {
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

  private async resolveSelectedSalesMetricsScope(
    user: any,
    scope: SalesReportSummaryScopeDescriptor,
    requestedUserId: string | null,
  ): Promise<{
    scope: SalesReportSummaryScopeDescriptor;
    selectedUserId: string | null;
  }> {
    const requested = this.optionalText(requestedUserId, 80);
    if (!requested) return { scope, selectedUserId: null };
    const assignees = await this.salesProgressAssigneesForScope(user, scope);
    const selected = this.selectSalesProgressAssignee(assignees, requested);
    if (!selected) return { scope, selectedUserId: null };
    return {
      scope: this.salesProgressScopeForAssignee(selected),
      selectedUserId: selected.userId,
    };
  }

  private async buildSalesProgressBundle(
    user: any,
    scope: SalesReportSummaryScopeDescriptor,
    summaryDate: Date,
    selectedRange: DateRange,
    requestedUserId: string | null,
  ): Promise<SalesProgressBundle> {
    const scopeProgressScope = this.scopeSalesProgressScope(scope);
    const [scopeProgress, assignees] = await Promise.all([
      scopeProgressScope
        ? this.buildSalesProgress(
            user,
            scopeProgressScope,
            summaryDate,
            selectedRange,
          )
        : Promise.resolve(this.emptySalesProgress()),
      this.salesProgressAssigneesForScope(user, scope),
    ]);
    const selectedAssignee =
      this.selectSalesProgressAssignee(assignees, requestedUserId) ?? null;
    const personalScope = selectedAssignee
      ? this.salesProgressScopeForAssignee(selectedAssignee)
      : scope.scope === 'OWN'
        ? scope
        : null;
    const personalProgress = personalScope
      ? await this.buildSalesProgress(
          selectedAssignee
            ? { id: selectedAssignee.userId, jobRoleCode: 'SA' }
            : user,
          personalScope,
          summaryDate,
          selectedRange,
        )
      : this.emptySalesProgress();
    const selectedUserId = selectedAssignee?.userId ?? null;
    return {
      personal: personalProgress,
      scope: scopeProgress,
      assignees: assignees.map((assignee) => ({
        userId: assignee.userId,
        label: assignee.label,
        email: assignee.email,
        storeCodes: assignee.storeCodes,
        isCurrentUser: assignee.isCurrentUser,
        isSelected: assignee.userId === selectedUserId,
      })),
      selectedUserId,
      selectedScope: selectedAssignee ? personalScope : null,
    };
  }

  private emptySalesProgressBundle(): SalesProgressBundle {
    return {
      personal: this.emptySalesProgress(),
      scope: this.emptySalesProgress(),
      assignees: [],
      selectedUserId: null,
      selectedScope: null,
    };
  }

  private scopeSalesProgressScope(
    scope: SalesReportSummaryScopeDescriptor,
  ): SalesReportSummaryScopeDescriptor | null {
    if (scope.scope === 'ALL') return scope;
    if (scope.scope === 'MANAGED_SCOPE') return scope;
    const allowedStoreCodes = this.normalizedStoreCodes(
      scope.allowedStoreCodes,
    );
    if (scope.scope !== 'OWN' || allowedStoreCodes.length === 0) return null;
    return {
      available: true,
      scope: 'MANAGED_SCOPE',
      scopeLabel: 'Cửa hàng',
      scopeDetail: scope.scopeDetail,
      unavailableMessage: null,
      ownUserId: null,
      ownEmail: null,
      ownPersonnelCode: null,
      allowedStoreCodes,
    };
  }

  private async salesProgressAssigneesForScope(
    user: any,
    scope: SalesReportSummaryScopeDescriptor,
  ): Promise<SalesProgressAssignee[]> {
    if (scope.scope !== 'MANAGED_SCOPE' && scope.scope !== 'ALL') return [];
    const allowedStoreCodes = await this.salesProgressAssigneeStoreCodes(scope);
    if (allowedStoreCodes.length === 0) return [];
    const allowed = new Set(allowedStoreCodes);
    const users = await this.prisma.user.findMany({
      where: { status: 'yes', jobRoleCode: 'SA' },
      include: {
        store: {
          include: {
            area: { include: { region: true } },
            organizationNode: true,
          },
        },
        area: { include: { region: true } },
        region: true,
        organizationNode: {
          include: organizationNodeStoreTreeInclude(),
        },
        organizationAssignments: {
          where: { isActive: true },
          orderBy: [
            { isPrimary: Prisma.SortOrder.desc },
            { createdAt: Prisma.SortOrder.asc },
          ],
          include: {
            organizationNode: {
              include: organizationNodeStoreTreeInclude(),
            },
          },
        },
      },
    });
    const assignees = users
      .map((candidate: any) =>
        this.salesProgressAssigneeFromUser(candidate, allowed, user),
      )
      .filter(
        (value: SalesProgressAssignee | null): value is SalesProgressAssignee =>
          value != null,
      )
      .sort((left, right) => {
        if (left.isCurrentUser !== right.isCurrentUser) {
          return left.isCurrentUser ? -1 : 1;
        }
        return left.label.localeCompare(right.label, 'vi');
      });
    return assignees;
  }

  private async salesProgressAssigneeStoreCodes(
    scope: SalesReportSummaryScopeDescriptor,
  ) {
    const scopedStoreCodes = this.normalizedStoreCodes(scope.allowedStoreCodes);
    if (scope.scope !== 'ALL' || scopedStoreCodes.length > 0) {
      return scopedStoreCodes;
    }
    const stores = await this.prisma.store.findMany({
      where: {
        organizationNodeId: { not: null },
        organizationNode: { isActive: true },
      },
      orderBy: { storeId: 'asc' },
      select: { storeId: true },
    });
    return this.normalizedStoreCodes(stores.map((store) => store.storeId));
  }

  private salesProgressAssigneeFromUser(
    candidate: any,
    allowed: Set<string>,
    currentUser: any,
  ): SalesProgressAssignee | null {
    const storeSources = this.storeSourcesForUser(candidate);
    const storeCodes = this.normalizedStoreCodes(
      storeSources.map((store) => store?.storeId),
    ).filter((code) => allowed.has(code));
    if (storeCodes.length === 0) return null;
    const userId = this.optionalText(candidate?.id, 80);
    if (!userId) return null;
    const email = this.normalizeEmail(candidate?.email);
    const firstName = this.optionalText(candidate?.firstName, 80);
    const lastName = this.optionalText(candidate?.lastName, 80);
    const fullName = [firstName, lastName].filter(Boolean).join(' ').trim();
    return {
      userId,
      firstName,
      lastName,
      email,
      storeCodes,
      label: fullName || email || `Nhân viên ${storeCodes.join(', ')}`,
      isCurrentUser: userId === this.optionalText(currentUser?.id, 80),
      isSelected: false,
    };
  }

  private selectSalesProgressAssignee(
    assignees: SalesProgressAssignee[],
    requestedUserId: string | null,
  ) {
    if (assignees.length === 0) return null;
    const requested = this.optionalText(requestedUserId, 80);
    if (requested) {
      const found = assignees.find((assignee) => assignee.userId === requested);
      if (found) return found;
    }
    return null;
  }

  private salesProgressScopeForAssignee(
    assignee: SalesProgressAssignee,
  ): SalesReportSummaryScopeDescriptor {
    return {
      available: true,
      scope: 'OWN',
      scopeLabel: 'Tổng quan cá nhân',
      scopeDetail: assignee.storeCodes.join(', '),
      unavailableMessage: null,
      ownUserId: null,
      ownEmail: assignee.email,
      ownPersonnelCode: null,
      allowedStoreCodes: assignee.storeCodes,
    };
  }

  private storeSourcesForUser(user: any) {
    const stores: any[] = [];
    const pushStore = (store?: any | null) => {
      const storeCode = this.normalizeStoreCode(store?.storeId);
      if (!storeCode) return;
      if (
        stores.some(
          (existing) =>
            this.normalizeStoreCode(existing?.storeId) === storeCode,
        )
      ) {
        return;
      }
      stores.push(store);
    };
    pushStore(user?.store);
    for (const store of storesForOrganizationNodeTree(user?.organizationNode)) {
      pushStore(store);
    }
    for (const assignment of user?.organizationAssignments ?? []) {
      for (const store of storesForOrganizationNodeTree(
        assignment?.organizationNode,
      )) {
        pushStore(store);
      }
    }
    return stores;
  }

  private normalizedStoreCodes(values: Array<string | null | undefined>) {
    const seen = new Set<string>();
    const normalized: string[] = [];
    for (const value of values) {
      const code = this.normalizeStoreCode(value);
      if (code && !seen.has(code)) {
        seen.add(code);
        normalized.push(code);
      }
    }
    return normalized;
  }

  private salesProgressReportWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Prisma.SalesReportWhereInput {
    const base: Prisma.SalesReportWhereInput = {
      reportType: REPORT_TYPE_PURCHASED,
      erpExcludedAt: null,
      erpLifecycleStatus: {
        in: ['COMPLETED', 'COMPLETED_PARTIAL_RETURN'],
      },
      OR: [
        { erpOrderCreatedAt: { gte: range.start, lt: range.end } },
        {
          AND: [
            { erpOrderCreatedAt: null },
            { submittedAt: { gte: range.start, lt: range.end } },
          ],
        },
      ],
    };
    if (scope.scope === 'ALL') return base;
    if (scope.scope === 'MANAGED_SCOPE') {
      return { AND: [base, { storeCode: { in: scope.allowedStoreCodes } }] };
    }
    const email = this.personalEmail(scope);
    if (!email) {
      return { AND: [base, { id: '__NO_PERSONAL_REPORT__' }] };
    }
    const filters: Prisma.SalesReportWhereInput[] = [
      base,
      { createdByEmail: { equals: email, mode: 'insensitive' } },
    ];
    const storeGuard = this.personalStoreGuard(scope);
    if (storeGuard) filters.push(storeGuard as Prisma.SalesReportWhereInput);
    return { AND: filters };
  }

  private salesReportBehaviorWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Prisma.SalesReportWhereInput {
    const base: Prisma.SalesReportWhereInput = {
      erpExcludedAt: null,
      ...this.reportedOrderDateWhere(range),
    };
    if (scope.scope === 'ALL') return base;
    if (scope.scope === 'MANAGED_SCOPE') {
      return { AND: [base, { storeCode: { in: scope.allowedStoreCodes } }] };
    }
    const email = this.personalEmail(scope);
    if (!email) {
      return { AND: [base, { id: '__NO_PERSONAL_BEHAVIOR_REPORT__' }] };
    }
    const filters: Prisma.SalesReportWhereInput[] = [
      base,
      { createdByEmail: { equals: email, mode: 'insensitive' } },
    ];
    const storeGuard = this.personalStoreGuard(scope);
    if (storeGuard) filters.push(storeGuard as Prisma.SalesReportWhereInput);
    return { AND: filters };
  }

  private salesReportMainKpiWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Prisma.SalesReportWhereInput {
    const base: Prisma.SalesReportWhereInput = {
      erpExcludedAt: null,
      ...this.reportedOrderDateWhere(range),
    };
    if (scope.scope === 'ALL') return base;
    if (scope.scope === 'MANAGED_SCOPE') {
      return { AND: [base, { storeCode: { in: scope.allowedStoreCodes } }] };
    }
    const email = this.personalEmail(scope);
    if (!email) {
      return { AND: [base, { id: '__NO_PERSONAL_MAIN_KPI_REPORT__' }] };
    }
    const filters: Prisma.SalesReportWhereInput[] = [
      base,
      { createdByEmail: { equals: email, mode: 'insensitive' } },
    ];
    const storeGuard = this.personalStoreGuard(scope);
    if (storeGuard) filters.push(storeGuard as Prisma.SalesReportWhereInput);
    return { AND: filters };
  }

  private salesProgressRanges(summaryDate: Date) {
    const local = new Date(summaryDate.getTime() + 7 * 60 * 60 * 1000);
    const year = local.getUTCFullYear();
    const monthIndex = local.getUTCMonth();
    const monthStart = new Date(
      Date.UTC(year, monthIndex, 1) - 7 * 60 * 60 * 1000,
    );
    const monthEnd = new Date(
      Date.UTC(year, monthIndex + 1, 1) - 7 * 60 * 60 * 1000,
    );
    const weekday = local.getUTCDay();
    const mondayOffset = (weekday + 6) % 7;
    const rawWeekStart = new Date(summaryDate);
    rawWeekStart.setUTCDate(rawWeekStart.getUTCDate() - mondayOffset);
    const rawWeekEnd = new Date(rawWeekStart);
    rawWeekEnd.setUTCDate(rawWeekEnd.getUTCDate() + 7);
    const weekStart = new Date(
      Math.max(rawWeekStart.getTime(), monthStart.getTime()),
    );
    const weekEnd = new Date(
      Math.min(rawWeekEnd.getTime(), monthEnd.getTime()),
    );
    const day = this.dateRangeFor(summaryDate);
    return {
      day,
      week: { start: weekStart, end: weekEnd },
      month: { start: monthStart, end: monthEnd },
      targetMonthStart: new Date(Date.UTC(year, monthIndex, 1)),
      daysInMonth: new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate(),
      weekDaysInMonth: Math.max(
        1,
        Math.round((weekEnd.getTime() - weekStart.getTime()) / 86_400_000),
      ),
    };
  }

  private async activeSaCountByStore(storeCodes: string[]) {
    const allowed = new Set(storeCodes.map((code) => code.toUpperCase()));
    const counts = new Map<string, number>();
    if (allowed.size === 0) return counts;
    const users = await this.prisma.user.findMany({
      where: { status: 'yes', jobRoleCode: 'SA' },
      include: {
        store: true,
        organizationNode: {
          include: organizationNodeStoreTreeInclude(),
        },
        organizationAssignments: {
          where: { isActive: true },
          include: {
            organizationNode: {
              include: organizationNodeStoreTreeInclude(),
            },
          },
        },
      },
    });
    for (const user of users) {
      const userStores = new Set<string>();
      if (user.store?.storeId) userStores.add(user.store.storeId.toUpperCase());
      for (const store of storesForOrganizationNodeTree(
        user.organizationNode,
      )) {
        if (store.storeId) userStores.add(String(store.storeId).toUpperCase());
      }
      for (const assignment of user.organizationAssignments) {
        for (const store of storesForOrganizationNodeTree(
          assignment.organizationNode,
        )) {
          if (store.storeId)
            userStores.add(String(store.storeId).toUpperCase());
        }
      }
      for (const storeCode of userStores) {
        if (allowed.has(storeCode)) {
          counts.set(storeCode, (counts.get(storeCode) ?? 0) + 1);
        }
      }
    }
    return counts;
  }

  private salesProgressWithActuals(
    status: SalesProgressResponse['status'],
    scope: SalesProgressResponse['scope'],
    missingStoreCodes: string[],
    actuals: { range: number; day: number; week: number; month: number },
  ): SalesProgressResponse {
    const period = (actual: number): SalesProgressPeriod => ({
      actual,
      target: null,
      percentage: null,
    });
    return {
      status,
      scope,
      missingStoreCodes,
      range: period(actuals.range),
      day: period(actuals.day),
      week: period(actuals.week),
      month: period(actuals.month),
    };
  }

  private emptySalesProgress(): SalesProgressResponse {
    return this.salesProgressWithActuals('NOT_APPLICABLE', null, [], {
      range: 0,
      day: 0,
      week: 0,
      month: 0,
    });
  }

  private async resolveSectionAccess(user: any) {
    const [salesAvailable, financeAvailable] = await Promise.all([
      this.featureService.canAccessFeature(
        user,
        FEATURE_KEYS.HOME_DASHBOARD_SALES,
      ),
      this.featureService.canAccessFeature(
        user,
        FEATURE_KEYS.HOME_DASHBOARD_FINANCE,
      ),
    ]);
    return { salesAvailable, financeAvailable };
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
    range: SummaryDateRange,
    scope: SalesReportSummaryScopeDescriptor,
    refreshedAt: Date,
    unavailableMessage: string | null,
  ): HomeSummaryResponse {
    return {
      date,
      startDate: range.startDate,
      endDate: range.endDate,
      available: false,
      scope: scope.scope,
      scopeLabel: scope.scopeLabel,
      scopeDetail: scope.scopeDetail,
      coverageLabel: COVERAGE_LABEL,
      totalRevenue: 0,
      totalOrders: 0,
      totalReports: 0,
      reportedOrders: 0,
      notPurchasedReports: 0,
      unreportedOrders: 0,
      averageOrderValue: 0,
      completedRevenue: 0,
      pendingRevenue: 0,
      ...this.emptyMainKpis(),
      coverageRate: 0,
      conversionRate: 0,
      consultedSolutionRate: 0,
      experiencedRate: 0,
      zaloRate: 0,
      appDownloadRate: 0,
      salesAvailable: false,
      financeAvailable: false,
      totalTransferredAmount: 0,
      totalStatements: 0,
      totalStatementsWithOrder: 0,
      totalStatementsWithoutOrder: 0,
      statementOrderRate: 0,
      salesProgress: this.emptySalesProgress(),
      personalSalesProgress: this.emptySalesProgress(),
      scopeSalesProgress: this.emptySalesProgress(),
      salesProgressAssignees: [],
      selectedSalesProgressUserId: null,
      refreshedAt,
      unavailableMessage,
    };
  }

  private dateRangeFor(summaryDate: Date): DateRange {
    const end = new Date(summaryDate);
    end.setUTCDate(end.getUTCDate() + 1);
    return { start: summaryDate, end };
  }

  private parseSummaryRange(query: GetHomeSummaryQueryDto): SummaryDateRange {
    const legacyDate = this.parseDateParam(query.date);
    const today = this.todayVietnamDate();
    const explicitStart = this.parseDateParam(query.startDate);
    const explicitEnd = this.parseDateParam(query.endDate);
    let startDate: string;
    let endDate: string;

    if (explicitStart || explicitEnd) {
      startDate = explicitStart ?? explicitEnd ?? today;
      endDate = explicitEnd ?? explicitStart ?? today;
    } else if (legacyDate) {
      startDate = legacyDate;
      endDate = legacyDate;
    } else {
      endDate = today;
      startDate = this.addVietnamDays(
        endDate,
        -(DEFAULT_HOME_SUMMARY_RANGE_DAYS - 1),
      );
    }

    const start = this.parseDateOnly(startDate);
    const endStart = this.parseDateOnly(endDate);
    if (!start || !endStart) {
      throw new BadRequestException('Khoảng ngày chưa đúng định dạng.');
    }
    if (endStart < start) {
      throw new BadRequestException(
        'Ngày kết thúc phải bằng hoặc sau ngày bắt đầu.',
      );
    }
    const end = new Date(endStart);
    end.setUTCDate(end.getUTCDate() + 1);
    return { startDate, endDate, legacyDate, start, end };
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
    return this.formatVietnamDate(new Date());
  }

  private addVietnamDays(dateText: string, days: number) {
    const date = this.parseDateOnly(dateText) ?? new Date();
    date.setUTCDate(date.getUTCDate() + days);
    return this.formatVietnamDate(date);
  }

  private formatVietnamDate(value: Date) {
    const local = new Date(value.getTime() + 7 * 60 * 60 * 1000);
    const two = (part: number) => String(part).padStart(2, '0');
    return `${local.getUTCFullYear()}-${two(local.getUTCMonth() + 1)}-${two(local.getUTCDate())}`;
  }

  private normalizeOrderCode(value: unknown) {
    const text = String(value || '')
      .trim()
      .replace(/\s+/g, '');
    return text || null;
  }

  private normalizeStoreCode(value: unknown) {
    const text = String(value || '')
      .trim()
      .toUpperCase();
    return text || null;
  }

  private normalizeEmail(value: unknown) {
    const text = String(value || '')
      .trim()
      .toLowerCase();
    return text || null;
  }

  private optionalText(value: unknown, maxLength: number) {
    const text = String(value || '').trim();
    if (!text) return null;
    return text.slice(0, maxLength);
  }

  private normalizeDetailLimit(value?: number | null) {
    const parsed = Number(value ?? DEFAULT_HOME_SUMMARY_DETAIL_LIMIT);
    if (!Number.isFinite(parsed)) return DEFAULT_HOME_SUMMARY_DETAIL_LIMIT;
    return Math.min(500, Math.max(1, Math.floor(parsed)));
  }

  private toHomeNotPurchasedDetail(row: any): HomeSummaryNotPurchasedDetail {
    const customerType = this.optionalText(row.customerType, 40);
    const reason = this.optionalText(row.notPurchasedReason, 80);
    return {
      id: String(row.id),
      submittedAt: row.submittedAt,
      salesName: this.displayPersonName(row.createdByName, row.createdByEmail),
      customerName: this.optionalText(row.customerName, 160),
      customerType,
      customerTypeLabel: customerType
        ? this.customerTypeLabel(customerType)
        : null,
      categoryName:
        this.optionalText(row.categoryGroupNameVi, 160) ??
        this.optionalText(row.categoryGroupName, 160),
      notPurchasedReason: reason,
      notPurchasedReasonLabel: this.notPurchasedReasonLabel(
        reason,
        row.notPurchasedOtherReason,
      ),
    };
  }

  private toHomeUnreportedOrderDetail(
    row: any,
  ): HomeSummaryUnreportedOrderDetail {
    return {
      orderCode: this.normalizeOrderCode(row.orderCode) ?? '',
      soldAt: row.orderCreatedAt ?? row.fetchedAt ?? null,
      salesName: this.displayPersonName(
        row.consultantName ?? row.sellerName,
        row.consultantEmail ?? row.sellerEmail ?? row.sourceUserEmail,
      ),
    };
  }

  private toHomeInstallmentNeedDetail(
    row: any,
  ): HomeSummaryInstallmentNeedDetail {
    const orderCode =
      this.normalizeOrderCode(row.orderCode) ??
      this.normalizeOrderCode(row.erpOrderId);
    const successful = this.isReportedInstallmentSuccess(row);
    const failureNote =
      this.optionalText(row.installmentFailureReason, 240) ??
      this.installmentNoInstallmentReasonLabel(
        this.optionalText(row.installmentNoInstallmentReason, 80),
      );
    return {
      id: String(row.id),
      submittedAt: row.submittedAt,
      storeCode: this.normalizeStoreCode(row.storeCode),
      salesName: this.displayPersonName(row.createdByName, row.createdByEmail),
      orderCode,
      installmentPartnerLabels: this.installmentPartnerLabels(
        row.installmentPartnerCodes,
      ),
      successful,
      note: successful ? orderCode : failureNote,
    };
  }

  private displayPersonName(name: unknown, email: unknown) {
    return this.optionalText(name, 120) ?? this.normalizeEmail(email) ?? null;
  }

  private customerTypeLabel(code: string) {
    return CUSTOMER_TYPE_LABELS[code] ?? code;
  }

  private notPurchasedReasonLabel(code: string | null, other: unknown) {
    if (!code) return null;
    const label = NOT_PURCHASED_LABELS[code] ?? code;
    const otherText = this.optionalText(other, 240);
    return code === 'OTHER' && otherText ? `${label}: ${otherText}` : label;
  }

  private installmentPartnerLabels(value: unknown) {
    const raw = Array.isArray(value) ? value : [];
    return raw
      .map((item) =>
        String(item || '')
          .trim()
          .toUpperCase(),
      )
      .filter((code) => code.length > 0)
      .map((code) => INSTALLMENT_PARTNER_LABELS[code] ?? code);
  }

  private installmentNoInstallmentReasonLabel(code: string | null) {
    if (!code) return null;
    return INSTALLMENT_NO_INSTALLMENT_REASON_LABELS[code] ?? code;
  }

  private isReportedInstallmentSuccess(row: any) {
    const status = String(row?.installmentStatus || '')
      .trim()
      .toUpperCase();
    if (status === INSTALLMENT_SUCCESS) return true;
    if (status === INSTALLMENT_FAILED) return false;
    return (
      String(row?.installmentNoInstallmentReason || '')
        .trim()
        .toUpperCase() === 'NORMAL_INSTALLMENT'
    );
  }

  private safeUserLabel(user: any) {
    return (
      this.normalizeEmail(user?.email) ||
      this.optionalText(user?.id, 80) ||
      'missing'
    );
  }
}
