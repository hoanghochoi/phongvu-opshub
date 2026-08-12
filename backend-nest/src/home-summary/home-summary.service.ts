import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  Optional,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash } from 'crypto';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { FeatureService } from '../feature/feature.service';
import { AuthContextService } from '../auth/auth-context.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { logFingerprint, safeLogError } from '../common/log-sanitizer';
import {
  SalesReportOperatingSummary,
  SalesReportSummaryScopeDescriptor,
  SalesReportsService,
} from '../sales-reports/sales-reports.service';
import { isSalesReportErpPendingPaymentStatus } from '../sales-reports/sales-report-erp.service';
import {
  buildCanonicalRevenueLookup,
  canonicalRevenueForOrder,
  canonicalVatIncludedRevenue,
  CanonicalRevenueLookup,
  normalizeRevenueOrderCode,
  SALES_PRICE_CONTRACT_VERSION,
} from '../sales-reports/sales-report-revenue';
import {
  GetHomeSummaryDetailsQueryDto,
  GetHomeSummaryDetailsV2QueryDto,
  GetHomeSummaryQueryDto,
} from './home-summary.dto';
import { HOME_SALES_KPI_CONTRACT_VERSION } from './home-summary-contract';

const REPORT_TYPE_PURCHASED = 'PURCHASED';
const REPORT_TYPE_NOT_PURCHASED = 'NOT_PURCHASED';
const COVERAGE_LABEL = 'Tỉ lệ báo cáo';
const DEFAULT_HOME_SUMMARY_RANGE_DAYS = 30;
const DEFAULT_HOME_SUMMARY_DETAIL_LIMIT = 200;
const HOME_SUMMARY_RESPONSE_CACHE_TTL_MS = 60_000;
const HOME_SUMMARY_SUPPORT_CACHE_TTL_MS = 5_000;
const HOME_SUMMARY_CACHE_DIAGNOSTIC_LOG_INTERVAL_MS = 15_000;
const HOME_SUMMARY_RESPONSE_REFRESH_AHEAD_MIN_MS = 30_000;
const HOME_SUMMARY_RESPONSE_REFRESH_AHEAD_SPREAD_MS = 20_000;
const MAX_HOME_SUMMARY_RESPONSE_CACHE_ENTRIES = 1000;
const HOME_SUMMARY_SCOPE_OPTIONS_L1_TTL_MS = 5_000;
const HOME_SUMMARY_SCOPE_OPTIONS_REDIS_TTL_SECONDS = 60;
const HOME_SUMMARY_SCOPE_OPTIONS_LEASE_TTL_MS = 5_000;
const MAX_HOME_SUMMARY_SCOPE_OPTIONS_CACHE_ENTRIES = 1000;
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
  freshness: HomeSummaryFreshnessResponse | null;
  dailySeries?: HomeSummaryDailyPoint[];
  comparisons?: HomeSummaryComparisonsResponse;
};

const HOME_SALES_COMPARISON_METRIC_KEYS = [
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

type HomeSalesComparisonMetricKey =
  (typeof HOME_SALES_COMPARISON_METRIC_KEYS)[number];

const CSV_SUPPORTED_COMPARISON_METRICS = new Set<HomeSalesComparisonMetricKey>([
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

const METRIC_COMPARISON_QUANTITY_KEYS = [
  'extendedInsuranceQuantity',
  'laptopQuantity',
  'pcQuantity',
  'assembledPcQuantity',
  'appleQuantity',
  'monitorQuantity',
  'printerQuantity',
  'accessoriesQuantity',
] as const;

type HomeSummaryComparisonMetricResponse = {
  value: number | null;
  deltaPercent: number | null;
  status: 'AVAILABLE' | 'NEW' | 'UNAVAILABLE';
};

type HomeSummaryComparisonPeriodResponse = {
  startDate: string;
  endDate: string;
  source: 'OPSHUB' | 'HYBRID_CSV' | 'UNAVAILABLE';
  complete: boolean;
  metrics: Record<
    HomeSalesComparisonMetricKey,
    HomeSummaryComparisonMetricResponse
  >;
};

type HomeSummaryComparisonsResponse = {
  previousMonth: HomeSummaryComparisonPeriodResponse;
  previousYear: HomeSummaryComparisonPeriodResponse;
};

type HomeSummaryDailyPoint = {
  date: string;
  totalRevenue: number;
  totalOrders: number;
  reportedOrders: number;
  totalReports: number;
};

type HomeSummaryFreshnessResponse = {
  projectionGeneratedAt: Date;
  projectionLagSeconds: number;
  projectionVersion: number;
  sourceUpdatedAtBySource: Record<string, Date>;
  isStale: boolean;
};

type HomeSummaryResponseCacheEntry = {
  expiresAt: number;
  refreshAfter: number;
  refreshAttempted: boolean;
  startDate: string;
  endDate: string;
  projectionVersionsByDate: Map<string, number>;
  response: HomeSummaryResponse;
};

type HomeSummaryInFlightEntry = {
  promise: Promise<HomeSummaryResponse>;
  startDate: string;
  endDate: string;
  invalidated: boolean;
  source: 'miss' | 'refresh_ahead' | 'daily_extension';
};

type HomeSummarySupportCacheEntry<T> = {
  expiresAt: number;
  value: T;
};

type HomeSummaryComputationContext = {
  useProjection: boolean;
  salesAvailable: boolean;
  salesMetricsScope: SalesReportSummaryScopeDescriptor;
};

export type HomeSummaryProjectionInvalidation = {
  affectedDates: string[];
  projectionVersion: number;
};

type HomeSummaryProjectionSnapshot = {
  freshness: HomeSummaryFreshnessResponse;
  versionsByDate: Map<string, number>;
};

type HomeProjectionKind = 'SALES' | 'FINANCE';

type HomeProjectionMetrics = {
  totalOrders: number;
  reportedOrders: number;
  totalReports: number;
  notPurchasedReports: number;
  totalRevenue: number;
  completedRevenue: number;
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
  consultedSolutionYes: number;
  experiencedYes: number;
  zaloYes: number;
  appDownloadYes: number;
  totalTransferredAmount: number;
  totalStatements: number;
  totalStatementsTracked: number;
  totalStatementsUnfollowed: number;
  totalStatementsWithOrder: number;
  totalStatementsWithoutOrder: number;
};

type HomeProjectionLoadResult = HomeProjectionMetrics & {
  dailySeries?: HomeSummaryDailyPoint[];
};

type HomeSummaryScopeOptionsCacheEntry = {
  expiresAt: number;
  response: HomeSummaryScopeOptionResponse[];
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
  storeCode: string | null;
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
  grandTotal: number | null;
  soldAt: Date | null;
  storeCode: string | null;
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
  private readonly summaryResponseCache = new Map<
    string,
    HomeSummaryResponseCacheEntry
  >();
  private readonly summaryInFlight = new Map<
    string,
    HomeSummaryInFlightEntry
  >();
  private readonly projectionVersionsByResponse = new WeakMap<
    HomeSummaryResponse,
    Map<string, number>
  >();
  private readonly computationContextByResponse = new WeakMap<
    HomeSummaryResponse,
    HomeSummaryComputationContext
  >();
  private readonly projectionFreshnessCache = new Map<
    string,
    HomeSummarySupportCacheEntry<HomeSummaryProjectionSnapshot>
  >();
  private readonly projectionFreshnessInFlight = new Map<
    string,
    Promise<HomeSummaryProjectionSnapshot>
  >();
  private readonly salesProgressBundleCache = new Map<
    string,
    HomeSummarySupportCacheEntry<SalesProgressBundle>
  >();
  private readonly salesProgressBundleInFlight = new Map<
    string,
    Promise<SalesProgressBundle>
  >();
  private readonly scopedSalesProgressCache = new Map<
    string,
    HomeSummarySupportCacheEntry<SalesProgressResponse>
  >();
  private readonly scopedSalesProgressInFlight = new Map<
    string,
    Promise<SalesProgressResponse>
  >();
  private readonly cacheDiagnosticLogAtByBranch = new Map<string, number>();
  private supportCacheGeneration = 0;
  private readonly latestProjectionVersionByDate = new Map<string, number>();
  private readonly scopeOptionsCache = new Map<
    string,
    HomeSummaryScopeOptionsCacheEntry
  >();
  private readonly scopeOptionsInFlight = new Map<
    string,
    Promise<HomeSummaryScopeOptionResponse[]>
  >();

  constructor(
    private readonly prisma: PrismaService,
    private readonly salesReports: SalesReportsService,
    private readonly featureService: FeatureService,
    @Optional() private readonly authContextService?: AuthContextService,
    @Optional() private readonly redis?: RedisService,
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
    if (!this.summaryResponseCacheEnabled()) {
      return this.computeSummary(user, query);
    }
    const cacheKey = this.summaryResponseCacheKey(user, query);
    const cacheLabel = logFingerprint(cacheKey);
    const range = this.parseSummaryRange(query);
    const cached = this.summaryResponseCache.get(cacheKey);
    const now = Date.now();
    if (cached && cached.expiresAt > now) {
      this.maybeStartSummaryRefreshAhead(
        cacheKey,
        cacheLabel,
        cached,
        user,
        query,
        range,
        now,
      );
      this.logCacheDiagnostic(
        'response_hit',
        `Home summary cache hit: key=${cacheLabel} ttlMs=${cached.expiresAt - now}`,
      );
      return cached.response;
    }
    if (cached) {
      this.summaryResponseCache.delete(cacheKey);
      this.logCacheDiagnostic(
        'response_expired',
        `Home summary cache expired: key=${cacheLabel}`,
      );
    }
    const pending = this.summaryInFlight.get(cacheKey);
    if (pending && !pending.invalidated) {
      this.logCacheDiagnostic(
        'response_join',
        `Home summary cache joined in-flight: key=${cacheLabel}`,
      );
      return pending.promise;
    }
    if (pending?.invalidated) {
      this.logger.log(
        `Home summary cache follow-up started: key=${cacheLabel} source=${pending.source}`,
      );
    }

    const dailyExtension = this.maybeStartDailySeriesExtension(
      cacheKey,
      cacheLabel,
      user,
      query,
      range,
      now,
    );
    if (dailyExtension) return dailyExtension;

    this.logger.log(`Home summary cache miss: key=${cacheLabel}`);
    return this.startSummaryLoad(
      cacheKey,
      cacheLabel,
      user,
      query,
      range,
      'miss',
    );
  }

  invalidateSummaryResponseCache(
    updates: HomeSummaryProjectionInvalidation[],
    source = 'projection_event',
  ) {
    const changedVersionsByDate = new Map<string, number | null>();
    let ignoredUpdates = 0;
    for (const update of updates) {
      const version = Number(update.projectionVersion);
      const validVersion = Number.isSafeInteger(version) && version > 0;
      for (const rawDate of update.affectedDates ?? []) {
        const date = String(rawDate).trim();
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
          ignoredUpdates += 1;
          continue;
        }
        if (!validVersion) {
          changedVersionsByDate.set(date, null);
          continue;
        }
        const previous = changedVersionsByDate.get(date);
        if (
          previous === null ||
          (previous !== undefined && version <= previous)
        ) {
          ignoredUpdates += 1;
          continue;
        }
        changedVersionsByDate.set(date, version);
      }
    }
    for (const [date, version] of changedVersionsByDate) {
      if (version === null) continue;
      const previous = this.latestProjectionVersionByDate.get(date) ?? 0;
      if (version <= previous) {
        changedVersionsByDate.delete(date);
        ignoredUpdates += 1;
        continue;
      }
      this.latestProjectionVersionByDate.set(date, version);
    }
    const invalidatedSupportEntries =
      changedVersionsByDate.size > 0 ? this.clearSummarySupportCaches() : 0;

    let invalidatedCacheEntries = 0;
    let coveredCacheEntries = 0;
    for (const [cacheKey, entry] of this.summaryResponseCache.entries()) {
      if (!this.cacheEntryNeedsInvalidation(entry, changedVersionsByDate)) {
        if (this.rangeOverlapsDates(entry, changedVersionsByDate.keys())) {
          coveredCacheEntries += 1;
        }
        continue;
      }
      this.summaryResponseCache.delete(cacheKey);
      invalidatedCacheEntries += 1;
    }

    let invalidatedInFlight = 0;
    for (const [cacheKey, entry] of this.summaryInFlight) {
      const cached = this.summaryResponseCache.get(cacheKey);
      if (
        entry.invalidated ||
        (cached &&
          !this.cacheEntryNeedsInvalidation(cached, changedVersionsByDate)) ||
        !this.rangeOverlapsDates(entry, changedVersionsByDate.keys())
      ) {
        continue;
      }
      entry.invalidated = true;
      invalidatedInFlight += 1;
    }

    this.logger.log(
      `Home summary cache invalidated: source=${source} affectedDates=${changedVersionsByDate.size} cacheEntries=${invalidatedCacheEntries} coveredCacheEntries=${coveredCacheEntries} supportEntries=${invalidatedSupportEntries} inFlightMarked=${invalidatedInFlight} ignoredUpdates=${ignoredUpdates}`,
    );
    return {
      affectedDates: changedVersionsByDate.size,
      invalidatedCacheEntries,
      coveredCacheEntries,
      invalidatedSupportEntries,
      invalidatedInFlight,
      ignoredUpdates,
    };
  }

  private maybeStartSummaryRefreshAhead(
    cacheKey: string,
    cacheLabel: string,
    cached: HomeSummaryResponseCacheEntry,
    user: any,
    query: GetHomeSummaryQueryDto,
    range: SummaryDateRange,
    now: number,
  ) {
    if (cached.refreshAttempted || now < cached.refreshAfter) return;
    cached.refreshAttempted = true;
    const pending = this.summaryInFlight.get(cacheKey);
    if (pending && !pending.invalidated) return;
    this.logger.log(
      `Home summary cache refresh-ahead started: key=${cacheLabel} ttlMs=${cached.expiresAt - now}`,
    );
    void this.startSummaryLoad(
      cacheKey,
      cacheLabel,
      user,
      query,
      range,
      'refresh_ahead',
    ).catch((error) => {
      this.logger.warn(
        `Home summary cache refresh-ahead failed: key=${cacheLabel} error=${safeLogError(error)}`,
      );
    });
  }

  private startSummaryLoad(
    cacheKey: string,
    cacheLabel: string,
    user: any,
    query: GetHomeSummaryQueryDto,
    range: SummaryDateRange,
    source: HomeSummaryInFlightEntry['source'],
  ) {
    const cacheRange = this.summaryCacheCoverageRange(range, query);
    let inFlight: HomeSummaryInFlightEntry;
    const promise = this.computeSummary(user, query)
      .then((response) => {
        if (inFlight.invalidated) {
          this.logger.log(
            `Home summary cache stale store skipped: key=${cacheLabel} source=${source}`,
          );
          return response;
        }
        this.storeSummaryResponseCache(cacheKey, response, cacheRange);
        this.logger.log(
          `Home summary cache stored: key=${cacheLabel} source=${source} ttlMs=${HOME_SUMMARY_RESPONSE_CACHE_TTL_MS}`,
        );
        return response;
      })
      .finally(() => {
        if (this.summaryInFlight.get(cacheKey) === inFlight) {
          this.summaryInFlight.delete(cacheKey);
        }
      });
    inFlight = {
      promise,
      startDate: cacheRange.startDate,
      endDate: cacheRange.endDate,
      invalidated: false,
      source,
    };
    this.summaryInFlight.set(cacheKey, inFlight);
    return promise;
  }

  private maybeStartDailySeriesExtension(
    cacheKey: string,
    cacheLabel: string,
    user: any,
    query: GetHomeSummaryQueryDto,
    range: SummaryDateRange,
    now: number,
  ) {
    if (query.includeDailySeries !== 'true') return null;
    const days = this.rangeDateKeys(range.startDate, range.endDate).length;
    if (days > 90) return null;
    const legacyQuery: GetHomeSummaryQueryDto = {
      ...query,
      includeDailySeries: 'false',
    };
    const legacyKey = this.summaryResponseCacheKey(user, legacyQuery);
    const legacy = this.summaryResponseCache.get(legacyKey);
    if (!legacy || legacy.expiresAt <= now) return null;
    const context = this.computationContextByResponse.get(legacy.response);
    if (!context?.useProjection || !context.salesAvailable) return null;

    this.logger.log(
      `Home summary daily cache extension started: key=${cacheLabel} days=${days} scope=${context.salesMetricsScope.scope}`,
    );
    return this.startDailySeriesExtension(
      cacheKey,
      cacheLabel,
      user,
      query,
      range,
      legacy.response,
      context,
    );
  }

  private startDailySeriesExtension(
    cacheKey: string,
    cacheLabel: string,
    user: any,
    query: GetHomeSummaryQueryDto,
    range: SummaryDateRange,
    legacyResponse: HomeSummaryResponse,
    context: HomeSummaryComputationContext,
  ) {
    const cacheRange = this.summaryCacheCoverageRange(range, query);
    let inFlight: HomeSummaryInFlightEntry;
    const startedAt = Date.now();
    const promise = this.extendLegacySummaryWithDailySeries(
      user,
      query,
      range,
      legacyResponse,
      context,
    )
      .then((response) => {
        if (inFlight.invalidated) {
          this.logger.log(
            `Home summary cache stale store skipped: key=${cacheLabel} source=daily_extension`,
          );
          return response;
        }
        this.storeSummaryResponseCache(cacheKey, response, cacheRange);
        this.logger.log(
          `Home summary daily cache extension stored: key=${cacheLabel} scope=${context.salesMetricsScope.scope} points=${response.dailySeries?.length ?? 0} durationMs=${Date.now() - startedAt}`,
        );
        return response;
      })
      .finally(() => {
        if (this.summaryInFlight.get(cacheKey) === inFlight) {
          this.summaryInFlight.delete(cacheKey);
        }
      });
    inFlight = {
      promise,
      startDate: cacheRange.startDate,
      endDate: cacheRange.endDate,
      invalidated: false,
      source: 'daily_extension',
    };
    this.summaryInFlight.set(cacheKey, inFlight);
    return promise;
  }

  private async extendLegacySummaryWithDailySeries(
    user: any,
    query: GetHomeSummaryQueryDto,
    range: SummaryDateRange,
    legacyResponse: HomeSummaryResponse,
    context: HomeSummaryComputationContext,
  ) {
    const projected = await this.loadProjectionMetrics(
      range,
      context.salesMetricsScope,
      'SALES',
      true,
    );
    if (
      !projected.dailySeries ||
      projected.totalRevenue !== legacyResponse.totalRevenue ||
      projected.totalOrders !== legacyResponse.totalOrders ||
      projected.reportedOrders !== legacyResponse.reportedOrders ||
      projected.totalReports !== legacyResponse.totalReports
    ) {
      this.logger.warn(
        `Home summary daily cache extension bypassed: reason=aggregate_drift scope=${context.salesMetricsScope.scope}`,
      );
      return this.computeSummary(user, query);
    }
    const response: HomeSummaryResponse = {
      ...legacyResponse,
      dailySeries: projected.dailySeries,
    };
    const versions = this.projectionVersionsByResponse.get(legacyResponse);
    if (versions) {
      this.projectionVersionsByResponse.set(response, new Map(versions));
    }
    this.computationContextByResponse.set(response, context);
    return response;
  }

  private cacheEntryNeedsInvalidation(
    entry: HomeSummaryResponseCacheEntry,
    changes: Map<string, number | null>,
  ) {
    for (const [date, version] of changes) {
      if (date < entry.startDate || date > entry.endDate) continue;
      if (version === null) return true;
      const cachedVersion = entry.projectionVersionsByDate.get(date) ?? 0;
      if (cachedVersion < version) return true;
    }
    return false;
  }

  private rangeOverlapsDates(
    range: Pick<SummaryDateRange, 'startDate' | 'endDate'>,
    dates: Iterable<string>,
  ) {
    for (const date of dates) {
      if (date >= range.startDate && date <= range.endDate) return true;
    }
    return false;
  }

  private clearSummarySupportCaches() {
    const entries =
      this.projectionFreshnessCache.size +
      this.salesProgressBundleCache.size +
      this.scopedSalesProgressCache.size;
    this.supportCacheGeneration += 1;
    this.projectionFreshnessCache.clear();
    this.salesProgressBundleCache.clear();
    this.scopedSalesProgressCache.clear();
    this.projectionFreshnessInFlight.clear();
    this.salesProgressBundleInFlight.clear();
    this.scopedSalesProgressInFlight.clear();
    return entries;
  }

  private async getOrLoadSummarySupportValue<T>(
    key: string,
    label: string,
    cache: Map<string, HomeSummarySupportCacheEntry<T>>,
    inFlight: Map<string, Promise<T>>,
    loader: () => Promise<T>,
  ): Promise<T> {
    if (!this.summaryResponseCacheEnabled()) return loader();
    const now = Date.now();
    const cached = cache.get(key);
    if (cached && cached.expiresAt > now) {
      this.logCacheDiagnostic(
        `support_hit:${label}`,
        `Home summary support cache hit: type=${label}`,
      );
      return cached.value;
    }
    if (cached) cache.delete(key);
    const pending = inFlight.get(key);
    if (pending) {
      this.logCacheDiagnostic(
        `support_join:${label}`,
        `Home summary support cache joined in-flight: type=${label}`,
      );
      return pending;
    }

    const generation = this.supportCacheGeneration;
    let promise: Promise<T>;
    promise = loader()
      .then((value) => {
        if (generation !== this.supportCacheGeneration) return value;
        while (cache.size >= MAX_HOME_SUMMARY_RESPONSE_CACHE_ENTRIES) {
          const oldestKey = cache.keys().next().value;
          if (!oldestKey) break;
          cache.delete(oldestKey);
        }
        cache.set(key, {
          expiresAt: Date.now() + HOME_SUMMARY_SUPPORT_CACHE_TTL_MS,
          value,
        });
        return value;
      })
      .finally(() => {
        if (inFlight.get(key) === promise) inFlight.delete(key);
      });
    inFlight.set(key, promise);
    return promise;
  }

  private logCacheDiagnostic(branch: string, message: string) {
    const now = Date.now();
    const lastLoggedAt = this.cacheDiagnosticLogAtByBranch.get(branch) ?? 0;
    if (now - lastLoggedAt < HOME_SUMMARY_CACHE_DIAGNOSTIC_LOG_INTERVAL_MS) {
      return;
    }
    this.cacheDiagnosticLogAtByBranch.set(branch, now);
    this.logger.debug(message);
  }

  private async computeSummary(
    user: any,
    query: GetHomeSummaryQueryDto,
    options: { skipComparisons?: boolean } = {},
  ): Promise<HomeSummaryResponse> {
    const startedAt = Date.now();
    const range = this.parseSummaryRange(query);
    const includeDailySeries = query.includeDailySeries === 'true';
    const includeComparisons =
      query.includeComparisons === 'true' && options.skipComparisons !== true;
    const dailySeriesDates = includeDailySeries
      ? this.rangeDateKeys(range.startDate, range.endDate)
      : [];
    if (dailySeriesDates.length > 90) {
      this.logger.warn(
        `Home summary daily series rejected: reason=range_above_90_days days=${dailySeriesDates.length}`,
      );
      throw new BadRequestException(
        'Chuỗi dữ liệu theo ngày chỉ hỗ trợ tối đa 90 ngày. Vui lòng chọn khoảng ngắn hơn.',
      );
    }
    const contextStartedAt = Date.now();
    const contextUser = this.authContextService
      ? await this.authContextService.withFeatureScopeContext(user, [
          FEATURE_KEYS.HOME_DASHBOARD_SALES,
          FEATURE_KEYS.HOME_DASHBOARD_FINANCE,
          FEATURE_KEYS.ADMIN_SALES_REPORTS,
        ])
      : user;
    const contextDurationMs = Date.now() - contextStartedAt;
    const date = range.endDate;
    const requestedScope = this.parseScopeParam(query.scope);
    const summaryDate = this.parseDateOnly(date) ?? new Date();
    const requestedSalesProgressUserId = this.optionalText(
      query.salesProgressUserId,
      80,
    );
    this.logger.log(
      `Home summary load started: user=${this.safeUserLabel(user)} startDate=${range.startDate} endDate=${range.endDate} scopeFilter=${requestedScope} salesProgressUserId=${requestedSalesProgressUserId || 'none'} includeDailySeries=${includeDailySeries} includeComparisons=${includeComparisons} dailySeriesDays=${dailySeriesDates.length}`,
    );
    const sectionAccessStartedAt = Date.now();
    const { salesAvailable, financeAvailable } =
      await this.resolveSectionAccess(contextUser);
    const sectionAccessDurationMs = Date.now() - sectionAccessStartedAt;
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
    const scopeStartedAt = Date.now();
    const scope = await this.salesReports.describeHomeSummaryScope(
      contextUser,
      requestedScope,
      this.optionalText(query.organizationNodeId, 80),
      { allowOwnScope: salesAvailable || financeAvailable },
    );
    const scopeDurationMs = Date.now() - scopeStartedAt;
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
    let freshness: HomeSummaryFreshnessResponse | null = null;
    let projectionVersionsByDate = new Map<string, number>();
    let useProjection = this.projectionEnabled();
    const projectionPreparationStartedAt = Date.now();
    if (includeDailySeries && salesAvailable && !useProjection) {
      this.logger.warn(
        'Home summary daily series unavailable: reason=projection_disabled',
      );
      throw new ServiceUnavailableException(
        'Chuỗi dữ liệu theo ngày đang được chuẩn bị. Vui lòng thử lại sau ít phút.',
      );
    }
    if (useProjection) {
      try {
        const projection = await this.loadProjectionFreshnessCached(
          range,
          salesAvailable,
          financeAvailable,
        );
        freshness = projection.freshness;
        projectionVersionsByDate = projection.versionsByDate;
        refreshedAt = freshness.projectionGeneratedAt;
      } catch (error) {
        if (includeDailySeries && salesAvailable) {
          this.logger.warn(
            `Home summary daily series load failed: reason=projection_freshness error=${safeLogError(error)} durationMs=${Date.now() - startedAt}`,
          );
          throw error;
        }
        if (!this.legacySyncFallbackEnabled()) throw error;
        this.logger.warn(
          `Home summary projection unavailable; legacy sync fallback started: user=${this.safeUserLabel(user)} startDate=${range.startDate} endDate=${range.endDate}`,
        );
        useProjection = false;
        refreshedAt = await this.syncFactsForRange(range);
      }
    } else if (salesAvailable || (financeAvailable && scope.scope === 'OWN')) {
      refreshedAt = await this.syncFactsForRange(range);
    }
    const projectionPreparationDurationMs =
      Date.now() - projectionPreparationStartedAt;
    const salesProgressStartedAt = Date.now();
    const salesProgressBundle = salesAvailable
      ? await this.buildSalesProgressBundleCached(
          contextUser,
          scope,
          summaryDate,
          range,
          requestedSalesProgressUserId,
        )
      : this.emptySalesProgressBundle();
    const salesProgressDurationMs = Date.now() - salesProgressStartedAt;
    const salesMetricsScope = salesProgressBundle.selectedScope ?? scope;
    // Pending-payment rows stay in the order cache/facts for reporting, but
    // they are not paid sales and must not inflate the sales KPI denominator.
    const salesOrderWhere = this.salesKpiOrderScopeWhere(
      salesMetricsScope,
      range,
    );

    let totalRevenue = 0;
    let totalOrders = 0;
    let totalReports = 0;
    let reportedOrders = 0;
    let notPurchasedReports = 0;
    let completedRevenue = 0;
    let dailySeries: HomeSummaryDailyPoint[] | undefined;
    let mainKpis = this.emptyMainKpis();
    let behaviorYesCounts = this.emptyBehaviorYesCounts();
    let projectedSales: HomeProjectionLoadResult | null = null;
    let projectedFinance: HomeProjectionLoadResult | null = null;
    const projectionMetricsStartedAt = Date.now();
    if (useProjection) {
      [projectedSales, projectedFinance] = await Promise.all([
        salesAvailable
          ? this.loadProjectionMetrics(
              range,
              salesMetricsScope,
              'SALES',
              includeDailySeries,
            )
          : Promise.resolve(null),
        financeAvailable
          ? this.loadProjectionMetrics(range, scope, 'FINANCE')
          : Promise.resolve(null),
      ]);
    }
    const projectionMetricsDurationMs = Date.now() - projectionMetricsStartedAt;
    if (salesAvailable) {
      if (useProjection) {
        const projected = projectedSales!;
        totalOrders = projected.totalOrders;
        totalReports = projected.totalReports;
        notPurchasedReports = projected.notPurchasedReports;
        reportedOrders = projected.reportedOrders;
        totalRevenue = projected.totalRevenue;
        completedRevenue = projected.completedRevenue;
        dailySeries = projected.dailySeries;
        behaviorYesCounts = {
          consultedSolution: projected.consultedSolutionYes,
          experienced: projected.experiencedYes,
          zalo: projected.zaloYes,
          appDownload: projected.appDownloadYes,
        };
        mainKpis = {
          businessCustomerRevenue: projected.businessCustomerRevenue,
          personalCustomerRevenue: projected.personalCustomerRevenue,
          examScorePromotionCount: projected.examScorePromotionCount,
          studentPromotionCount: projected.studentPromotionCount,
          installmentNeedCount: projected.installmentNeedCount,
          successfulInstallmentCount: projected.successfulInstallmentCount,
          extendedInsuranceQuantity: projected.extendedInsuranceQuantity,
          laptopQuantity: projected.laptopQuantity,
          pcQuantity: projected.pcQuantity,
          assembledPcQuantity: projected.assembledPcQuantity,
          appleQuantity: projected.appleQuantity,
          monitorQuantity: projected.monitorQuantity,
          printerQuantity: projected.printerQuantity,
          accessoriesQuantity: projected.accessoriesQuantity,
        };
      } else {
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
            where: { ...reportWhere, reportType: REPORT_TYPE_NOT_PURCHASED },
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
              .filter((value: string | null): value is string =>
                Boolean(value),
              ),
          ),
        );
        reportedOrders = reportedCodes.length
          ? await this.homeSummaryOrderFact.count({
              where: { ...salesOrderWhere, orderCode: { in: reportedCodes } },
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
    } else if (includeDailySeries) {
      this.logger.log(
        'Home summary daily series omitted: reason=sales_unavailable',
      );
    }

    let totalStatements = 0;
    let totalStatementsTracked = 0;
    let totalStatementsUnfollowed = 0;
    let totalTransferredAmount = 0;
    let totalStatementsWithOrder = 0;
    let totalStatementsWithoutOrder = 0;
    if (financeAvailable) {
      if (useProjection) {
        const projected = projectedFinance!;
        totalStatements = projected.totalStatements;
        totalStatementsTracked = projected.totalStatementsTracked;
        totalStatementsUnfollowed = projected.totalStatementsUnfollowed;
        totalTransferredAmount = projected.totalTransferredAmount;
        totalStatementsWithOrder = projected.totalStatementsWithOrder;
        totalStatementsWithoutOrder = projected.totalStatementsWithoutOrder;
      } else {
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
                .filter((value: string | null): value is string =>
                  Boolean(value),
                )
            : [];
        const financeWhere = this.financeScopeWhere(
          scope,
          range,
          personalOrderCodes,
        );
        const [
          statementCount,
          statementTrackedCount,
          statementUnfollowedCount,
          transferredAmountSummary,
          statementWithOrderCount,
          statementWithoutOrderCount,
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
        totalStatements = statementCount;
        totalStatementsTracked = statementTrackedCount;
        totalStatementsUnfollowed = statementUnfollowedCount;
        totalTransferredAmount = transferredAmountSummary._sum.amount ?? 0;
        totalStatementsWithOrder = statementWithOrderCount;
        totalStatementsWithoutOrder = statementWithoutOrderCount;
      }
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
    const statementOrderRate = totalStatementsTracked
      ? Number(
          ((totalStatementsWithOrder / totalStatementsTracked) * 100).toFixed(
            2,
          ),
        )
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
      totalStatementsTracked,
      totalStatementsUnfollowed,
      totalStatementsWithOrder,
      totalStatementsWithoutOrder,
      statementOrderRate,
      salesProgress: salesProgressBundle.personal,
      personalSalesProgress: salesProgressBundle.personal,
      scopeSalesProgress: salesProgressBundle.scope,
      salesProgressAssignees: salesProgressBundle.assignees,
      selectedSalesProgressUserId: salesProgressBundle.selectedUserId,
      refreshedAt,
      freshness,
      unavailableMessage: null,
      ...(dailySeries ? { dailySeries } : {}),
    };
    if (includeComparisons && salesAvailable) {
      response.comparisons = await this.buildComparisons(
        contextUser,
        query,
        range,
        response,
        salesMetricsScope,
      );
    }
    this.projectionVersionsByResponse.set(response, projectionVersionsByDate);
    this.computationContextByResponse.set(response, {
      useProjection,
      salesAvailable,
      salesMetricsScope,
    });
    this.logger.debug(
      `Home summary stage timings: user=${this.safeUserLabel(contextUser)} contextDurationMs=${contextDurationMs} sectionAccessDurationMs=${sectionAccessDurationMs} scopeDurationMs=${scopeDurationMs} projectionPreparationDurationMs=${projectionPreparationDurationMs} salesProgressDurationMs=${salesProgressDurationMs} projectionMetricsDurationMs=${projectionMetricsDurationMs} durationMs=${Date.now() - startedAt}`,
    );
    this.logger.log(
      `Home summary load succeeded: user=${this.safeUserLabel(user)} startDate=${range.startDate} endDate=${range.endDate} scopeFilter=${requestedScope} scope=${scope.scope} salesMetricsScope=${salesMetricsScope.scope} selectedSalesProgressUserId=${salesProgressBundle.selectedUserId || 'none'} salesProgressAssignees=${salesProgressBundle.assignees.length} salesAvailable=${salesAvailable} financeAvailable=${financeAvailable} includeDailySeries=${includeDailySeries} includeComparisons=${includeComparisons} comparisonMonthComplete=${response.comparisons?.previousMonth.complete ?? 'not_requested'} comparisonYearComplete=${response.comparisons?.previousYear.complete ?? 'not_requested'} dailySeriesPoints=${dailySeries?.length ?? 0} totalRevenue=${totalRevenue} completedRevenue=${completedRevenue} pendingRevenue=${pendingRevenue} businessCustomerRevenue=${mainKpis.businessCustomerRevenue} personalCustomerRevenue=${mainKpis.personalCustomerRevenue} installmentNeedCount=${mainKpis.installmentNeedCount} successfulInstallmentCount=${mainKpis.successfulInstallmentCount} laptopQuantity=${mainKpis.laptopQuantity} pcQuantity=${mainKpis.pcQuantity} assembledPcQuantity=${mainKpis.assembledPcQuantity} appleQuantity=${mainKpis.appleQuantity} totalOrders=${totalOrders} averageOrderValue=${averageOrderValue} totalReports=${totalReports} reportedOrders=${reportedOrders} notPurchasedReports=${notPurchasedReports} consultedYes=${behaviorYesCounts.consultedSolution} experiencedYes=${behaviorYesCounts.experienced} zaloYes=${behaviorYesCounts.zalo} appDownloadYes=${behaviorYesCounts.appDownload} totalStatements=${totalStatements} statementsWithOrder=${totalStatementsWithOrder} projectionVersion=${freshness?.projectionVersion ?? 'legacy'} projectionLagSeconds=${freshness?.projectionLagSeconds ?? 'legacy'} isStale=${freshness?.isStale ?? false} durationMs=${Date.now() - startedAt}`,
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
          });
    const unreportedEmployeeNames =
      await this.unreportedEmployeeNamesByEmail(unreportedOrders);

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
        this.toHomeUnreportedOrderDetail(row, unreportedEmployeeNames),
      ),
      installmentNeedReports: installmentNeedReports.map((row: any) =>
        this.toHomeInstallmentNeedDetail(row),
      ),
    };
    this.logger.log(
      `Home summary behavior details load succeeded: user=${this.safeUserLabel(user)} startDate=${range.startDate} endDate=${range.endDate} scope=${salesMetricsScope.scope} selectedSalesProgressUserId=${selectedSalesScope.selectedUserId || 'none'} notPurchased=${response.notPurchasedReports.length}/${notPurchasedTotal} unreported=${response.unreportedOrders.length}/${unreportedTotal} resolvedEmployeeNames=${response.unreportedOrders.filter((row) => Boolean(row.salesName)).length} unresolvedEmployeeNames=${response.unreportedOrders.filter((row) => !row.salesName).length} installmentNeed=${response.installmentNeedReports.length}/${installmentNeedTotal} limit=${limit} durationMs=${Date.now() - startedAt}`,
    );
    return response;
  }

  async listScopeOptions(user: any): Promise<HomeSummaryScopeOptionResponse[]> {
    const contextUser = this.authContextService
      ? await this.authContextService.withContext(user)
      : user;
    const cacheKey = this.scopeOptionsCacheKey(contextUser);
    const cacheLabel = logFingerprint(cacheKey);
    const now = Date.now();
    const cached = this.scopeOptionsCache.get(cacheKey);
    if (cached && cached.expiresAt > now) {
      this.logger.log(
        `Home summary scope options cache hit: key=${cacheLabel} ttlMs=${cached.expiresAt - now}`,
      );
      return cached.response;
    }
    if (cached) {
      this.scopeOptionsCache.delete(cacheKey);
      this.logger.log(
        `Home summary scope options cache expired: key=${cacheLabel}`,
      );
    }
    const pending = this.scopeOptionsInFlight.get(cacheKey);
    if (pending) {
      this.logger.log(
        `Home summary scope options cache joined in-flight: key=${cacheLabel}`,
      );
      return pending;
    }

    const pendingLoad = this.loadScopeOptionsFromSharedOrSource(
      contextUser,
      user,
      cacheKey,
      cacheLabel,
    );
    this.scopeOptionsInFlight.set(cacheKey, pendingLoad);
    try {
      return await pendingLoad;
    } finally {
      if (this.scopeOptionsInFlight.get(cacheKey) === pendingLoad) {
        this.scopeOptionsInFlight.delete(cacheKey);
      }
    }
  }

  private async loadScopeOptionsFromSharedOrSource(
    contextUser: any,
    user: any,
    cacheKey: string,
    cacheLabel: string,
  ): Promise<HomeSummaryScopeOptionResponse[]> {
    const sharedCached = await this.readSharedScopeOptions(cacheKey);
    if (sharedCached) {
      this.storeScopeOptionsCache(cacheKey, sharedCached);
      this.logger.log(
        `Home summary scope options shared cache hit: key=${cacheLabel} count=${sharedCached.length}`,
      );
      return sharedCached;
    }

    const leaseKey = `opshub:home:scope-options:lease:${logFingerprint(cacheKey)}`;
    let leaseToken: string | null = null;
    if (this.redis?.tryAcquireLease) {
      try {
        leaseToken = await this.redis.tryAcquireLease(
          leaseKey,
          HOME_SUMMARY_SCOPE_OPTIONS_LEASE_TTL_MS,
        );
        if (!leaseToken) {
          for (let attempt = 0; attempt < 10; attempt += 1) {
            await new Promise((resolve) => setTimeout(resolve, 50));
            const retry = await this.readSharedScopeOptions(cacheKey);
            if (retry) {
              this.storeScopeOptionsCache(cacheKey, retry);
              this.logger.log(
                `Home summary scope options distributed lease hit: key=${cacheLabel} attempt=${attempt + 1}`,
              );
              return retry;
            }
          }
          this.logger.warn(
            `Home summary scope options lease wait timed out: key=${cacheLabel}`,
          );
        }
      } catch (error) {
        this.logger.warn(
          `Home summary scope options lease unavailable: key=${cacheLabel} error=${safeLogError(error)}`,
        );
      }
    }

    this.logger.log(
      `Home summary scope options cache miss: key=${cacheLabel} user=${this.safeUserLabel(user)}`,
    );
    try {
      const response = await this.computeScopeOptions(contextUser);
      this.storeScopeOptionsCache(cacheKey, response);
      await this.writeSharedScopeOptions(cacheKey, response);
      this.logger.log(
        `Home summary scope options cache stored: key=${cacheLabel} l1TtlMs=${HOME_SUMMARY_SCOPE_OPTIONS_L1_TTL_MS} sharedTtlSeconds=${HOME_SUMMARY_SCOPE_OPTIONS_REDIS_TTL_SECONDS}`,
      );
      return response;
    } finally {
      if (leaseToken && this.redis?.releaseLease) {
        try {
          await this.redis.releaseLease(leaseKey, leaseToken);
        } catch (error) {
          this.logger.warn(
            `Home summary scope options lease release failed: key=${cacheLabel} error=${safeLogError(error)}`,
          );
        }
      }
    }
  }

  async getBehaviorDetailsV2(
    user: any,
    query: GetHomeSummaryDetailsV2QueryDto,
  ) {
    const startedAt = Date.now();
    const range = this.parseSummaryRange(query);
    const requestedScope = this.parseScopeParam(query.scope);
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 50)));
    const cursorId = this.decodeDetailsV2Cursor(query.cursor, query.kind);
    const requestedSalesProgressUserId = this.optionalText(
      query.salesProgressUserId,
      80,
    );
    this.logger.log(
      `Home summary details v2 load started: user=${this.safeUserLabel(user)} kind=${query.kind} startDate=${range.startDate} endDate=${range.endDate} limit=${limit} hasCursor=${Boolean(cursorId)}`,
    );
    const { salesAvailable } = await this.resolveSectionAccess(user);
    if (!salesAvailable) {
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
      const where = {
        ...this.reportScopeWhere(salesMetricsScope, range),
        reportType: REPORT_TYPE_NOT_PURCHASED,
      };
      const [total, facts] = await this.prisma.$transaction([
        this.homeSummaryReportFact.count({ where }),
        this.homeSummaryReportFact.findMany({
          where,
          orderBy: { salesReportId: 'asc' },
          take: limit + 1,
          ...(cursorId ? { cursor: { salesReportId: cursorId }, skip: 1 } : {}),
          select: { salesReportId: true },
        }),
      ]);
      const page = facts.slice(0, limit);
      const ids = page.map(
        (row: { salesReportId: string }) => row.salesReportId,
      );
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
      return this.detailsV2Response(
        base,
        page
          .map((fact: { salesReportId: string }) =>
            byId.get(fact.salesReportId),
          )
          .filter(Boolean)
          .map((row: any) => this.toHomeNotPurchasedDetail(row)),
        total,
        facts.length > limit ? (ids.at(-1) ?? null) : null,
        startedAt,
      );
    }

    if (query.kind === 'UNREPORTED_ORDER') {
      const salesOrderWhere = this.orderScopeWhere(salesMetricsScope, range);
      const reportedCodeRows = await this.homeSummaryReportFact.findMany({
        where: {
          ...this.reportScopeWhere(salesMetricsScope, range),
          reportType: REPORT_TYPE_PURCHASED,
          orderCode: { not: null },
        },
        select: { orderCode: true },
      });
      const reportedCodes = reportedCodeRows
        .map((row: { orderCode: string | null }) =>
          this.normalizeOrderCode(row.orderCode),
        )
        .filter((value: string | null): value is string => Boolean(value));
      const where = reportedCodes.length
        ? { AND: [salesOrderWhere, { orderCode: { notIn: reportedCodes } }] }
        : salesOrderWhere;
      const [total, rows] = await this.prisma.$transaction([
        this.homeSummaryOrderFact.count({ where }),
        this.homeSummaryOrderFact.findMany({
          where,
          orderBy: { orderCode: 'asc' },
          take: limit + 1,
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
      const page = rows.slice(0, limit);
      const employeeNames = await this.unreportedEmployeeNamesByEmail(page);
      return this.detailsV2Response(
        base,
        page.map((row: any) =>
          this.toHomeUnreportedOrderDetail(row, employeeNames),
        ),
        total,
        rows.length > limit ? (page.at(-1)?.orderCode ?? null) : null,
        startedAt,
      );
    }

    const where: Prisma.SalesReportWhereInput = {
      AND: [
        this.salesReportMainKpiWhere(salesMetricsScope, range),
        { installmentNeed: true },
      ],
    };
    const [total, rows] = await this.prisma.$transaction([
      this.prisma.salesReport.count({ where }),
      this.prisma.salesReport.findMany({
        where,
        orderBy: { id: 'asc' },
        take: limit + 1,
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
    const page = rows.slice(0, limit);
    return this.detailsV2Response(
      base,
      page.map((row) => this.toHomeInstallmentNeedDetail(row)),
      total,
      rows.length > limit ? (page.at(-1)?.id ?? null) : null,
      startedAt,
    );
  }

  private detailsV2Response(
    base: Record<string, unknown>,
    items: unknown[],
    total: number,
    nextId: string | null,
    startedAt: number,
  ) {
    const kind = String(base.kind);
    const response = {
      ...base,
      total,
      items,
      nextCursor: nextId ? this.encodeDetailsV2Cursor(kind, nextId) : null,
    };
    this.logger.log(
      `Home summary details v2 load succeeded: kind=${kind} count=${items.length}/${total} hasNext=${Boolean(nextId)} durationMs=${Date.now() - startedAt}`,
    );
    return response;
  }

  private encodeDetailsV2Cursor(kind: string, id: string) {
    return Buffer.from(JSON.stringify({ v: 1, kind, id }), 'utf8').toString(
      'base64url',
    );
  }

  private decodeDetailsV2Cursor(cursor: string | undefined, kind: string) {
    if (!cursor) return null;
    try {
      const decoded = JSON.parse(
        Buffer.from(cursor, 'base64url').toString('utf8'),
      );
      const id = this.optionalText(decoded?.id, 120);
      if (decoded?.v !== 1 || decoded?.kind !== kind || !id) throw new Error();
      return id;
    } catch {
      throw new BadRequestException(
        'Vị trí tải tiếp không hợp lệ. Vui lòng tải lại danh sách.',
      );
    }
  }

  async rebuildProjectionDate(date: string) {
    const summaryDate = this.parseDateOnly(date);
    if (!summaryDate) {
      throw new Error('Projection date must use yyyy-MM-dd');
    }
    return this.syncFacts(date, summaryDate);
  }

  async populateSalesProjectionMetrics(
    tx: Prisma.TransactionClient,
    date: string,
  ) {
    const startedAt = Date.now();
    const sourceDayStart = this.parseDateOnly(date);
    if (!sourceDayStart) throw new Error('Projection date must use yyyy-MM-dd');
    // Aggregate summaryDate is a PostgreSQL DATE keyed by the visible Vietnam
    // date, while source facts use the UTC instant at Vietnam midnight.
    const aggregateDate = this.dateOnlyUtc(date);
    const range = this.dateRangeFor(sourceDayStart);
    const [aggregates, reports, cacheRows] = await Promise.all([
      tx.homeSummaryDailyAggregate.findMany({
        where: { summaryDate: aggregateDate, projectionKind: 'SALES' },
        select: {
          id: true,
          dimensionType: true,
          dimensionKey: true,
          storeCode: true,
          totalOrders: true,
          reportedOrders: true,
          totalReports: true,
          notPurchasedReports: true,
        },
      }),
      tx.salesReport.findMany({
        where: {
          erpExcludedAt: null,
          ...this.reportedOrderDateWhere(range),
        },
        select: {
          id: true,
          reportType: true,
          orderCode: true,
          erpOrderId: true,
          createdByEmail: true,
          storeCode: true,
          consultedSolutionAnswer: true,
          experiencedAnswer: true,
          zaloAnswer: true,
          appDownloadAnswer: true,
          customerType: true,
          erpLifecycleStatus: true,
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
      }),
      tx.salesReportErpOrderCache.findMany({
        where: { excludedAt: null, ...this.orderCacheDateWhere(range) },
        select: {
          storeCode: true,
          orderCode: true,
          sourceUserEmail: true,
          consultantEmail: true,
          sellerEmail: true,
          grandTotal: true,
          paymentStatus: true,
          lifecycleStatus: true,
          hasReturnedFullItems: true,
        },
      }),
    ]);
    const reportRevenueCodes = Array.from(
      new Set(
        reports
          .map((row) => normalizeRevenueOrderCode(row.orderCode))
          .filter((code): code is string => Boolean(code)),
      ),
    );
    const reportCanonicalRows = reportRevenueCodes.length
      ? await tx.salesReportErpOrderCache.findMany({
          where: {
            orderCode: { in: reportRevenueCodes },
            excludedAt: null,
          },
          select: { orderCode: true, grandTotal: true },
        })
      : [];
    const canonicalRevenue = buildCanonicalRevenueLookup([
      ...cacheRows,
      ...reportCanonicalRows,
    ]);
    const missingRevenueOrders = reportRevenueCodes.filter(
      (code) => !canonicalRevenue.presentCodes.has(code),
    ).length;
    const invalidRevenueOrders = reportRevenueCodes.filter((code) =>
      canonicalRevenue.invalidCodes.has(code),
    ).length;
    if (missingRevenueOrders > 0 || invalidRevenueOrders > 0) {
      this.logger.warn(
        `Home revenue quality warning: source=projection_metrics reports=${reports.length} requestedOrders=${reportRevenueCodes.length} validOrders=${reportRevenueCodes.length - missingRevenueOrders - invalidRevenueOrders} missingOrders=${missingRevenueOrders} invalidOrders=${invalidRevenueOrders}`,
      );
    }
    type SalesAccumulator = {
      reports: any[];
      totalRevenue: number;
      completedRevenue: number;
      consultedSolutionYes: number;
      experiencedYes: number;
      zaloYes: number;
      appDownloadYes: number;
    };
    const buckets = new Map<string, SalesAccumulator>();
    const grainKey = (
      dimensionType: string,
      dimensionKey: string,
      store: string,
    ) => `${dimensionType}\u0000${dimensionKey}\u0000${store}`;
    const bucketFor = (key: string) => {
      let bucket = buckets.get(key);
      if (!bucket) {
        bucket = {
          reports: [],
          totalRevenue: 0,
          completedRevenue: 0,
          consultedSolutionYes: 0,
          experiencedYes: 0,
          zaloYes: 0,
          appDownloadYes: 0,
        };
        buckets.set(key, bucket);
      }
      return bucket;
    };
    const reportKeys = (row: {
      storeCode: string | null;
      createdByEmail: string | null;
    }) => {
      const store = this.normalizeStoreCode(row.storeCode) ?? '';
      const email = this.normalizeEmail(row.createdByEmail) ?? '';
      return Array.from(
        new Set([
          grainKey('GLOBAL', '', ''),
          ...(store ? [grainKey('STORE', store, store)] : []),
          ...(store && email ? [grainKey('USER_STORE', email, store)] : []),
        ]),
      );
    };
    for (const report of reports) {
      for (const key of reportKeys(report)) {
        const bucket = bucketFor(key);
        bucket.reports.push(report);
        if (report.consultedSolutionAnswer === 'YES')
          bucket.consultedSolutionYes += 1;
        if (report.experiencedAnswer === 'YES') bucket.experiencedYes += 1;
        if (report.zaloAnswer === 'YES') bucket.zaloYes += 1;
        if (report.appDownloadAnswer === 'YES') bucket.appDownloadYes += 1;
        if (
          report.reportType === REPORT_TYPE_PURCHASED &&
          ['COMPLETED', 'COMPLETED_PARTIAL_RETURN'].includes(
            report.erpLifecycleStatus,
          )
        ) {
          bucket.completedRevenue += canonicalRevenueForOrder(
            canonicalRevenue,
            report.orderCode,
          );
        }
      }
    }
    for (const row of cacheRows) {
      const store = this.normalizeStoreCode(row.storeCode) ?? '';
      const emails = new Set(
        [row.sourceUserEmail, row.consultantEmail, row.sellerEmail]
          .map((value) => this.normalizeEmail(value))
          .filter((value): value is string => Boolean(value)),
      );
      const keys = [
        grainKey('GLOBAL', '', ''),
        ...(store ? [grainKey('STORE', store, store)] : []),
        ...(store
          ? Array.from(emails, (email) => grainKey('USER_STORE', email, store))
          : []),
      ];
      const revenue = this.netCacheRevenue(row);
      for (const key of new Set(keys)) bucketFor(key).totalRevenue += revenue;
    }
    const metricUpdates: Array<{
      id: string;
      metrics: Prisma.InputJsonObject;
    }> = [];
    for (const aggregate of aggregates) {
      const bucket = bucketFor(
        grainKey(
          aggregate.dimensionType,
          aggregate.dimensionKey,
          aggregate.storeCode,
        ),
      );
      const main = this.salesReports.summarizeSalesRevenueRows(
        bucket.reports,
        canonicalRevenue,
      );
      const metrics: Prisma.InputJsonObject = {
        salesPriceContractVersion: SALES_PRICE_CONTRACT_VERSION,
        salesKpiContractVersion: HOME_SALES_KPI_CONTRACT_VERSION,
        totalRevenue: bucket.totalRevenue,
        completedRevenue: bucket.completedRevenue,
        businessCustomerRevenue: main.businessRevenue,
        personalCustomerRevenue: main.personalRevenue,
        examScorePromotionCount: main.examScorePromotionCount,
        studentPromotionCount: main.studentPromotionCount,
        installmentNeedCount: main.installmentNeedTotalCount,
        successfulInstallmentCount: main.successfulInstallmentOrderCount,
        extendedInsuranceQuantity: main.extendedInsuranceQuantity,
        laptopQuantity: main.laptopQuantity,
        pcQuantity: main.pcQuantity,
        assembledPcQuantity: main.assembledPcQuantity,
        appleQuantity: main.appleQuantity,
        monitorQuantity: main.monitorQuantity,
        printerQuantity: main.printerQuantity,
        accessoriesQuantity: main.accessoriesQuantity,
        consultedSolutionYes: bucket.consultedSolutionYes,
        experiencedYes: bucket.experiencedYes,
        zaloYes: bucket.zaloYes,
        appDownloadYes: bucket.appDownloadYes,
      };
      metricUpdates.push({ id: aggregate.id, metrics });
    }
    if (metricUpdates.length > 0) {
      await tx.$executeRaw(Prisma.sql`
        WITH metric_updates AS (
          SELECT item->>'id' AS id, item->'metrics' AS metrics
          FROM jsonb_array_elements(
            CAST(${JSON.stringify(metricUpdates)} AS jsonb)
          ) AS item
        )
        UPDATE "HomeSummaryDailyAggregate" AS aggregate
        SET "metrics" = metric_updates.metrics,
            "updatedAt" = CURRENT_TIMESTAMP
        FROM metric_updates
        WHERE aggregate."id" = metric_updates.id
      `);
    }
    this.logger.log(
      `Home projection sales metrics populated: date=${date} grains=${metricUpdates.length} reports=${reports.length} cacheRows=${cacheRows.length} reportRevenueRows=${reportCanonicalRows.length} durationMs=${Date.now() - startedAt}`,
    );
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
          erpPaymentStatus: true,
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
          paymentStatus: true,
          grandTotal: true,
        },
      }),
    ]);
    const canonicalRevenue = buildCanonicalRevenueLookup(orders);

    const refreshedAt = new Date();
    const purchaseReportsByOrderCode = new Map<
      string,
      {
        id: string;
        createdByUserId: string | null;
        createdByEmail: string | null;
        createdByPersonnelCode: string | null;
        revenue: number | null;
        paymentStatus: string | null;
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
          revenue: canonicalRevenueForOrder(canonicalRevenue, orderCode),
          paymentStatus: this.optionalText(row.erpPaymentStatus, 80),
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
          revenue: canonicalRevenueForOrder(canonicalRevenue, orderCode),
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
          revenue: canonicalRevenueForOrder(canonicalRevenue, orderCode),
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
            isPaymentPending: isSalesReportErpPendingPaymentStatus(
              report.paymentStatus,
            ),
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
            isPaymentPending: isSalesReportErpPendingPaymentStatus(
              report.paymentStatus,
            ),
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
      paymentStatus: string | null;
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
        isPaymentPending: isSalesReportErpPendingPaymentStatus(
          row.paymentStatus,
        ),
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
        isPaymentPending: isSalesReportErpPendingPaymentStatus(
          row.paymentStatus,
        ),
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

  private salesKpiOrderScopeWhere(
    scope: SalesReportSummaryScopeDescriptor,
    dateRange: DateRange,
  ) {
    const base = this.orderScopeWhere(scope, dateRange) as {
      AND?: Record<string, unknown>[];
    };
    if (Array.isArray(base.AND)) {
      return {
        AND: [...base.AND, { isPaymentPending: false }],
      };
    }
    return {
      AND: [
        base,
        // Do not remove the row from cache/facts: it remains available to the
        // reporting cockpit until ERP confirms payment or cancellation.
        { isPaymentPending: false },
      ],
    };
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
        orderCode: true,
        erpOrderCreatedAt: true,
        submittedAt: true,
      },
    });
    const canonicalRevenue = await this.loadCanonicalRevenueForRows(
      this.prisma,
      rows,
      'sales_progress',
    );
    const actualFor = (range: DateRange) =>
      rows.reduce((sum, row) => {
        const occurredAt = row.erpOrderCreatedAt ?? row.submittedAt;
        if (occurredAt < range.start || occurredAt >= range.end) return sum;
        return sum + canonicalRevenueForOrder(canonicalRevenue, row.orderCode);
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
        Math.round(Number(target.targetBeforeTax) * 1.08),
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
        orderCode: true,
      },
    });
    const canonicalRevenue = await this.loadCanonicalRevenueForRows(
      this.prisma,
      rows,
      'completed_revenue',
    );
    return rows.reduce(
      (sum, row) =>
        sum + canonicalRevenueForOrder(canonicalRevenue, row.orderCode),
      0,
    );
  }

  private async totalCacheRevenue(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ) {
    const rows = await this.prisma.salesReportErpOrderCache.findMany({
      where: this.orderCacheRevenueWhere(scope, range),
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
    this.logger.log(
      `Home summary cache revenue calculated: source=cache scope=${scope.scope} rows=${rows.length} skippedPendingPayment=${skippedPendingPayment} invalidCanonicalTotals=${invalidCanonicalTotal} revenue=${revenue}`,
    );
    return revenue;
  }

  private netCacheRevenue(row: {
    grandTotal: number | null;
    paymentStatus?: string | null;
    lifecycleStatus: string;
    hasReturnedFullItems: boolean;
  }) {
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
    const canonicalRevenue = await this.loadCanonicalRevenueForRows(
      this.prisma,
      rows,
      'main_kpis',
    );
    const summary = this.salesReports.summarizeSalesRevenueRows(
      rows,
      canonicalRevenue,
    );
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
        ? this.buildSharedScopeSalesProgressCached(
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

  private buildSalesProgressBundleCached(
    user: any,
    scope: SalesReportSummaryScopeDescriptor,
    summaryDate: Date,
    selectedRange: DateRange,
    requestedUserId: string | null,
  ) {
    const key = this.salesProgressBundleCacheKey(
      user,
      scope,
      summaryDate,
      selectedRange,
      requestedUserId,
    );
    return this.getOrLoadSummarySupportValue(
      key,
      'principal_progress',
      this.salesProgressBundleCache,
      this.salesProgressBundleInFlight,
      () =>
        this.buildSalesProgressBundle(
          user,
          scope,
          summaryDate,
          selectedRange,
          requestedUserId,
        ),
    );
  }

  private buildSharedScopeSalesProgressCached(
    scope: SalesReportSummaryScopeDescriptor,
    summaryDate: Date,
    selectedRange: DateRange,
  ) {
    if (scope.scope !== 'ALL' && scope.scope !== 'MANAGED_SCOPE') {
      throw new Error('Shared sales progress requires a non-personal scope.');
    }
    const canonical = JSON.stringify([
      'v1',
      this.summaryScopeFingerprint(scope),
      this.dateOnlyKey(summaryDate),
      selectedRange.start.toISOString(),
      selectedRange.end.toISOString(),
    ]);
    const key = createHash('sha256').update(canonical).digest('hex');
    return this.getOrLoadSummarySupportValue(
      key,
      'shared_scope_progress',
      this.scopedSalesProgressCache,
      this.scopedSalesProgressInFlight,
      () => this.buildSalesProgress(null, scope, summaryDate, selectedRange),
    );
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
    const contextAccess = user?.__authContext?.featureAccess;
    if (contextAccess && typeof contextAccess === 'object') {
      return {
        salesAvailable:
          contextAccess[FEATURE_KEYS.HOME_DASHBOARD_SALES] === true,
        financeAvailable:
          contextAccess[FEATURE_KEYS.HOME_DASHBOARD_FINANCE] === true,
      };
    }
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
      orderCreatedAt: {
        gte: dateRange.start,
        lt: dateRange.end,
      },
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
      totalStatementsTracked: 0,
      totalStatementsUnfollowed: 0,
      totalStatementsWithOrder: 0,
      totalStatementsWithoutOrder: 0,
      statementOrderRate: 0,
      salesProgress: this.emptySalesProgress(),
      personalSalesProgress: this.emptySalesProgress(),
      scopeSalesProgress: this.emptySalesProgress(),
      salesProgressAssignees: [],
      selectedSalesProgressUserId: null,
      refreshedAt,
      freshness: null,
      unavailableMessage,
    };
  }

  private loadProjectionFreshnessCached(
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
    return this.getOrLoadSummarySupportValue(
      key,
      'projection_freshness',
      this.projectionFreshnessCache,
      this.projectionFreshnessInFlight,
      () => this.loadProjectionFreshness(range, requireSales, requireFinance),
    );
  }

  private async loadProjectionFreshness(
    range: SummaryDateRange,
    requireSales = true,
    requireFinance = true,
  ): Promise<HomeSummaryProjectionSnapshot> {
    const startDate = this.dateOnlyUtc(range.startDate);
    const endDate = this.dateOnlyUtc(range.endDate);
    const states = await this.prisma.homeSummaryProjectionState.findMany({
      where: { summaryDate: { gte: startDate, lte: endDate } },
      orderBy: { summaryDate: 'asc' },
    });
    const stateByDate = new Map(
      states.map((state) => [this.dateOnlyKey(state.summaryDate), state]),
    );
    const expectedDates = this.rangeDateKeys(range.startDate, range.endDate);
    const missingDates = expectedDates.filter((date) => {
      const state = stateByDate.get(date);
      if (!state) return true;
      // A source write marks its projection kind PENDING immediately, while the
      // previous aggregate snapshot remains complete and readable. Only return
      // 503 when that kind has never produced a complete snapshot.
      if (requireSales && !state.salesGeneratedAt) {
        return true;
      }
      if (requireFinance && !state.financeGeneratedAt) {
        return true;
      }
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
      const state = stateByDate.get(date)!;
      const generatedCandidates = [
        ...(requireSales && state.salesGeneratedAt
          ? [state.salesGeneratedAt]
          : []),
        ...(requireFinance && state.financeGeneratedAt
          ? [state.financeGeneratedAt]
          : []),
      ];
      const generatedAt = generatedCandidates.reduce(
        (oldest, value) => (value < oldest ? value : oldest),
        generatedCandidates[0],
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
                generatedAt: state.salesGeneratedAt!,
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
                generatedAt: state.financeGeneratedAt!,
                sourceWatermarks: [state.mapVietinSourceUpdatedAt],
              },
            ]
          : []),
      ];
      for (const pair of freshnessPairs) {
        const sourceUpdatedAt = pair.sourceWatermarks
          .filter((value): value is Date => value !== null)
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
    return {
      freshness: {
        projectionGeneratedAt,
        projectionLagSeconds,
        projectionVersion,
        sourceUpdatedAtBySource,
        isStale,
      },
      versionsByDate: new Map(
        expectedDates.map((date) => [
          date,
          Math.max(
            requireSales
              ? Number(stateByDate.get(date)!.salesProjectionVersion)
              : 0,
            requireFinance
              ? Number(stateByDate.get(date)!.financeProjectionVersion)
              : 0,
          ),
        ]),
      ),
    };
  }

  private emptyProjectionMetrics(): HomeProjectionMetrics {
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

  private async buildComparisons(
    user: any,
    query: GetHomeSummaryQueryDto,
    currentRange: SummaryDateRange,
    current: HomeSummaryResponse,
    scope: SalesReportSummaryScopeDescriptor,
  ): Promise<HomeSummaryComparisonsResponse> {
    const previousMonthRange = this.shiftSummaryRange(currentRange, -1, 0);
    const previousYearRange = this.shiftSummaryRange(currentRange, 0, -1);
    const [previousMonth, previousYear] = await Promise.all([
      this.buildComparisonPeriod(
        user,
        query,
        current,
        previousMonthRange,
        scope,
      ),
      this.buildComparisonPeriod(
        user,
        query,
        current,
        previousYearRange,
        scope,
      ),
    ]);
    return { previousMonth, previousYear };
  }

  private async buildComparisonPeriod(
    user: any,
    query: GetHomeSummaryQueryDto,
    current: HomeSummaryResponse,
    range: SummaryDateRange,
    scope: SalesReportSummaryScopeDescriptor,
  ): Promise<HomeSummaryComparisonPeriodResponse> {
    const startedAt = Date.now();
    try {
      const csvComposition = await this.overlayActiveCsvHistory(range, scope);
      let values: Record<HomeSalesComparisonMetricKey, number>;
      let source: HomeSummaryComparisonPeriodResponse['source'];
      let unavailable: Set<HomeSalesComparisonMetricKey>;
      if (csvComposition) {
        values = csvComposition.values;
        source = csvComposition.source;
        unavailable = csvComposition.unavailable;
      } else {
        const previous = await this.computeSummary(
          user,
          {
            ...query,
            date: undefined,
            startDate: range.startDate,
            endDate: range.endDate,
            includeDailySeries: 'false',
            includeComparisons: 'false',
          },
          { skipComparisons: true },
        );
        if (!previous.available || !previous.salesAvailable) {
          return this.unavailableComparisonPeriod(range);
        }
        values = this.comparisonValues(previous);
        source = 'OPSHUB';
        unavailable = new Set<HomeSalesComparisonMetricKey>();
      }
      const currentValues = this.comparisonValues(current);
      const metrics = {} as Record<
        HomeSalesComparisonMetricKey,
        HomeSummaryComparisonMetricResponse
      >;
      for (const key of HOME_SALES_COMPARISON_METRIC_KEYS) {
        metrics[key] = unavailable.has(key)
          ? { value: null, deltaPercent: null, status: 'UNAVAILABLE' }
          : this.comparisonMetric(currentValues[key], values[key]);
      }
      this.logger.log(
        `Home comparison period loaded: startDate=${range.startDate} endDate=${range.endDate} source=${source} unavailableMetrics=${unavailable.size} durationMs=${Date.now() - startedAt}`,
      );
      return {
        startDate: range.startDate,
        endDate: range.endDate,
        source,
        complete: unavailable.size === 0,
        metrics,
      };
    } catch (error) {
      this.logger.warn(
        `Home comparison period unavailable: startDate=${range.startDate} endDate=${range.endDate} error=${safeLogError(error)} durationMs=${Date.now() - startedAt}`,
      );
      return this.unavailableComparisonPeriod(range);
    }
  }

  private async overlayActiveCsvHistory(
    range: SummaryDateRange,
    scope: SalesReportSummaryScopeDescriptor,
  ) {
    let stores = this.normalizedStoreCodes(scope.allowedStoreCodes);
    if (scope.scope === 'ALL') {
      stores = this.normalizedStoreCodes(
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
          gte: this.dateOnlyUtc(range.startDate),
          lte: this.dateOnlyUtc(range.endDate),
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
      : this.optionalText(scope.ownUserId, 120) || '__NO_CSV_USER__';
    const projectionDimensionKey = storeDimension
      ? ''
      : this.personalEmail(scope) || '__NO_PROJECTED_USER__';
    const versionIds = Array.from(
      new Set(active.map((grain) => grain.currentVersionId)),
    );
    const expectedStores = stores.length
      ? stores
      : Array.from(new Set(active.map((grain) => grain.storeCode))).sort();
    const expectedGrains = new Set(
      this.rangeDateKeys(range.startDate, range.endDate).flatMap((date) =>
        expectedStores.map((storeCode) => `${date}|${storeCode}`),
      ),
    );
    const activeVersionByGrain = new Map(
      active.map((grain) => [
        `${this.dateOnlyKey(grain.summaryDate)}|${grain.storeCode}`,
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
              gte: this.dateOnlyUtc(range.startDate),
              lte: this.dateOnlyUtc(range.endDate),
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
          `${this.dateOnlyKey(coverage.summaryDate)}|${coverage.storeCode}`,
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
          gte: this.dateOnlyUtc(range.startDate),
          lte: this.dateOnlyUtc(range.endDate),
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
                gte: this.dateOnlyUtc(range.startDate),
                lte: this.dateOnlyUtc(range.endDate),
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
              `${this.dateOnlyKey(row.summaryDate)}|${row.storeCode}`,
            ) === row.versionId,
        )
        .map((row) => [
          `${this.dateOnlyKey(row.summaryDate)}|${row.storeCode}`,
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
        `${this.dateOnlyKey(row.summaryDate)}|${row.storeCode}`,
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
      for (const key of METRIC_COMPARISON_QUANTITY_KEYS) {
        const value = metrics[key];
        if (typeof value !== 'number' || !Number.isFinite(value)) {
          unavailable.add(key);
        } else {
          projectionTotals[key] += value;
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

  private comparisonValues(response: HomeSummaryResponse) {
    return Object.fromEntries(
      HOME_SALES_COMPARISON_METRIC_KEYS.map((key) => [
        key,
        Number(response[key] ?? 0),
      ]),
    ) as Record<HomeSalesComparisonMetricKey, number>;
  }

  private comparisonMetric(
    current: number,
    previous: number,
  ): HomeSummaryComparisonMetricResponse {
    if (previous === 0 && current > 0) {
      return { value: previous, deltaPercent: null, status: 'NEW' };
    }
    const deltaPercent =
      previous === 0
        ? 0
        : Number(
            (((current - previous) / Math.abs(previous)) * 100).toFixed(2),
          );
    return { value: previous, deltaPercent, status: 'AVAILABLE' };
  }

  private unavailableComparisonPeriod(
    range: Pick<SummaryDateRange, 'startDate' | 'endDate'>,
  ): HomeSummaryComparisonPeriodResponse {
    return {
      startDate: range.startDate,
      endDate: range.endDate,
      source: 'UNAVAILABLE',
      complete: false,
      metrics: Object.fromEntries(
        HOME_SALES_COMPARISON_METRIC_KEYS.map((key) => [
          key,
          { value: null, deltaPercent: null, status: 'UNAVAILABLE' },
        ]),
      ) as Record<
        HomeSalesComparisonMetricKey,
        HomeSummaryComparisonMetricResponse
      >,
    };
  }

  private shiftSummaryRange(
    range: Pick<SummaryDateRange, 'startDate' | 'endDate'>,
    monthDelta: number,
    yearDelta: number,
  ): SummaryDateRange {
    const startDate = this.shiftDateOnly(
      range.startDate,
      monthDelta,
      yearDelta,
    );
    const endDate = this.shiftDateOnly(range.endDate, monthDelta, yearDelta);
    return {
      startDate,
      endDate,
      legacyDate: null,
      start: this.dateOnlyUtc(startDate),
      end: new Date(`${endDate}T23:59:59.999Z`),
    };
  }

  private shiftDateOnly(value: string, monthDelta: number, yearDelta: number) {
    const source = this.dateOnlyUtc(value);
    const targetMonthIndex =
      source.getUTCFullYear() * 12 +
      source.getUTCMonth() +
      monthDelta +
      yearDelta * 12;
    const year = Math.floor(targetMonthIndex / 12);
    const month = ((targetMonthIndex % 12) + 12) % 12;
    const day = Math.min(
      source.getUTCDate(),
      new Date(Date.UTC(year, month + 1, 0)).getUTCDate(),
    );
    return `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
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

  private async loadProjectionMetrics(
    range: SummaryDateRange,
    scope: SalesReportSummaryScopeDescriptor,
    projectionKind: HomeProjectionKind,
    includeDailySeries = false,
  ): Promise<HomeProjectionLoadResult> {
    const startedAt = Date.now();
    const startDate = this.dateOnlyUtc(range.startDate);
    const endDate = this.dateOnlyUtc(range.endDate);
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
      const stores = this.normalizedStoreCodes(scope.allowedStoreCodes);
      where = {
        ...base,
        dimensionType: 'STORE',
        storeCode: { in: stores.length ? stores : ['__NO_PROJECTED_STORE__'] },
      };
    } else {
      const email = this.personalEmail(scope);
      const stores = this.normalizedStoreCodes(scope.allowedStoreCodes);
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
          this.rangeDateKeys(range.startDate, range.endDate).map((date) => [
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
      const dailyPoint = row.summaryDate
        ? dailyByDate?.get(this.dateOnlyKey(row.summaryDate))
        : undefined;
      if (dailyPoint) {
        dailyPoint.totalOrders += row.totalOrders;
        dailyPoint.reportedOrders += row.reportedOrders;
        dailyPoint.totalReports += row.totalReports;
        const dailyRevenue = Number(metrics.totalRevenue ?? 0);
        if (Number.isFinite(dailyRevenue)) {
          dailyPoint.totalRevenue += dailyRevenue;
        }
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

  private rangeDateKeys(startDate: string, endDate: string) {
    const start = this.dateOnlyUtc(startDate);
    const end = this.dateOnlyUtc(endDate);
    const dates: string[] = [];
    for (
      const cursor = new Date(start);
      cursor <= end;
      cursor.setUTCDate(cursor.getUTCDate() + 1)
    ) {
      dates.push(this.dateOnlyKey(cursor));
      if (dates.length > 366) {
        throw new BadRequestException('Khoảng ngày chỉ được tối đa 366 ngày.');
      }
    }
    return dates;
  }

  private dateOnlyUtc(value: string) {
    return new Date(`${value}T00:00:00.000Z`);
  }

  private dateOnlyKey(value: Date) {
    return value.toISOString().slice(0, 10);
  }

  private projectionEnabled() {
    const raw = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    if (raw === undefined && process.env.NODE_ENV === 'test') return false;
    return (
      String(raw ?? 'true')
        .trim()
        .toLowerCase() !== 'false'
    );
  }

  private summaryResponseCacheEnabled() {
    const raw = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    if (raw === undefined && process.env.NODE_ENV === 'test') return false;
    return (
      String(raw ?? 'true')
        .trim()
        .toLowerCase() !== 'false'
    );
  }

  private summaryResponseCacheKey(user: any, query: GetHomeSummaryQueryDto) {
    const range = this.parseSummaryRange(query);
    const userKey =
      this.optionalText(user?.id, 120) ||
      this.optionalText(user?.email, 160) ||
      this.optionalText(user?.personnelCode, 80) ||
      'anonymous';
    const accessIdentity = [
      user?.tokenVersion ?? 0,
      user?.authSession?.sessionVersion ?? 0,
      user?.accessVersion ?? 0,
    ].join('|');
    const canonicalKey = JSON.stringify([
      'v6',
      userKey,
      accessIdentity,
      range.startDate,
      range.endDate,
      this.parseScopeParam(query.scope),
      this.optionalText(query.organizationNodeId, 80) || '',
      this.optionalText(query.salesProgressUserId, 80) || '',
      query.includeDailySeries === 'true',
      query.includeComparisons === 'true',
    ]);
    return `v6:${createHash('sha256').update(canonicalKey).digest('hex')}`;
  }

  private salesProgressBundleCacheKey(
    user: any,
    scope: SalesReportSummaryScopeDescriptor,
    summaryDate: Date,
    selectedRange: DateRange,
    requestedUserId: string | null,
  ) {
    const userKey =
      this.optionalText(user?.id, 120) ||
      this.optionalText(user?.email, 160) ||
      this.optionalText(user?.personnelCode, 80) ||
      'anonymous';
    const accessVersion = [
      user?.tokenVersion ?? 0,
      user?.authSession?.sessionVersion ?? 0,
      user?.accessVersion ?? 0,
    ].join('|');
    const canonical = JSON.stringify([
      'v1',
      userKey,
      accessVersion,
      this.summaryScopeFingerprint(scope),
      this.dateOnlyKey(summaryDate),
      selectedRange.start.toISOString(),
      selectedRange.end.toISOString(),
      this.optionalText(requestedUserId, 80) || '',
    ]);
    return createHash('sha256').update(canonical).digest('hex');
  }

  private summaryScopeFingerprint(scope: SalesReportSummaryScopeDescriptor) {
    const canonical = JSON.stringify([
      scope.available,
      scope.scope,
      this.optionalText(scope.ownUserId, 120) || '',
      this.normalizeEmail(scope.ownEmail) || '',
      this.optionalText(scope.ownPersonnelCode, 120) || '',
      this.normalizedStoreCodes(scope.allowedStoreCodes).sort(),
    ]);
    return createHash('sha256').update(canonical).digest('hex');
  }

  private storeSummaryResponseCache(
    cacheKey: string,
    response: HomeSummaryResponse,
    range: Pick<SummaryDateRange, 'startDate' | 'endDate'>,
  ) {
    while (
      this.summaryResponseCache.size >= MAX_HOME_SUMMARY_RESPONSE_CACHE_ENTRIES
    ) {
      const oldestKey = this.summaryResponseCache.keys().next().value;
      if (!oldestKey) break;
      this.summaryResponseCache.delete(oldestKey);
    }
    const storedAt = Date.now();
    const refreshSpread =
      Number.parseInt(logFingerprint(cacheKey).slice(0, 8), 16) %
      HOME_SUMMARY_RESPONSE_REFRESH_AHEAD_SPREAD_MS;
    const responseVersions = this.projectionVersionsByResponse.get(response);
    const fallbackVersion = response.freshness?.projectionVersion ?? 0;
    const projectionVersionsByDate = new Map<string, number>();
    for (const date of this.rangeDateKeys(range.startDate, range.endDate)) {
      projectionVersionsByDate.set(
        date,
        responseVersions?.get(date) ?? fallbackVersion,
      );
    }
    this.summaryResponseCache.set(cacheKey, {
      expiresAt: storedAt + HOME_SUMMARY_RESPONSE_CACHE_TTL_MS,
      refreshAfter:
        storedAt + HOME_SUMMARY_RESPONSE_REFRESH_AHEAD_MIN_MS + refreshSpread,
      refreshAttempted: false,
      startDate: range.startDate,
      endDate: range.endDate,
      projectionVersionsByDate,
      response,
    });
  }

  private summaryCacheCoverageRange(
    range: Pick<SummaryDateRange, 'startDate' | 'endDate'>,
    query: GetHomeSummaryQueryDto,
  ) {
    if (query.includeComparisons !== 'true') return range;
    const previousYear = this.shiftSummaryRange(range, 0, -1);
    return {
      startDate:
        previousYear.startDate < range.startDate
          ? previousYear.startDate
          : range.startDate,
      endDate:
        previousYear.endDate > range.endDate
          ? previousYear.endDate
          : range.endDate,
    };
  }

  private async computeScopeOptions(
    user: any,
  ): Promise<HomeSummaryScopeOptionResponse[]> {
    const { salesAvailable, financeAvailable } =
      await this.resolveSectionAccess(user);
    if (!salesAvailable && !financeAvailable) return [];
    return this.salesReports.listHomeSummaryScopeOptions(user, {
      allowOwnScope: salesAvailable || financeAvailable,
    });
  }

  private scopeOptionsCacheKey(user: any) {
    const userKey =
      this.optionalText(user?.id, 120) ||
      this.optionalText(user?.email, 160) ||
      this.optionalText(user?.personnelCode, 80) ||
      'anonymous';
    const version = [
      user?.tokenVersion ?? 0,
      user?.authSession?.sessionVersion ?? 0,
      user?.accessVersion ?? 0,
    ].join('|');
    return ['v2', logFingerprint(`${userKey}|${version}`)].join('|');
  }

  private sharedScopeOptionsKey(cacheKey: string) {
    return `opshub:home:scope-options:${logFingerprint(cacheKey)}`;
  }

  private async readSharedScopeOptions(cacheKey: string) {
    if (!this.redis) return null;
    try {
      const value = await this.redis.getJson<HomeSummaryScopeOptionResponse[]>(
        this.sharedScopeOptionsKey(cacheKey),
      );
      return Array.isArray(value) ? value : null;
    } catch (error) {
      this.logger.warn(
        `Home summary scope options shared cache read skipped: key=${logFingerprint(cacheKey)} error=${safeLogError(error)}`,
      );
      return null;
    }
  }

  private async writeSharedScopeOptions(
    cacheKey: string,
    response: HomeSummaryScopeOptionResponse[],
  ) {
    if (!this.redis) return;
    try {
      await this.redis.setJsonWithTtl(
        this.sharedScopeOptionsKey(cacheKey),
        response,
        HOME_SUMMARY_SCOPE_OPTIONS_REDIS_TTL_SECONDS,
      );
    } catch (error) {
      this.logger.warn(
        `Home summary scope options shared cache write skipped: key=${logFingerprint(cacheKey)} error=${safeLogError(error)}`,
      );
    }
  }

  private storeScopeOptionsCache(
    cacheKey: string,
    response: HomeSummaryScopeOptionResponse[],
  ) {
    while (
      this.scopeOptionsCache.size >=
      MAX_HOME_SUMMARY_SCOPE_OPTIONS_CACHE_ENTRIES
    ) {
      const oldestKey = this.scopeOptionsCache.keys().next().value;
      if (!oldestKey) break;
      this.scopeOptionsCache.delete(oldestKey);
    }
    this.scopeOptionsCache.set(cacheKey, {
      expiresAt: Date.now() + HOME_SUMMARY_SCOPE_OPTIONS_L1_TTL_MS,
      response,
    });
  }

  private legacySyncFallbackEnabled() {
    return (
      String(process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED ?? 'false')
        .trim()
        .toLowerCase() === 'true'
    );
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

  private async loadCanonicalRevenueForRows(
    client: {
      salesReportErpOrderCache: {
        findMany: (
          args: unknown,
        ) => Promise<Array<{ orderCode: string; grandTotal: number | null }>>;
      };
    },
    rows: Array<{ orderCode?: unknown }>,
    source: string,
  ): Promise<CanonicalRevenueLookup> {
    const orderCodes = Array.from(
      new Set(
        rows
          .map((row) => normalizeRevenueOrderCode(row.orderCode))
          .filter((code): code is string => Boolean(code)),
      ),
    );
    const cacheRows = orderCodes.length
      ? await client.salesReportErpOrderCache.findMany({
          where: { orderCode: { in: orderCodes }, excludedAt: null },
          select: { orderCode: true, grandTotal: true },
        })
      : [];
    const lookup = buildCanonicalRevenueLookup(cacheRows);
    const missingCount = orderCodes.filter(
      (code) => !lookup.presentCodes.has(code),
    ).length;
    if (missingCount > 0 || lookup.invalidCodes.size > 0) {
      this.logger.warn(
        `Home revenue quality warning: source=${source} requestedOrders=${orderCodes.length} validOrders=${lookup.values.size} missingOrders=${missingCount} invalidOrders=${lookup.invalidCodes.size}`,
      );
    }
    return lookup;
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
      storeCode: this.normalizeStoreCode(row.storeCode),
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
    employeeNamesByKey: Map<string, string>,
  ): HomeSummaryUnreportedOrderDetail {
    const storeCode = this.normalizeStoreCode(row.storeCode);
    return {
      orderCode: this.normalizeOrderCode(row.orderCode) ?? '',
      grandTotal: typeof row.grandTotal === 'number' ? row.grandTotal : null,
      soldAt: row.orderCreatedAt ?? null,
      storeCode,
      salesName:
        this.employeeNameForStore(
          employeeNamesByKey,
          row.consultantEmail,
          storeCode,
        ) ??
        this.displayPersonName(row.consultantName, row.consultantEmail) ??
        this.employeeNameForStore(
          employeeNamesByKey,
          row.sellerEmail,
          storeCode,
        ) ??
        this.displayPersonName(row.sellerName, row.sellerEmail) ??
        this.employeeNameForStore(
          employeeNamesByKey,
          row.sourceUserEmail,
          storeCode,
        ) ??
        this.normalizeEmail(row.sourceUserEmail),
    };
  }

  private async unreportedEmployeeNamesByEmail(rows: any[]) {
    const candidates = rows
      .flatMap((row) => [
        {
          email: this.normalizeEmail(row.consultantEmail),
          storeCode: this.normalizeStoreCode(row.storeCode),
        },
        {
          email: this.normalizeEmail(row.sellerEmail),
          storeCode: this.normalizeStoreCode(row.storeCode),
        },
        {
          email: this.normalizeEmail(row.sourceUserEmail),
          storeCode: this.normalizeStoreCode(row.storeCode),
        },
      ])
      .filter((candidate): candidate is { email: string; storeCode: string } =>
        Boolean(candidate.email && candidate.storeCode),
      );
    if (candidates.length === 0) return new Map<string, string>();
    const emails = Array.from(
      new Set(candidates.map((candidate) => candidate.email)),
    );
    const users = await this.prisma.user.findMany({
      where: {
        status: 'yes',
        email: { in: emails, mode: 'insensitive' },
      },
      include: {
        jobRole: true,
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
    const usersByEmail = new Map<string, any>();
    for (const user of users) {
      const email = this.normalizeEmail(user.email);
      if (email) usersByEmail.set(email, user);
    }
    const result = new Map<string, string>();
    for (const candidate of candidates) {
      const user = usersByEmail.get(candidate.email);
      if (!user || !this.userHasStore(user, candidate.storeCode)) continue;
      const label = this.displayPersonName(
        [user.firstName, user.lastName].filter(Boolean).join(' ').trim(),
        user.email,
      );
      if (label) {
        result.set(
          this.salesPersonStoreKey(candidate.email, candidate.storeCode),
          label,
        );
      }
    }
    return result;
  }

  private employeeNameForStore(
    employeeNamesByKey: Map<string, string>,
    emailValue: unknown,
    storeCode: string | null,
  ) {
    const email = this.normalizeEmail(emailValue);
    if (!email || !storeCode) return null;
    return (
      employeeNamesByKey.get(this.salesPersonStoreKey(email, storeCode)) ?? null
    );
  }

  private salesPersonStoreKey(email: string, storeCode: string) {
    return `${email.toLowerCase()}|${storeCode.toUpperCase()}`;
  }

  private userHasStore(user: any, storeCode: string) {
    const normalized = this.normalizeStoreCode(storeCode);
    if (!normalized) return false;
    const stores = new Set<string>();
    const ownStore = this.normalizeStoreCode(user?.store?.storeId);
    if (ownStore) stores.add(ownStore);
    for (const store of storesForOrganizationNodeTree(user?.organizationNode)) {
      const code = this.normalizeStoreCode(store.storeId);
      if (code) stores.add(code);
    }
    for (const assignment of user?.organizationAssignments ?? []) {
      for (const store of storesForOrganizationNodeTree(
        assignment.organizationNode,
      )) {
        const code = this.normalizeStoreCode(store.storeId);
        if (code) stores.add(code);
      }
    }
    return stores.has(normalized);
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
    const userId = this.optionalText(user?.id, 80);
    if (userId) return `userId:${userId}`;
    const email = this.normalizeEmail(user?.email);
    return email ? `emailHash:${logFingerprint(email)}` : 'missing';
  }
}
