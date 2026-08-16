import {
  BadGatewayException,
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
  Optional,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import {
  constants as cryptoConstants,
  createHash,
  publicEncrypt,
} from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { decryptSecret } from '../common/secret-cipher';
import { PaymentNotificationsService } from '../payment-notifications/payment-notifications.service';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { FeatureService } from '../feature/feature.service';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { PolicyService } from '../policy/policy.service';
import { RedisService } from '../redis/redis.service';
import {
  APP_NOTIFICATION_SOURCE_STATEMENT_ORDER_TRANSFER,
  NotificationsService,
} from '../notifications';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { buildRealtimeRedisEnvelope } from '../common/realtime-event';
import { isPostgresDeadlock } from '../common/postgres-deadlock-retry';
import {
  SalesReportErpService,
  type SalesReportErpLifecycleStatus,
} from '../sales-reports/sales-report-erp.service';
import {
  BatchUpdateMapVietinStatementOrderTrackingDto,
  CreateMapVietinStatementOrderTransferRequestDto,
  ExportMapVietinStatementsDto,
  ListMapVietinStatementOrderTransferRequestsDto,
  ListStoredMapVietinTransactionsDto,
  ListMapVietinStatementsDto,
  ReviewMapVietinStatementOrderTransferRequestDto,
  SearchMapVietinTransactionsDto,
  UpdateMapVietinStatementIncomeTypeDto,
  UpdateMapVietinStatementOrderTrackingDto,
  UpdateMapVietinStatementOrdersDto,
} from './map-vietin.dto';
import {
  classifyMapVietinIncomeType,
  mapVietinIncomeTypeLabel,
  MAP_VIETIN_INCOME_TYPE,
} from './income-type';
import { resolveStoredStatementNumber } from './statement-identifiers';
import {
  BankProviderHttpException,
  EfastSession,
  MapSession,
  MapVietinProviderRuntime,
} from './map-vietin-provider.runtime';
import {
  MapVietinSyncCoordinator,
  type MapVietinSyncOptions,
} from './map-vietin-sync.runtime';
import {
  MapVietinPersistenceRuntime,
  type MapPersistStats,
  type MapTransactionRow,
} from './map-vietin-persistence.runtime';
import { MapVietinAccountRoutingRuntime } from './map-vietin-account-routing.runtime';
import { MapVietinStatementPolicyRuntime } from './map-vietin-statement-policy.runtime';
import {
  MapVietinStatementResponseRuntime,
  type MapVietinStoredTransactionRow,
} from './map-vietin-response.runtime';

const MAP_CLIENT_ID = 'c4a59ac3630f6d8f1abe722eac7052b5';
const MAP_SIGNATURE_KEY = '***REMOVED***';
const MAP_NO_AUTH_BASE_URL =
  'https://map.vietinbank.vn/vtb/public/map/api/ma/no-auth';
const MAP_TRANSACTION_BASE_URL =
  'https://map.vietinbank.vn/vtb/public/map/api/rpt-txnmng/api';
const GLOBAL_SYNC_STATE_CODE = '__GLOBAL__';
const EFAST_SYNC_STATE_CODE = '__EFAST__';
const EFAST_BASE_URL = 'https://efast.vietinbank.vn';
const EFAST_API_PREFIX = '/api/v1';
const EFAST_SUCCESS_CODE = '1';
const EFAST_SHARED_USER_CODE = '88';
const EFAST_INVALID_SESSION_CODE = '-1';
const EFAST_DEFAULT_PAGE_SIZE = 150;
const EFAST_DEFAULT_MAX_PAGES = 1;
const EFAST_DEFAULT_SESSION_TTL_SECONDS = 10 * 60;
const EFAST_PUBLIC_KEY =
  'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCz1zqQHtHvKczHh58ePiRNgOyiHEx6lZDPlvwBTaHmkNlQyyJ06SIlMU1pmGKxILjT7n06nxG7LlFVUN5MkW/jwF39/+drkHM5B0kh+hPQygFjRq81yxvLwolt+Vq7h+CTU0Z1wkFABcTeQQldZkJlTpyx0c3+jq0o47wIFjq5fwIDAQAB';
const MAP_SYNC_PAGE_SIZE = 100;
const DEFAULT_GLOBAL_SYNC_MAX_PAGES = 2;
const DEFAULT_GLOBAL_SESSION_TTL_SECONDS = 10 * 60;
const VIETNAM_UTC_OFFSET_HOURS = 7;
const ORDER_SOURCE_MANUAL = 'MANUAL';
const ORDER_SOURCE_OFFSET = 'OFFSET';
const ORDER_SOURCE_ERP_REPLACEMENT = 'ERP_REPLACEMENT';
const ORDER_RESOLUTION_SOURCE_ERP = 'ERP';
const INCOME_TYPE_SOURCE_AUTO = 'AUTO';
const INCOME_TYPE_SOURCE_MANUAL = 'MANUAL';
const FIN_ACC_DEPARTMENT_CODE = 'FIN_ACC';
const ACC_DEPARTMENT_CODE = 'ACC';
const ORDER_EDIT_FORBIDDEN_MESSAGE = 'Bạn không có quyền sửa đơn hàng.';
const ORDER_ACTION_REQUIRES_STATEMENT_PERMISSION_MESSAGE =
  'Bạn cần quyền Sao kê để cập nhật mã đơn hàng.';
const ORDER_TRANSFER_WINDOW_FORBIDDEN_MESSAGE =
  'Quá thời hạn cập nhật trong ngày. Vui lòng dùng chức năng Cấn trừ.';
const STATEMENT_ORDER_STATUS_ALL = 'ALL';
const STATEMENT_ORDER_STATUS_HAS_ORDER = 'HAS_ORDER';
const STATEMENT_ORDER_STATUS_MISSING_ORDER = 'MISSING_ORDER';
const STATEMENT_ORDER_STATUS_OFFSET_PENDING = 'OFFSET_PENDING';
const STATEMENT_ORDER_STATUS_OFFSET_CONFIRMED = 'OFFSET_CONFIRMED';
const STATEMENT_ORDER_STATUS_UNFOLLOWED = 'UNFOLLOWED';
const ORDER_TRACKING_STATUS_FOLLOWING = 'FOLLOWING';
const ORDER_TRACKING_STATUS_UNFOLLOWED = 'UNFOLLOWED';
const STATEMENT_EXPORT_MAX_DATE_SPAN_DAYS = 31;
const STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING = 'PENDING';
const STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_APPROVED = 'APPROVED';
const STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_REJECTED = 'REJECTED';
const STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_EXPIRED = 'EXPIRED';
const STATEMENT_ORDER_TRANSFER_NOTIFICATION_STATUS = 'NOTIFICATION';
const STATEMENT_ORDER_TRANSFER_CHANNEL = 'STATEMENT_ORDER_TRANSFER_REQUESTED';
const MS_PER_DAY = 24 * 60 * 60 * 1000;

type MapLoginResponse = {
  error_code?: string;
  error_desc?: string;
  message?: string;
  access_token?: string;
  merchant_info?: Array<{
    merchant_id?: string | number;
    merchant_type?: string;
    is_default?: boolean;
  }>;
};

type MapSearchResponse = {
  data?: {
    list?: unknown[];
    pageIndex?: number;
    pageSize?: number;
    total?: number;
  };
  message?: string;
  code?: string;
};

type MapGlobalSyncOptions = MapVietinSyncOptions;

type EfastStatus = {
  code?: string;
  message?: string;
  subCode?: string;
};

type EfastLoginResponse = {
  status?: EfastStatus;
  sessionId?: string;
  corpUser?: {
    username?: string;
    cifno?: string;
    enterpriseid?: string;
    enterpriseId?: string;
  };
  listCifShared?: Array<{
    cifno?: string;
    enterpriseid?: string;
    enterpriseId?: string;
  }>;
};

type EfastHistoryResponse = {
  status?: EfastStatus;
  transactions?: unknown[];
  currentPage?: number;
  nextPage?: number;
};

@Injectable()
export class MapVietinService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MapVietinService.name);
  private readonly providerRuntime: MapVietinProviderRuntime;
  private readonly syncCoordinator: MapVietinSyncCoordinator;
  private readonly persistenceRuntime: MapVietinPersistenceRuntime;
  private readonly accountRoutingRuntime: MapVietinAccountRoutingRuntime;
  private readonly statementPolicyRuntime: MapVietinStatementPolicyRuntime;
  private readonly statementResponseRuntime: MapVietinStatementResponseRuntime;
  private readonly amountKeys = [
    'amount',
    'txnAmount',
    'transactionAmount',
    'paymentAmount',
    'paidAmount',
    'totalAmount',
    'transAmount',
    'txnAmt',
  ];
  private readonly contentKeys = [
    'transactionDescription',
    'description',
    'content',
    'transferContent',
    'addInfo',
    'additionalInfo',
    'remark',
    'remarks',
    'txnDesc',
    'txnRemark',
    'transactionContent',
    'paymentContent',
  ];
  private readonly statusKeys = [
    'statusText',
    'status',
    'statusName',
    'transactionStatus',
    'transactionStatusName',
    'txnStatus',
    'txnStatusName',
    'paymentStatus',
    'paymentStatusName',
  ];
  private readonly transactionNumberKeys = [
    'transactionNumber',
    'txnNumber',
    'tranNumber',
    'transactionNo',
    'txnNo',
    'trxId',
    'trxRefNo',
    'id',
  ];
  private readonly transactionReferenceKeys = ['txnReference', 'trxRefNo'];
  private readonly transactionTimeKeys = [
    'tranTime',
    'tranDate',
    'txnDate',
    'transactionDate',
    'transactionTime',
    'paymentDate',
    'createdDate',
  ];
  private readonly payerNameKeys = [
    'payerName',
    'payerFullName',
    'reqCardName',
    'requestCardName',
    'senderName',
    'senderFullName',
    'fromAccountName',
    'debitAccountName',
    'corresponsiveName',
    'customerName',
    'buyerName',
  ];
  private readonly payerAccountKeys = [
    'payerAccount',
    'payerAccountNo',
    'reqCardNo',
    'requestCardNo',
    'senderAccount',
    'senderAccountNo',
    'fromAccount',
    'fromAccountNo',
    'debitAccount',
    'debitAccountNo',
    'corresponsiveAccount',
  ];
  private readonly virtualAccountKeys = [
    'virtualAccount',
    'virtualAcct',
    'virtualAccountNo',
    'creditAccount',
    'creditAccountNo',
    'receiveAccount',
    'receiveAccountNo',
    'beneficiaryAccount',
    'beneficiaryAccountNo',
  ];
  private readonly efastVirtualAccountKeys = [
    'pmtId',
    'pmtID',
    'pmtid',
    'paymentId',
    'paymentID',
  ];

  constructor(
    private prisma: PrismaService,
    private policyService: PolicyService,
    private featureService: FeatureService,
    @Optional()
    private paymentNotifications?: PaymentNotificationsService,
    @Optional()
    private redisService?: RedisService,
    @Optional()
    private notificationsService?: NotificationsService,
    @Optional()
    private salesReportErpService?: SalesReportErpService,
    @Optional()
    providerRuntime?: MapVietinProviderRuntime,
    @Optional()
    syncCoordinator?: MapVietinSyncCoordinator,
  ) {
    this.providerRuntime = providerRuntime ?? new MapVietinProviderRuntime();
    this.syncCoordinator = syncCoordinator ?? new MapVietinSyncCoordinator();
    this.persistenceRuntime = new MapVietinPersistenceRuntime({
      prisma: this.prisma,
      paymentNotifications: this.paymentNotifications,
      logger: this.logger,
      amountKeys: this.amountKeys,
      contentKeys: this.contentKeys,
      statusKeys: this.statusKeys,
      transactionNumberKeys: this.transactionNumberKeys,
      transactionReferenceKeys: this.transactionReferenceKeys,
      payerNameKeys: this.payerNameKeys,
      payerAccountKeys: this.payerAccountKeys,
      readAmount: (row) => this.readAmount(row),
      isSuccessfulTransaction: (row) => this.isSuccessfulTransaction(row),
      readFirstText: (row, keys) => this.readFirstText(row, keys),
      readTransactionTime: (row) => this.readTransactionTime(row),
      extractOrderCodesFromContent: (content) =>
        this.extractOrderCodesFromContent(content),
      isEfastMapTransactionRow: (row) => this.isEfastMapTransactionRow(row),
      rawDataAsMapRow: (value) => this.rawDataAsMapRow(value),
      readPositiveInt: (name, fallback) => this.readPositiveInt(name, fallback),
      safeError: (error) => this.safeError(error),
    });
    this.accountRoutingRuntime = new MapVietinAccountRoutingRuntime({
      prisma: this.prisma,
      logger: this.logger,
      contentKeys: this.contentKeys,
      transactionNumberKeys: this.transactionNumberKeys,
      statusKeys: this.statusKeys,
      payerNameKeys: this.payerNameKeys,
      payerAccountKeys: this.payerAccountKeys,
      readAmount: (row) => this.readAmount(row),
      isSuccessfulTransaction: (row) => this.isSuccessfulTransaction(row),
      readFirstText: (row, keys) => this.readFirstText(row, keys),
      readTransactionTime: (row) => this.readTransactionTime(row),
      isEfastMapTransactionRow: (row) => this.isEfastMapTransactionRow(row),
      resolveGlobalVirtualAccount: (row) => this.resolveGlobalVirtualAccount(row),
      resolveEfastSourceAccount: (row) => this.resolveEfastSourceAccount(row),
      normalizeAccountNumber: (value) => this.normalizeAccountNumber(value),
      scrubJson: (value) => this.scrubJson(value),
      maskAccount: (value) => this.maskAccount(value),
      persistTransactions: (storeCode, rows, stats) =>
        this.persistTransactions(storeCode, rows, stats),
    });
    this.statementPolicyRuntime = new MapVietinStatementPolicyRuntime({
      canAccessStatements: (user) => this.canUseStatements(user),
      hasNationalScope: (user) => this.hasNationalStatementScope(user),
      resolveUserStores: (user) => this.resolveUserStores(user),
      isPhongVuEmail: (email) => this.isPhongVuEmail(email),
      userMatchesAccessCodes: (user, codes) =>
        this.userMatchesStatementAccessCodes(user, codes),
      userBelongsToAccessCodes: (user, codes) =>
        this.userBelongsToStatementAccessCodes(user, codes),
      finAccDepartmentCode: FIN_ACC_DEPARTMENT_CODE,
      accDepartmentCode: ACC_DEPARTMENT_CODE,
      vietnamDateToken: (value) => this.vietnamDateToken(value),
      now: () => new Date(Date.now()),
    });
    this.statementResponseRuntime = new MapVietinStatementResponseRuntime({
      resolveStoredPayer: (row) => this.resolveStoredPayer(row),
      resolveStoredTransactionReference: (row) =>
        this.resolveStoredTransactionReference(row),
      resolveStoredReceivingAccount: (row) =>
        this.resolveStoredReceivingAccount(row),
      storedIncomeType: (row) => this.storedIncomeType(row),
      storedOrderTrackingStatus: (row) => this.storedOrderTrackingStatus(row),
      isStatementOrderTransferWindowOpen: (row) =>
        this.isStatementOrderTransferWindowOpen(row),
      mapIncomeTypeLabel: (incomeType) => mapVietinIncomeTypeLabel(incomeType),
      orderTrackingFollowing: ORDER_TRACKING_STATUS_FOLLOWING,
      orderTrackingUnfollowed: ORDER_TRACKING_STATUS_UNFOLLOWED,
      orderSourceOffset: ORDER_SOURCE_OFFSET,
      statementOrderTransferPendingStatus:
        STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
      statementOrderTransferApprovedStatus:
        STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_APPROVED,
      orderActionRequiresStatementPermissionMessage:
        ORDER_ACTION_REQUIRES_STATEMENT_PERMISSION_MESSAGE,
      orderTransferWindowForbiddenMessage:
        ORDER_TRANSFER_WINDOW_FORBIDDEN_MESSAGE,
      incomeTypeSourceAuto: INCOME_TYPE_SOURCE_AUTO,
      vietnamUtcOffsetHours: VIETNAM_UTC_OFFSET_HOURS,
    });
    this.syncCoordinator.configure({
      logger: this.logger,
      isMapHistorySyncDisabled: () => this.isMapHistorySyncDisabled(),
      isEfastSyncEnabled: () => this.isEfastSyncEnabled(),
      mapProviderBackoffUntil: () => this.mapProviderBackoffUntil,
      globalSyncMaxPages: () => this.globalSyncMaxPages(),
      readPositiveInt: (name, fallback) => this.readPositiveInt(name, fallback),
      resetProviderBackoff: () => this.providerRuntime.resetBackoff(),
      clearFingerprintCache: () =>
        this.persistenceRuntime.clearFingerprintCache(),
      safeError: (error) => this.safeError(error),
      syncConfiguredStores: (options) => this.syncConfiguredStores(options),
      syncEfastTransactions: () => this.syncEfastTransactions(),
    });
  }

  private get mapProviderBackoffUntil() {
    return this.providerRuntime.mapProviderBackoffUntil;
  }

  private get mapProviderBackoffAttempt() {
    return this.providerRuntime.mapProviderBackoffAttempt;
  }

  onModuleInit() {
    this.syncCoordinator.onModuleInit();
  }

  onModuleDestroy() {
    this.syncCoordinator.onModuleDestroy();
  }

  async searchTransactions(admin: any, input: SearchMapVietinTransactionsDto) {
    const store = await this.resolveStore(admin, input.storeId);
    return this.searchTransactionsForStore(store, input);
  }

  async listStoredTransactions(
    user: any,
    input: ListStoredMapVietinTransactionsDto,
  ) {
    await this.expireStaleStatementOrderTransferRequests();
    const storeScope = await this.resolveReadableStoreScope(user, {
      storeId: input.storeId,
      storeIds: input.storeIds,
      allStores: input.allStores,
    });
    const canUseStatements = await this.canUseStatements(user);
    const [canReviewOrderTransfers, canManageTracking] = canUseStatements
      ? await Promise.all([
          this.canReviewStatementOrderTransferRequests(user),
          this.canManageStatementOrderTracking(user),
        ])
      : [false, false];
    const afterFirstSeenAt = input.afterFirstSeenAt
      ? this.parseDate(input.afterFirstSeenAt, 'afterFirstSeenAt')
      : null;
    const localDateRange = this.resolveStoredTransactionDateRange(input);
    const limit = input.limit ?? 10;
    const page = input.page ?? 0;
    const includeTotal =
      String(input.includeTotal ?? 'true')
        .trim()
        .toLowerCase() !== 'false';
    const where: Prisma.MapVietinTransactionWhereInput = {
      ...(storeScope.storeCodes.length > 0
        ? { storeCode: this.storeCodeWhere(storeScope.storeCodes) }
        : {}),
      ...(afterFirstSeenAt ? { firstSeenAt: { gt: afterFirstSeenAt } } : {}),
      ...(localDateRange
        ? {
            OR: [
              {
                paidAt: {
                  gte: localDateRange.start,
                  lt: localDateRange.end,
                },
              },
              {
                paidAt: null,
                firstSeenAt: {
                  gte: localDateRange.start,
                  lt: localDateRange.end,
                },
              },
            ],
          }
        : {}),
    };
    const rowsPromise = this.prisma.mapVietinTransaction.findMany({
      where,
      include: {
        orderTransferRequests: {
          where: { status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING },
          orderBy: { createdAt: 'desc' },
          take: 1,
        },
      },
      orderBy: [{ paidAt: 'desc' }, { firstSeenAt: 'desc' }],
      skip: page * limit,
      take: limit,
    });
    const [rows, total] = await Promise.all([
      rowsPromise,
      includeTotal
        ? this.prisma.mapVietinTransaction.count({ where })
        : Promise.resolve(null),
    ]);

    return {
      storeId: storeScope.storeCodes[0] ?? null,
      storeIds: storeScope.storeCodes,
      allStores: storeScope.allStores,
      page,
      limit,
      ...(total !== null ? { total } : {}),
      canReviewOrderTransfers,
      list: rows.map((row) =>
        this.toStoredTransactionDto(row, {
          canUseStatements,
          canManageTracking,
        }),
      ),
    };
  }

  async listStatements(user: any, input: ListMapVietinStatementsDto) {
    await this.expireStaleStatementOrderTransferRequests();
    const query = await this.buildStatementQuery(user, input, {
      requireFilter: true,
    });
    const [rows, total] = await Promise.all([
      this.prisma.mapVietinTransaction.findMany({
        where: query.where,
        include: {
          orderTransferRequests: {
            where: { status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING },
            orderBy: { createdAt: 'desc' },
            take: 1,
          },
        },
        orderBy: [{ paidAt: 'desc' }, { firstSeenAt: 'desc' }],
        skip: query.page * query.limit,
        take: query.limit,
      }),
      this.prisma.mapVietinTransaction.count({ where: query.where }),
    ]);

    this.logger.log(
      `Statement search succeeded: user=${this.safeUserLabel(user)} total=${total} page=${query.page} limit=${query.limit} filters=${query.filterSummary}`,
    );
    const [canEditIncomeType, canManageTracking] = await Promise.all([
      this.canEditStatementIncomeType(user),
      this.canManageStatementOrderTracking(user),
    ]);
    const actionScope =
      rows.length > 0 ? await this.resolveStatementActionScope(user) : null;

    return {
      page: query.page,
      limit: query.limit,
      total,
      list: rows.map((row) => {
        const verifiedOrderLookupEdit = this.matchesStatementOrderUpdateLookup(
          row,
          query.verifiedOrderLookup,
        );
        const canUseStatementActions =
          !actionScope ||
          actionScope.allStores ||
          (row.storeCode
            ? actionScope.storeCodes.includes(row.storeCode)
            : actionScope.includeUnassigned) ||
          verifiedOrderLookupEdit;
        const canUseScopedStatementActions =
          !actionScope ||
          actionScope.allStores ||
          (row.storeCode
            ? actionScope.storeCodes.includes(row.storeCode)
            : actionScope.includeUnassigned);
        return this.toStoredTransactionDto(row, {
          canUseStatements: canUseStatementActions,
          canEditIncomeType: canEditIncomeType && canUseStatementActions,
          canManageTracking: canManageTracking && canUseScopedStatementActions,
        });
      }),
    };
  }

  async exportStatementsXlsx(user: any, input: ExportMapVietinStatementsDto) {
    const selectedIds = this.normalizeTransactionIds(input.transactionIds);
    const mode = selectedIds.length ? 'selected' : 'filter';
    const startedAt = Date.now();
    this.logger.log(
      `Statement export started: user=${this.safeUserLabel(user)} mode=${mode} selectedCount=${selectedIds.length}`,
    );
    try {
      await this.assertCanUseStatements(user);
      this.assertStatementExportDateRangeAllowed(input);
      const where = selectedIds.length
        ? await this.buildSelectedStatementWhere(user, input, selectedIds)
        : (
            await this.buildStatementQuery(user, input, {
              requireFilter: true,
            })
          ).where;
      const rows = await this.prisma.mapVietinTransaction.findMany({
        where,
        orderBy: [{ paidAt: 'desc' }, { firstSeenAt: 'desc' }],
      });
      const transactionReferenceCount = rows.filter((row) =>
        Boolean(this.resolveStoredTransactionReference(row)),
      ).length;
      this.logger.log(
        `Statement export succeeded: user=${this.safeUserLabel(user)} mode=${mode} count=${rows.length} transactionReferenceCount=${transactionReferenceCount} durationMs=${Date.now() - startedAt}`,
      );
      const incomeTypeCounts = rows.reduce(
        (counts, row) => {
          const incomeType = this.storedIncomeType(row);
          counts[incomeType] = (counts[incomeType] || 0) + 1;
          return counts;
        },
        {} as Record<string, number>,
      );
      this.logger.log(
        `Statement export income types: user=${this.safeUserLabel(user)} sales=${incomeTypeCounts[MAP_VIETIN_INCOME_TYPE.SALES] || 0} partnerInternal=${incomeTypeCounts[MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL] || 0}`,
      );
      return this.toStatementsXlsx(rows);
    } catch (error) {
      this.logger.error(
        `Statement export failed: user=${this.safeUserLabel(user)} mode=${mode} selectedCount=${selectedIds.length} durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      throw error;
    }
  }

  private assertStatementExportDateRangeAllowed(
    input: ExportMapVietinStatementsDto,
  ) {
    const dateRange = this.resolveStoredTransactionDateRange(input);
    if (!dateRange) return;
    const spanDays = Math.round(
      (dateRange.end.getTime() - dateRange.start.getTime()) / MS_PER_DAY,
    );
    if (spanDays > STATEMENT_EXPORT_MAX_DATE_SPAN_DAYS) {
      throw new BadRequestException(
        'Chỉ được export sao kê trong tối đa 1 tháng',
      );
    }
  }

  async updateStatementOrders(
    user: any,
    transactionId: string,
    input: UpdateMapVietinStatementOrdersDto,
  ) {
    const startedAt = Date.now();
    try {
      const result = await this.applyStatementOrderMutation(
        user,
        transactionId,
        input,
        { createCompatibilityRequest: false },
      );
      return result.transaction;
    } catch (error) {
      this.logger.warn(
        `Statement ERP order update failed: user=${this.safeUserLabel(user)} transaction=${String(transactionId || '').trim() || 'missing'} endpoint=patch durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      throw error;
    }
  }

  async updateStatementIncomeType(
    user: any,
    transactionId: string,
    input: UpdateMapVietinStatementIncomeTypeDto,
  ) {
    const startedAt = Date.now();
    await this.assertCanUseStatements(user);
    const id = String(transactionId || '').trim();
    const nextIncomeType = String(input.incomeType || '')
      .trim()
      .toUpperCase();
    this.logger.log(
      `Statement income type update started: user=${this.safeUserLabel(user)} transaction=${id || 'missing'} target=${nextIncomeType || 'missing'}`,
    );
    try {
      if (!id) throw new BadRequestException('Giao dịch không hợp lệ');
      if (
        nextIncomeType !== MAP_VIETIN_INCOME_TYPE.SALES &&
        nextIncomeType !== MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL
      ) {
        throw new BadRequestException('Loại giao dịch không hợp lệ');
      }
      if (!(await this.canEditStatementIncomeType(user))) {
        throw new ForbiddenException(
          'Bạn không có quyền thay đổi loại giao dịch sao kê.',
        );
      }
      const existing = await this.prisma.mapVietinTransaction.findUnique({
        where: { id },
      });
      if (!existing) throw new BadRequestException('Giao dịch không hợp lệ');
      await this.assertCanReadStatementStore(user, existing.storeCode);
      const previousIncomeType = this.storedIncomeType(existing);
      const updated = await this.prisma.mapVietinTransaction.update({
        where: { id },
        data: {
          incomeType: nextIncomeType,
          incomeTypeSource: INCOME_TYPE_SOURCE_MANUAL,
          incomeTypeUpdatedAt: new Date(),
          incomeTypeUpdatedByUserId: user?.id || null,
          incomeTypeUpdatedByEmail: this.safeUserEmail(user),
        },
      });
      this.logger.log(
        `Statement income type update succeeded: user=${this.safeUserLabel(user)} transaction=${id} store=${existing.storeCode || 'null'} previous=${previousIncomeType} next=${nextIncomeType} changed=${previousIncomeType !== nextIncomeType} durationMs=${Date.now() - startedAt}`,
      );
      return this.toStoredTransactionDto(updated, {
        canEditProtectedOrders: true,
        canEditIncomeType: true,
      });
    } catch (error) {
      this.logger.warn(
        `Statement income type update failed: user=${this.safeUserLabel(user)} transaction=${id || 'missing'} target=${nextIncomeType || 'missing'} durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      throw error;
    }
  }

  async updateStatementOrderTracking(
    user: any,
    transactionId: string,
    input: UpdateMapVietinStatementOrderTrackingDto,
  ) {
    const startedAt = Date.now();
    await this.assertCanUseStatements(user);
    const id = String(transactionId || '').trim();
    const nextStatus = String(input.status || '')
      .trim()
      .toUpperCase();
    if (!id) throw new BadRequestException('Giao dịch không hợp lệ');
    if (
      nextStatus !== ORDER_TRACKING_STATUS_FOLLOWING &&
      nextStatus !== ORDER_TRACKING_STATUS_UNFOLLOWED
    ) {
      throw new BadRequestException('Trạng thái theo dõi không hợp lệ');
    }
    if (!(await this.canManageStatementOrderTracking(user))) {
      throw new ForbiddenException(
        'Bạn không có quyền thay đổi trạng thái theo dõi giao dịch.',
      );
    }
    const existing = await this.prisma.mapVietinTransaction.findUnique({
      where: { id },
    });
    if (!existing) throw new BadRequestException('Giao dịch không hợp lệ');
    await this.assertCanReadStatementStore(user, existing.storeCode);
    const pending =
      await this.prisma.mapVietinStatementOrderTransferRequest.findFirst({
        where: {
          transactionId: id,
          status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
        },
      });
    if (pending) {
      throw new BadRequestException(
        'Giao dịch đang chờ Kế toán xác nhận. Vui lòng xử lý yêu cầu cũ trước.',
      );
    }
    const oldStatus = this.storedOrderTrackingStatus(existing);
    if (oldStatus === nextStatus) {
      this.logger.log(
        `Statement tracking update skipped: user=${this.safeUserLabel(user)} transaction=${id} status=${nextStatus} reason=no_change`,
      );
      return this.toStoredTransactionDto(existing, {
        canUseStatements: true,
        canEditIncomeType: await this.canEditStatementIncomeType(user),
        canManageTracking: true,
      });
    }

    const now = new Date();
    const userEmail = this.safeUserEmail(user);
    const updated = await this.runStatementOptimisticTransaction(() =>
      this.prisma.$transaction(async (tx) => {
        const current = await tx.mapVietinTransaction.findUnique({
          where: { id },
        });
        const currentPending =
          await tx.mapVietinStatementOrderTransferRequest.findFirst({
            where: {
              transactionId: id,
              status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
            },
          });
        if (
          !current ||
          currentPending ||
          !this.sameInstant(current.updatedAt, existing.updatedAt) ||
          this.storedOrderTrackingStatus(current) !== oldStatus
        ) {
          throw new BadRequestException(
            'Dữ liệu giao dịch vừa thay đổi. Vui lòng tải lại và thử lại.',
          );
        }
        const row = await tx.mapVietinTransaction.update({
          where: {
            id,
            updatedAt: existing.updatedAt,
            orderTrackingStatus: oldStatus,
          },
          data: {
            orderTrackingStatus: nextStatus,
            orderTrackingUpdatedAt: now,
            orderTrackingUpdatedByUserId: user.id || null,
            orderTrackingUpdatedByEmail: userEmail,
          },
        });
        await tx.mapVietinTransactionOrderTrackingAudit.create({
          data: {
            transactionId: id,
            storeCode: existing.storeCode,
            oldStatus,
            newStatus: nextStatus,
            changedByUserId: user.id || null,
            changedByEmail: userEmail,
            source: ORDER_SOURCE_MANUAL,
          },
        });
        return row;
      }),
    );
    this.logger.log(
      `Statement tracking update succeeded: user=${this.safeUserLabel(user)} transaction=${id} store=${existing.storeCode || 'null'} oldStatus=${oldStatus} newStatus=${nextStatus} durationMs=${Date.now() - startedAt}`,
    );
    return this.toStoredTransactionDto(updated, {
      canUseStatements: true,
      canEditIncomeType: await this.canEditStatementIncomeType(user),
      canManageTracking: true,
    });
  }

  async batchUpdateStatementOrderTracking(
    user: any,
    input: BatchUpdateMapVietinStatementOrderTrackingDto,
  ) {
    const startedAt = Date.now();
    await this.assertCanUseStatements(user);
    if (!(await this.canManageStatementOrderTracking(user))) {
      throw new ForbiddenException(
        'Bạn không có quyền bỏ theo dõi các giao dịch đã chọn.',
      );
    }
    const requestedIds = Array.isArray(input.transactionIds)
      ? input.transactionIds
      : [];
    const transactionIds = this.normalizeTransactionIds(requestedIds).sort();
    if (
      transactionIds.length < 1 ||
      transactionIds.length > 100 ||
      transactionIds.length !== requestedIds.length
    ) {
      throw new BadRequestException(
        'Chỉ được chọn từ 1 đến 100 giao dịch khác nhau mỗi lần.',
      );
    }
    const nextStatus = String(input.status || '')
      .trim()
      .toUpperCase();
    if (nextStatus !== ORDER_TRACKING_STATUS_UNFOLLOWED) {
      throw new BadRequestException(
        'Thao tác hàng loạt chỉ hỗ trợ Bỏ theo dõi.',
      );
    }
    this.logger.log(
      `Statement tracking batch update started: user=${this.safeUserLabel(user)} count=${transactionIds.length} nextStatus=${nextStatus}`,
    );

    try {
      const actionScope = await this.resolveStatementActionScope(user);
      const scopeWhere = this.statementActionScopeWhere(actionScope);
      const existingRows = await this.prisma.mapVietinTransaction.findMany({
        where: this.andWhere({ id: { in: transactionIds } }, scopeWhere),
      });
      if (existingRows.length !== transactionIds.length) {
        throw new BadRequestException(
          'Một số giao dịch không còn khả dụng. Vui lòng tải lại và chọn lại.',
        );
      }
      const pending =
        await this.prisma.mapVietinStatementOrderTransferRequest.findMany({
          where: {
            transactionId: { in: transactionIds },
            status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
          },
          select: { transactionId: true },
        });
      if (pending.length > 0) {
        throw new BadRequestException(
          `${pending.length} giao dịch đang chờ Kế toán xác nhận. Vui lòng xử lý yêu cầu cũ trước.`,
        );
      }

      const snapshots = new Map(
        existingRows.map((row) => [
          row.id,
          {
            updatedAt: row.updatedAt,
            oldStatus: this.storedOrderTrackingStatus(row),
            storeCode: row.storeCode,
          },
        ]),
      );
      const now = new Date();
      const userEmail = this.safeUserEmail(user);
      const result = await this.runStatementOptimisticTransaction(() =>
        this.prisma.$transaction(async (tx) => {
          await tx.$queryRaw(Prisma.sql`
            SELECT "id"
            FROM "MapVietinTransaction"
            WHERE "id" IN (${Prisma.join(transactionIds)})
            ORDER BY "id"
            FOR UPDATE
          `);
          const [currentRows, currentPending] = await Promise.all([
            tx.mapVietinTransaction.findMany({
              where: this.andWhere({ id: { in: transactionIds } }, scopeWhere),
            }),
            tx.mapVietinStatementOrderTransferRequest.findMany({
              where: {
                transactionId: { in: transactionIds },
                status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
              },
              select: { transactionId: true },
            }),
          ]);
          if (
            currentRows.length !== transactionIds.length ||
            currentPending.length > 0 ||
            currentRows.some((row) => {
              const snapshot = snapshots.get(row.id);
              return (
                !snapshot ||
                !this.sameInstant(row.updatedAt, snapshot.updatedAt) ||
                this.storedOrderTrackingStatus(row) !== snapshot.oldStatus
              );
            })
          ) {
            throw new BadRequestException(
              'Dữ liệu giao dịch vừa thay đổi. Vui lòng tải lại và thử lại.',
            );
          }

          const unchangedIds = transactionIds.filter(
            (id) =>
              snapshots.get(id)?.oldStatus === ORDER_TRACKING_STATUS_UNFOLLOWED,
          );
          if (unchangedIds.length > 0) {
            const noOpConcurrencyTokenAt = new Date(
              unchangedIds.reduce(
                (latest, id) =>
                  Math.max(
                    latest,
                    (snapshots.get(id)?.updatedAt.getTime() ?? 0) + 1,
                  ),
                now.getTime(),
              ),
            );
            const tokenBump = await tx.mapVietinTransaction.updateMany({
              where: {
                id: { in: unchangedIds },
                orderTrackingStatus: ORDER_TRACKING_STATUS_UNFOLLOWED,
              },
              data: { updatedAt: noOpConcurrencyTokenAt },
            });
            if (tokenBump.count !== unchangedIds.length) {
              throw new BadRequestException(
                'Dữ liệu giao dịch vừa thay đổi. Vui lòng tải lại và thử lại.',
              );
            }
          }

          let changedCount = 0;
          for (const id of transactionIds) {
            const snapshot = snapshots.get(id)!;
            if (snapshot.oldStatus === ORDER_TRACKING_STATUS_UNFOLLOWED) {
              continue;
            }
            await tx.mapVietinTransaction.update({
              where: {
                id,
                updatedAt: snapshot.updatedAt,
                orderTrackingStatus: snapshot.oldStatus,
              },
              data: {
                orderTrackingStatus: nextStatus,
                orderTrackingUpdatedAt: now,
                orderTrackingUpdatedByUserId: user.id || null,
                orderTrackingUpdatedByEmail: userEmail,
              },
            });
            await tx.mapVietinTransactionOrderTrackingAudit.create({
              data: {
                transactionId: id,
                storeCode: snapshot.storeCode,
                oldStatus: snapshot.oldStatus,
                newStatus: nextStatus,
                changedByUserId: user.id || null,
                changedByEmail: userEmail,
                source: ORDER_SOURCE_MANUAL,
              },
            });
            changedCount += 1;
          }
          return {
            processedCount: transactionIds.length,
            changedCount,
            unchangedCount: transactionIds.length - changedCount,
          };
        }),
      );
      this.logger.log(
        `Statement tracking batch update succeeded: user=${this.safeUserLabel(user)} count=${result.processedCount} changed=${result.changedCount} unchanged=${result.unchangedCount} durationMs=${Date.now() - startedAt}`,
      );
      return result;
    } catch (error) {
      this.logger.warn(
        `Statement tracking batch update failed: user=${this.safeUserLabel(user)} count=${transactionIds.length} durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      throw error;
    }
  }

  async createStatementOrderTransferRequest(
    user: any,
    transactionId: string,
    input: CreateMapVietinStatementOrderTransferRequestDto,
  ) {
    const startedAt = Date.now();
    try {
      const result = await this.applyStatementOrderMutation(
        user,
        transactionId,
        input,
        { createCompatibilityRequest: true },
      );
      return result.request;
    } catch (error) {
      this.logger.warn(
        `Statement ERP order update failed: user=${this.safeUserLabel(user)} transaction=${String(transactionId || '').trim() || 'missing'} endpoint=compatibility_post durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      throw error;
    }
  }

  private async applyStatementOrderMutation(
    user: any,
    transactionId: string,
    input:
      | UpdateMapVietinStatementOrdersDto
      | CreateMapVietinStatementOrderTransferRequestDto,
    options: { createCompatibilityRequest: boolean },
  ) {
    const startedAt = Date.now();
    await this.assertCanUseStatements(user);
    await this.expireStaleStatementOrderTransferRequests();
    const requestedId = String(transactionId || '').trim();
    if (!requestedId) throw new BadRequestException('Giao dịch không hợp lệ');
    const newOrders = this.normalizeOrderCodes(input.orders || []);
    const transactionKey = String(input.transactionKey || '').trim();
    this.logger.log(
      `Statement ERP order update started: user=${this.safeUserLabel(user)} transaction=${requestedId} oldEndpoint=${options.createCompatibilityRequest} newCount=${newOrders.length}`,
    );

    let existing = await this.prisma.mapVietinTransaction.findUnique({
      where: { id: requestedId },
    });
    let resolvedId = requestedId;
    if (!existing && transactionKey) {
      existing = await this.prisma.mapVietinTransaction.findUnique({
        where: { transactionKey },
      });
      if (existing) resolvedId = existing.id;
    }
    if (!existing) {
      throw new BadRequestException(
        'Không tìm thấy giao dịch mới nhất. Vui lòng tải lại danh sách rồi thử lại.',
      );
    }

    const lookup = this.normalizeStatementOrderUpdateLookup(
      input as UpdateMapVietinStatementOrdersDto,
    );
    const canReadStore = await this.canReadStatementStore(
      user,
      existing.storeCode,
    );
    const verifiedOrderLookupEdit = this.matchesStatementOrderUpdateLookup(
      existing,
      lookup.hasExactField ? lookup : null,
    );
    if (!canReadStore && !verifiedOrderLookupEdit) {
      throw new ForbiddenException(
        'Chỉ được sửa giao dịch showroom khác khi tìm chính xác bằng mã sao kê, mã đơn, số tiền hoặc nội dung chuyển khoản.',
      );
    }

    const oldOrders = this.normalizeOrderCodes(existing.orders || []);
    if (this.sameOrderList(oldOrders, newOrders)) {
      this.logger.log(
        `Statement ERP order update skipped: user=${this.safeUserLabel(user)} transaction=${resolvedId} reason=no_change oldCount=${oldOrders.length}`,
      );
      const [canEditIncomeType, canManageTracking] = await Promise.all([
        this.canEditStatementIncomeType(user),
        this.canManageStatementOrderTracking(user),
      ]);
      const noOpAt = existing.updatedAt || existing.firstSeenAt || new Date();
      return {
        transaction: this.toStoredTransactionDto(existing, {
          canUseStatements: true,
          canEditIncomeType,
          canManageTracking,
        }),
        request: options.createCompatibilityRequest
          ? this.toStatementOrderTransferRequestDto({
              id: `noop:${resolvedId}:${noOpAt.getTime()}`,
              transactionId: resolvedId,
              storeCode: existing.storeCode || '__all__',
              oldOrders,
              requestedOrders: newOrders,
              status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_APPROVED,
              requestedByUserId: user.id || null,
              requestedByEmail: this.safeUserEmail(user),
              reviewedByUserId: user.id || null,
              reviewedByEmail: this.safeUserEmail(user),
              resolutionSource: ORDER_RESOLUTION_SOURCE_ERP,
              reviewedAt: noOpAt,
              createdAt: noOpAt,
              updatedAt: noOpAt,
              transaction: existing,
            })
          : null,
      };
    }

    const pendingRequest =
      await this.prisma.mapVietinStatementOrderTransferRequest.findFirst({
        where: {
          transactionId: resolvedId,
          status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
        },
      });
    if (pendingRequest) {
      throw new BadRequestException(
        'Giao dịch đang chờ Kế toán xác nhận. Vui lòng xử lý yêu cầu cũ trước.',
      );
    }

    const trackingStatus = this.storedOrderTrackingStatus(existing);
    if (trackingStatus === ORDER_TRACKING_STATUS_UNFOLLOWED) {
      throw new BadRequestException(
        'Giao dịch đang Bỏ theo dõi. Vui lòng Theo dõi lại trước khi cập nhật mã đơn.',
      );
    }
    if (oldOrders.length === 0 && newOrders.length === 0) {
      throw new BadRequestException('Vui lòng nhập ít nhất một mã đơn hàng');
    }
    if (oldOrders.length > 0) {
      this.assertStatementOrderTransferWindow(existing);
    }

    const oldLifecycle = oldOrders.length
      ? await this.lookupStatementOrderLifecycles(
          oldOrders,
          existing.storeCode,
          'current',
        )
      : [];
    if (
      oldLifecycle.some(
        (status) => status !== 'CANCELLED' && status !== 'RETURNED_FULL',
      )
    ) {
      throw new BadRequestException(
        'Chỉ được cập nhật khi tất cả mã đơn hiện tại đã hủy hoặc hoàn trả toàn bộ trên hệ thống bán hàng.',
      );
    }

    const newLifecycle = newOrders.length
      ? await this.lookupStatementOrderLifecycles(
          newOrders,
          existing.storeCode,
          'new',
        )
      : [];
    if (
      newLifecycle.some(
        (status) => status === 'CANCELLED' || status === 'RETURNED_FULL',
      )
    ) {
      throw new BadRequestException(
        'Mã đơn mới đã bị hủy hoặc hoàn trả toàn bộ. Vui lòng chọn mã đơn còn hiệu lực.',
      );
    }

    const assignedStoreCode = existing.storeCode
      ? existing.storeCode
      : (await this.resolveUserStore(user)).storeId;
    const now = new Date();
    const userEmail = this.safeUserEmail(user);
    const snapshotUpdatedAt = existing.updatedAt;
    const result = await this.runStatementOptimisticTransaction(() =>
      this.prisma.$transaction(async (tx) => {
        const current = await tx.mapVietinTransaction.findUnique({
          where: { id: resolvedId },
        });
        const currentPending =
          await tx.mapVietinStatementOrderTransferRequest.findFirst({
            where: {
              transactionId: resolvedId,
              status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
            },
          });
        if (
          !current ||
          currentPending ||
          !this.sameInstant(current.updatedAt, snapshotUpdatedAt) ||
          !this.sameOrderList(
            this.normalizeOrderCodes(current.orders || []),
            oldOrders,
          ) ||
          this.storedOrderTrackingStatus(current) !== trackingStatus
        ) {
          throw new BadRequestException(
            'Dữ liệu giao dịch vừa thay đổi. Vui lòng tải lại và thử lại.',
          );
        }

        const updated = await tx.mapVietinTransaction.update({
          where: {
            id: resolvedId,
            updatedAt: snapshotUpdatedAt,
            orderTrackingStatus: trackingStatus,
            orders: { equals: oldOrders },
          },
          data: {
            storeCode: assignedStoreCode,
            orders: newOrders,
            orderSource: ORDER_SOURCE_ERP_REPLACEMENT,
            orderUpdatedAt: now,
            orderUpdatedByUserId: user.id || null,
            orderUpdatedByEmail: userEmail,
          },
        });
        await tx.mapVietinTransactionOrderAudit.create({
          data: {
            transactionId: resolvedId,
            storeCode: assignedStoreCode,
            oldOrders,
            newOrders,
            changedByUserId: user.id || null,
            changedByEmail: userEmail,
            source: ORDER_SOURCE_ERP_REPLACEMENT,
          },
        });

        const request = options.createCompatibilityRequest
          ? await tx.mapVietinStatementOrderTransferRequest.create({
              data: {
                transactionId: resolvedId,
                storeCode: assignedStoreCode,
                oldOrders,
                requestedOrders: newOrders,
                status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_APPROVED,
                requestedByUserId: user.id || null,
                requestedByEmail: userEmail,
                reviewedByUserId: user.id || null,
                reviewedByEmail: userEmail,
                reviewedAt: now,
                resolutionSource: ORDER_RESOLUTION_SOURCE_ERP,
              },
              include: { transaction: true },
            })
          : null;
        return { updated, request };
      }),
    );

    if (result.request) {
      await this.publishStatementOrderTransferRequestEvent({
        id: result.request.id,
        transactionId: result.request.transactionId,
        storeCode: result.request.storeCode,
        status: result.request.status,
        createdAt: result.request.createdAt,
      });
    }

    const [canEditIncomeType, canManageTracking] = await Promise.all([
      this.canEditStatementIncomeType(user),
      this.canManageStatementOrderTracking(user),
    ]);
    this.logger.log(
      `Statement ERP order update succeeded: user=${this.safeUserLabel(user)} transaction=${resolvedId} oldCount=${oldOrders.length} newCount=${newOrders.length} oldLifecycle=${this.lifecycleSummary(oldLifecycle)} newLifecycle=${this.lifecycleSummary(newLifecycle)} oldEndpoint=${options.createCompatibilityRequest} durationMs=${Date.now() - startedAt}`,
    );
    return {
      transaction: this.toStoredTransactionDto(result.updated, {
        canUseStatements: true,
        canEditIncomeType,
        canManageTracking,
      }),
      request: result.request
        ? this.toStatementOrderTransferRequestDto(result.request)
        : null,
    };
  }

  private async lookupStatementOrderLifecycles(
    orders: string[],
    storeCode: string | null,
    phase: 'current' | 'new',
  ): Promise<SalesReportErpLifecycleStatus[]> {
    if (!this.salesReportErpService) {
      throw new ServiceUnavailableException(
        'Chưa thể kiểm tra đơn hàng trên hệ thống bán hàng. Vui lòng thử lại sau ít phút.',
      );
    }
    const startedAt = Date.now();
    try {
      const rows = await Promise.all(
        orders.map((order) =>
          this.salesReportErpService!.lookupOrderStatus(order, storeCode),
        ),
      );
      const statuses = rows.map((row) => row.lifecycleStatus);
      if (rows.some((row) => row.lifecycleVerified !== true)) {
        throw new Error('unverified_lifecycle');
      }
      if (
        statuses.some(
          (status) =>
            ![
              'PENDING',
              'COMPLETED',
              'COMPLETED_PARTIAL_RETURN',
              'CANCELLED',
              'RETURNED_FULL',
            ].includes(status),
        )
      ) {
        throw new Error('missing_lifecycle');
      }
      this.logger.log(
        `Statement ERP lifecycle lookup succeeded: phase=${phase} count=${orders.length} summary=${this.lifecycleSummary(statuses)} durationMs=${Date.now() - startedAt}`,
      );
      return statuses;
    } catch (error) {
      this.logger.warn(
        `Statement ERP lifecycle lookup failed: phase=${phase} count=${orders.length} durationMs=${Date.now() - startedAt} errorType=${this.errorTypeName(error)}`,
      );
      throw new BadRequestException(
        phase === 'current'
          ? 'Chưa xác minh được trạng thái của tất cả mã đơn hiện tại trên hệ thống bán hàng. Vui lòng thử lại.'
          : 'Không tìm thấy hoặc chưa kiểm tra được mã đơn mới trên hệ thống bán hàng. Vui lòng kiểm tra mã và thử lại.',
      );
    }
  }

  private lifecycleSummary(statuses: SalesReportErpLifecycleStatus[]) {
    if (statuses.length === 0) return 'none';
    const counts = statuses.reduce<Record<string, number>>(
      (summary, status) => {
        summary[status] = (summary[status] || 0) + 1;
        return summary;
      },
      {},
    );
    return Object.keys(counts)
      .sort()
      .map((status) => `${status}:${counts[status]}`)
      .join(',');
  }

  private errorTypeName(error: unknown) {
    return error instanceof Error ? error.constructor.name : typeof error;
  }

  private sameInstant(left: unknown, right: unknown) {
    if (
      left === null ||
      left === undefined ||
      right === null ||
      right === undefined
    ) {
      return left === right;
    }
    const leftTime =
      left instanceof Date ? left.getTime() : new Date(String(left)).getTime();
    const rightTime =
      right instanceof Date
        ? right.getTime()
        : new Date(String(right)).getTime();
    return Number.isFinite(leftTime) && leftTime === rightTime;
  }

  private async runStatementOptimisticTransaction<T>(
    operation: () => Promise<T>,
  ): Promise<T> {
    try {
      return await operation();
    } catch (error) {
      const code = (error as { code?: string } | null)?.code;
      if (code === 'P2025' || code === 'P2034' || isPostgresDeadlock(error)) {
        throw new BadRequestException(
          'Dữ liệu giao dịch vừa thay đổi. Vui lòng tải lại và thử lại.',
        );
      }
      throw error;
    }
  }

  async listStatementOrderTransferRequests(
    user: any,
    input: ListMapVietinStatementOrderTransferRequestsDto,
  ) {
    await this.assertCanUseStatements(user);
    await this.expireStaleStatementOrderTransferRequests();
    const canReview = await this.canReviewStatementOrderTransferRequests(user);
    const filters = this.normalizeStatementTransferRequestFilters(input);
    const where = await this.buildStatementOrderTransferListWhere(
      user,
      filters,
      canReview,
    );
    const [rows, total] = await Promise.all([
      this.prisma.mapVietinStatementOrderTransferRequest.findMany({
        where,
        include: { transaction: true },
        orderBy: { createdAt: 'desc' },
        skip: filters.page * filters.limit,
        take: filters.limit,
      }),
      this.prisma.mapVietinStatementOrderTransferRequest.count({ where }),
    ]);
    const readAtById =
      filters.status === STATEMENT_ORDER_TRANSFER_NOTIFICATION_STATUS
        ? await this.notificationReadAtById(
            user,
            APP_NOTIFICATION_SOURCE_STATEMENT_ORDER_TRANSFER,
            rows.map((row) => row.id),
          )
        : new Map<string, Date>();
    this.logger.log(
      `Statement order transfer requests listed: user=${this.safeUserLabel(user)} status=${filters.status} canReview=${canReview} count=${rows.length} total=${total} unread=${rows.filter((row) => !readAtById.has(row.id)).length} page=${filters.page} limit=${filters.limit}`,
    );
    return {
      page: filters.page,
      limit: filters.limit,
      total,
      canReview,
      list: rows.map((row) =>
        this.toStatementOrderTransferRequestDto(row, readAtById.get(row.id)),
      ),
    };
  }

  async approveStatementOrderTransferRequest(user: any, requestId: string) {
    return this.reviewStatementOrderTransferRequest(user, requestId, true);
  }

  async rejectStatementOrderTransferRequest(
    user: any,
    requestId: string,
    input: ReviewMapVietinStatementOrderTransferRequestDto = {},
  ) {
    return this.reviewStatementOrderTransferRequest(user, requestId, false, {
      note: input.note,
    });
  }

  async listStatementOrderHistory(user: any, transactionId: string) {
    await this.assertCanUseStatements(user);
    const id = String(transactionId || '').trim();
    if (!id) throw new BadRequestException('transactionId không hợp lệ');
    const transaction = await this.prisma.mapVietinTransaction.findUnique({
      where: { id },
    });
    if (!transaction) throw new BadRequestException('Giao dịch không hợp lệ');
    await this.assertCanReadStatementStore(user, transaction.storeCode);
    const rows = await this.prisma.mapVietinTransactionOrderAudit.findMany({
      where: { transactionId: id },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    this.logger.log(
      `Statement order history fetched: user=${this.safeUserLabel(user)} transaction=${id} count=${rows.length}`,
    );
    return {
      transactionId: id,
      list: rows.map((row) => ({
        id: row.id,
        oldOrders: row.oldOrders || [],
        newOrders: row.newOrders || [],
        changedByUserId: row.changedByUserId,
        changedByEmail: row.changedByEmail,
        source: row.source,
        createdAt: row.createdAt,
      })),
    };
  }

  private scheduleNextMapHistorySync(delayOverrideMs?: number) {
    this.syncCoordinator.scheduleNextMapHistorySync(delayOverrideMs);
  }

  private async runScheduledMapHistorySync() {
    return this.syncCoordinator.runScheduledMapHistorySync();
  }

  private scheduleNextEfastSync() {
    this.syncCoordinator.scheduleNextEfastSync();
  }

  private async runScheduledEfastSync() {
    return this.syncCoordinator.runScheduledEfastSync();
  }

  private randomMapHistorySyncDelayMs() {
    return this.syncCoordinator.randomMapHistorySyncDelayMs();
  }

  private randomMapDeepSweepDelayMs() {
    return this.syncCoordinator.randomMapDeepSweepDelayMs();
  }

  private randomEfastFastSyncDelayMs() {
    return this.syncCoordinator.randomEfastFastSyncDelayMs();
  }

  private nextMapHistorySyncDelayMs(value = new Date(Date.now())) {
    return this.syncCoordinator.nextMapHistorySyncDelayMs(value);
  }

  private nextEfastSyncDelayMs(value = new Date(Date.now())) {
    return this.syncCoordinator.nextEfastSyncDelayMs(value);
  }

  private isWithinMapSyncWindow(value = new Date(Date.now())) {
    return this.syncCoordinator.isWithinMapSyncWindow(value);
  }

  private isWithinEfastFastSyncWindow(value = new Date(Date.now())) {
    return this.syncCoordinator.isWithinEfastFastSyncWindow(value);
  }

  private get mapHistoryDeepSweepDueAt() {
    return this.syncCoordinator.mapHistoryDeepSweepDueAt;
  }

  private set mapHistoryDeepSweepDueAt(value: number) {
    this.syncCoordinator.mapHistoryDeepSweepDueAt = value;
  }

  private isMapHistorySyncDisabled() {
    return process.env.MAP_VIETIN_SYNC_ENABLED === 'false';
  }

  async syncConfiguredStores(options: MapGlobalSyncOptions = {}) {
    return this.syncCoordinator.runConfiguredStores(options, (syncOptions) =>
      this.executeConfiguredStores(syncOptions),
    );
  }

  private async executeConfiguredStores(options: MapGlobalSyncOptions = {}) {
    if (this.isMapHistorySyncDisabled()) return;
    if (this.mapProviderBackoffUntil > Date.now()) {
      this.logger.debug(
        `MAP sync skipped by provider backoff retryAt=${new Date(this.mapProviderBackoffUntil).toISOString()}`,
      );
      return;
    }
    const inFastWindow = this.isWithinMapSyncWindow();
    if (this.syncCoordinator.lastSyncWindowOpen !== inFastWindow) {
      this.logger.log(
        inFastWindow
          ? 'MAP sync fast cadence active'
          : 'MAP sync night cadence active',
      );
    }
    this.syncCoordinator.lastSyncWindowOpen = inFastWindow;
    if (this.shouldUseGlobalSync()) {
      await this.syncGlobalTransactions(options);
    } else {
      await this.syncPerStoreTransactions();
    }
  }

  private async syncPerStoreTransactions() {
    const stores = await this.prisma.store.findMany({
      where: {
        mapVietinUsername: { not: null },
        mapVietinPasswordCipher: { not: null },
      },
    });
    for (const store of stores) {
      if (this.mapProviderBackoffUntil > Date.now()) {
        this.logger.debug(
          `Per-store MAP sync batch stopped by provider backoff retryAt=${new Date(this.mapProviderBackoffUntil).toISOString()}`,
        );
        break;
      }
      await this.syncStoreTransactions(store);
    }
  }

  async syncGlobalTransactions(options: MapGlobalSyncOptions = {}) {
    if (this.mapProviderBackoffUntil > Date.now()) {
      this.logger.debug(
        `Global MAP sync skipped by provider backoff retryAt=${new Date(this.mapProviderBackoffUntil).toISOString()}`,
      );
      return { created: 0, quarantined: 0 };
    }
    const now = new Date();
    const startedAt = Date.now();
    let mode = options.mode ?? 'manual';
    try {
      const username = this.globalUsername();
      const password = this.globalPassword();
      if (!username || !password) {
        throw new BadRequestException(
          'Global MAP credential is not configured',
        );
      }

      const today = this.formatMapDate(now);
      let session = await this.getGlobalSession(username, password);
      const storeAccountIndex = await this.loadStoreAccountIndex();
      let created = 0;
      let updated = 0;
      let unchanged = 0;
      let cacheHits = 0;
      let quarantined = 0;
      let page = 0;
      let pagesFetched = 0;
      const size = MAP_SYNC_PAGE_SIZE;
      const configuredMaxPages = this.globalSyncMaxPages();
      let maxPages = Math.max(
        1,
        Math.min(options.maxPages ?? configuredMaxPages, configuredMaxPages),
      );

      this.logger.debug(
        `Global MAP sync started mode=${mode} maxPages=${maxPages}`,
      );
      while (page < maxPages) {
        const input = {
          startDate: today,
          endDate: today,
          page,
          size,
        };
        let result: Awaited<
          ReturnType<typeof this.searchTransactionsWithSession>
        >;
        try {
          result = await this.searchTransactionsWithSession(
            GLOBAL_SYNC_STATE_CODE,
            session,
            input,
          );
        } catch (error) {
          if (!this.isProviderAuthError(error)) throw error;
          mode = 'session_recovery';
          maxPages = configuredMaxPages;
          this.logger.warn(
            `Global MAP session was rejected; refreshing token and enabling deep sweep page=${page} maxPages=${maxPages}`,
          );
          session = await this.getGlobalSession(username, password, true);
          result = await this.searchTransactionsWithSession(
            GLOBAL_SYNC_STATE_CODE,
            session,
            input,
          );
        }
        pagesFetched += 1;
        const persisted = await this.persistGlobalTransactions(
          result.list,
          storeAccountIndex,
        );
        created += persisted.created;
        updated += persisted.updated;
        unchanged += persisted.unchanged;
        cacheHits += persisted.cacheHits;
        quarantined += persisted.quarantined;

        const listLength = result.list.length;
        const total = result.total ?? 0;
        if (listLength === 0 || (page + 1) * size >= total) break;
        page += 1;
      }

      await this.prisma.mapVietinSyncState.upsert({
        where: { storeCode: GLOBAL_SYNC_STATE_CODE },
        create: {
          storeCode: GLOBAL_SYNC_STATE_CODE,
          lastSyncedAt: now,
          lastSuccessAt: now,
          lastError: null,
        },
        update: {
          lastSyncedAt: now,
          lastSuccessAt: now,
          lastError: null,
        },
      });
      const deepSweepCompleted = mode !== 'fast_page' || maxPages > 1;
      let nextDeepSweepInMs = Math.max(
        0,
        this.mapHistoryDeepSweepDueAt - Date.now(),
      );
      if (deepSweepCompleted) {
        nextDeepSweepInMs = this.randomMapDeepSweepDelayMs();
        this.mapHistoryDeepSweepDueAt = Date.now() + nextDeepSweepInMs;
      }
      this.clearMapProviderBackoff();
      if (created > 0 || updated > 0 || quarantined > 0 || deepSweepCompleted) {
        this.logger.log(
          `Global MAP sync succeeded mode=${mode} pagesFetched=${pagesFetched} created=${created} updated=${updated} unchanged=${unchanged} cacheHits=${cacheHits} quarantined=${quarantined} durationMs=${Date.now() - startedAt} nextDeepSweepInMs=${nextDeepSweepInMs}`,
        );
      } else if (unchanged > 0) {
        this.logger.debug(
          `Global MAP sync no-op mode=${mode} pagesFetched=${pagesFetched} unchanged=${unchanged} cacheHits=${cacheHits} durationMs=${Date.now() - startedAt}`,
        );
      }
      return { created, quarantined };
    } catch (error) {
      const message = this.safeError(error).slice(0, 500);
      const providerStatus = this.providerHttpStatus(error);
      if (providerStatus === 429 || providerStatus === 403) {
        this.registerMapProviderBackoff(
          providerStatus,
          error instanceof BankProviderHttpException
            ? error.retryAfterMs
            : undefined,
        );
      }
      this.logger.warn(
        `Global MAP sync failed mode=${mode} providerStatus=${providerStatus ?? 'unknown'} durationMs=${Date.now() - startedAt}: ${message}`,
      );
      await this.prisma.mapVietinSyncState.upsert({
        where: { storeCode: GLOBAL_SYNC_STATE_CODE },
        create: {
          storeCode: GLOBAL_SYNC_STATE_CODE,
          lastSyncedAt: now,
          lastError: message,
        },
        update: {
          lastSyncedAt: now,
          lastError: message,
        },
      });
      return { created: 0, quarantined: 0 };
    }
  }

  async syncEfastTransactions() {
    return this.syncCoordinator.runEfastTransactions(() =>
      this.executeEfastTransactions(),
    );
  }

  private async executeEfastTransactions() {
    const now = new Date();
    const startedAt = Date.now();
    try {
      const username = this.efastUsername();
      const password = this.efastPassword();
      const accounts = this.efastBankAccounts();
      if (!username || !password || accounts.length === 0) {
        throw new BadRequestException(
          'VietinBank eFAST credential is not configured',
        );
      }

      const today = this.formatMapDate(now);
      let session = await this.getEfastSession(username, password);
      const storeAccountIndex = await this.loadStoreAccountIndex();
      const accountRemapped =
        await this.reassignUnassignedEfastTransactions(storeAccountIndex);
      const pageSize = this.efastPageSize();
      const maxPages = this.efastSyncMaxPages();
      let fetched = 0;
      let creditRows = 0;
      let created = 0;
      let updated = 0;
      let unchanged = 0;
      let cacheHits = 0;
      let quarantined = 0;
      let sourceAccountMapped = 0;

      this.logger.log(
        `VietinBank eFAST sync started: accounts=${accounts
          .map((account) => this.maskAccount(account))
          .join(',')} pageSize=${pageSize} maxPages=${maxPages}`,
      );

      for (const accountNo of accounts) {
        let page = 0;
        while (page < maxPages) {
          let result: EfastHistoryResponse;
          try {
            result = await this.searchEfastHistory(session, {
              accountNo,
              fromDate: today,
              toDate: today,
              page,
              pageSize,
            });
          } catch (error) {
            if (!this.isProviderAuthError(error)) throw error;
            this.logger.warn(
              `VietinBank eFAST session was rejected; refreshing session and retrying account=${this.maskAccount(accountNo)} page=${page}`,
            );
            session = await this.getEfastSession(username, password, true);
            result = await this.searchEfastHistory(session, {
              accountNo,
              fromDate: today,
              toDate: today,
              page,
              pageSize,
            });
          }

          const rows = result.transactions || [];
          fetched += rows.length;
          const mappedRows = rows
            .filter((row): row is MapTransactionRow => {
              return Boolean(
                row &&
                typeof row === 'object' &&
                this.isEfastCreditRow(row as MapTransactionRow),
              );
            })
            .map((row) => this.toEfastMapTransactionRow(accountNo, row));
          creditRows += mappedRows.length;
          const persisted = await this.persistGlobalTransactions(
            mappedRows,
            storeAccountIndex,
          );
          created += persisted.created;
          updated += persisted.updated;
          unchanged += persisted.unchanged;
          cacheHits += persisted.cacheHits;
          quarantined += persisted.quarantined;
          sourceAccountMapped += persisted.sourceAccountMapped;

          if (!this.hasNextEfastPage(result, page, rows.length, pageSize)) {
            break;
          }
          page += 1;
        }
      }

      await this.prisma.mapVietinSyncState.upsert({
        where: { storeCode: EFAST_SYNC_STATE_CODE },
        create: {
          storeCode: EFAST_SYNC_STATE_CODE,
          lastSyncedAt: now,
          lastSuccessAt: now,
          lastError: null,
        },
        update: {
          lastSyncedAt: now,
          lastSuccessAt: now,
          lastError: null,
        },
      });
      this.logger.log(
        `VietinBank eFAST sync finished: fetched=${fetched} creditRows=${creditRows} created=${created} updated=${updated} unchanged=${unchanged} cacheHits=${cacheHits} sourceAccountMapped=${sourceAccountMapped} accountRemapped=${accountRemapped} quarantined=${quarantined} durationMs=${Date.now() - startedAt}`,
      );
      return { created, quarantined, fetched, creditRows };
    } catch (error) {
      const message = this.safeError(error).slice(0, 500);
      this.logger.warn(
        `VietinBank eFAST sync failed: ${message} durationMs=${Date.now() - startedAt}`,
      );
      await this.prisma.mapVietinSyncState.upsert({
        where: { storeCode: EFAST_SYNC_STATE_CODE },
        create: {
          storeCode: EFAST_SYNC_STATE_CODE,
          lastSyncedAt: now,
          lastError: message,
        },
        update: {
          lastSyncedAt: now,
          lastError: message,
        },
      });
      return { created: 0, quarantined: 0, fetched: 0, creditRows: 0 };
    }
  }

  private async getEfastSession(
    username: string,
    password: string,
    forceRefresh = false,
  ) {
    const configuredCifno = this.efastCifno();
    return this.providerRuntime.getEfastSession(
      username,
      configuredCifno,
      this.efastSessionTtlSeconds(),
      forceRefresh,
      () => this.loginEfast(username, password, configuredCifno),
    );
  }

  private async loginEfast(
    username: string,
    password: string,
    configuredCifno: string,
  ): Promise<EfastSession> {
    const response = await this.postJson<EfastLoginResponse>(
      this.efastApiUrl('account/login'),
      {
        requestId: this.newEfastRequestId(),
        language: 'vi',
        version: '1.0',
        username: this.encryptEfastText(username),
        channel: 'eFAST',
        newCore: 'Y',
        password: this.encryptEfastText(password),
        cifno: configuredCifno ? this.encryptEfastText(configuredCifno) : false,
        deviceID: this.efastDeviceId(username),
        abc: '123',
      },
      this.efastHeaders(),
      'VietinBank eFAST',
    );

    if (!this.isEfastSuccess(response.status)) {
      const code = String(response.status?.code || '');
      if (code === EFAST_SHARED_USER_CODE) {
        throw new BadGatewayException(
          'VietinBank eFAST account requires VIETIN_EFAST_CIFNO because it has multiple enterprises',
        );
      }
      throw new BadGatewayException(
        `VietinBank eFAST login failed: ${this.safeProviderMessage(response)}`,
      );
    }

    const cifno =
      configuredCifno ||
      this.firstNonEmptyText(
        response.corpUser?.cifno,
        response.corpUser?.enterpriseid,
        response.corpUser?.enterpriseId,
      );
    const sessionId = this.firstNonEmptyText(response.sessionId);
    if (!cifno || !sessionId) {
      throw new BadGatewayException(
        'VietinBank eFAST login response is missing cifno or sessionId',
      );
    }
    this.logger.log(
      `VietinBank eFAST login succeeded: cifno=${this.maskAccount(cifno)} sessionIdLength=${sessionId.length}`,
    );
    return { username, cifno, sessionId };
  }

  private async searchEfastHistory(
    session: EfastSession,
    input: {
      accountNo: string;
      fromDate: string;
      toDate: string;
      page: number;
      pageSize: number;
    },
  ) {
    const response = await this.postJson<EfastHistoryResponse>(
      this.efastApiUrl('account/history'),
      {
        requestId: this.newEfastRequestId(),
        language: 'vi',
        version: '1.0',
        username: this.encryptEfastText(session.username),
        channel: 'eFAST',
        newCore: '',
        cifno: this.encryptEfastText(session.cifno),
        accountNo: input.accountNo,
        accountType: 'D',
        currency: 'VND',
        fromDate: input.fromDate,
        toDate: input.toDate,
        pageSize: input.pageSize,
        pageIndex: input.page,
        lastRecord: '',
        cardNo: '',
        fromAmount: '',
        toAmount: '',
        searchKey: '',
        startTime: '00:00:00',
        endTime: '23:59:59',
        queryType: 'NORMAL',
        dorcC: 'Credit',
        dorcD: '',
        sessionId: session.sessionId,
        screenResolution: '',
      },
      this.efastHeaders(),
      'VietinBank eFAST',
    );

    if (!this.isEfastSuccess(response.status)) {
      const code = String(response.status?.code || '');
      if (code === EFAST_INVALID_SESSION_CODE) {
        throw new UnauthorizedException('VietinBank eFAST session is invalid');
      }
      throw new BadGatewayException(
        `VietinBank eFAST history failed: ${this.safeProviderMessage(response)}`,
      );
    }
    return response;
  }

  async syncStoreTransactions(store: {
    storeId: string;
    mapVietinUsername?: string | null;
    mapVietinPasswordCipher?: string | null;
  }) {
    if (this.mapProviderBackoffUntil > Date.now()) {
      this.logger.debug(
        `MAP store sync skipped by provider backoff store=${store.storeId} retryAt=${new Date(this.mapProviderBackoffUntil).toISOString()}`,
      );
      return 0;
    }
    const now = new Date();
    try {
      const today = this.formatMapDate(now);
      const result = await this.searchTransactionsForStore(store, {
        startDate: today,
        endDate: today,
        page: 0,
        size: MAP_SYNC_PAGE_SIZE,
      });
      const persistStats: MapPersistStats = {
        updated: 0,
        unchanged: 0,
        cacheHits: 0,
      };
      const created = await this.persistTransactions(
        store.storeId,
        result.list,
        persistStats,
      );
      await this.prisma.mapVietinSyncState.upsert({
        where: { storeCode: store.storeId },
        create: {
          storeCode: store.storeId,
          lastSyncedAt: now,
          lastSuccessAt: now,
          lastError: null,
        },
        update: {
          lastSyncedAt: now,
          lastSuccessAt: now,
          lastError: null,
        },
      });
      if (created > 0 || persistStats.updated > 0) {
        this.logger.log(
          `MAP sync persisted store=${store.storeId} created=${created} updated=${persistStats.updated} unchanged=${persistStats.unchanged} cacheHits=${persistStats.cacheHits}`,
        );
      } else if (persistStats.unchanged > 0) {
        this.logger.debug(
          `MAP sync no-op store=${store.storeId} unchanged=${persistStats.unchanged} cacheHits=${persistStats.cacheHits}`,
        );
      }
      return created;
    } catch (error) {
      const message = this.safeError(error).slice(0, 500);
      const providerStatus = this.providerHttpStatus(error);
      if (providerStatus === 429 || providerStatus === 403) {
        this.registerMapProviderBackoff(
          providerStatus,
          error instanceof BankProviderHttpException
            ? error.retryAfterMs
            : undefined,
        );
      }
      this.logger.warn(
        `MAP sync failed for ${store.storeId} providerStatus=${providerStatus ?? 'unknown'}: ${message}`,
      );
      await this.prisma.mapVietinSyncState.upsert({
        where: { storeCode: store.storeId },
        create: {
          storeCode: store.storeId,
          lastSyncedAt: now,
          lastError: message,
        },
        update: {
          lastSyncedAt: now,
          lastError: message,
        },
      });
      return 0;
    }
  }

  async searchTransactionsForStoreCode(
    storeCode: string,
    input: SearchMapVietinTransactionsDto,
  ) {
    const store = await this.prisma.store.findUnique({
      where: { storeId: storeCode },
    });
    if (!store) throw new BadRequestException('Showroom không hợp lệ');
    return this.searchTransactionsForStore(store, input);
  }

  private async searchTransactionsForStore(
    store: {
      storeId: string;
      mapVietinUsername?: string | null;
      mapVietinPasswordCipher?: string | null;
    },
    input: SearchMapVietinTransactionsDto,
  ) {
    if (!store.mapVietinUsername || !store.mapVietinPasswordCipher) {
      throw new BadRequestException(
        'Showroom chưa cấu hình tài khoản VietinBank MAP',
      );
    }

    const password = this.decryptMapPassword(store.mapVietinPasswordCipher);
    const session = await this.login(
      store.mapVietinUsername,
      password,
      store.storeId,
    );
    return this.searchTransactionsWithSession(store.storeId, session, input);
  }

  private async searchTransactionsWithSession(
    storeId: string,
    session: MapSession,
    input: SearchMapVietinTransactionsDto,
  ) {
    const request = this.buildSearchRequest(input);
    const page = input.page ?? 0;
    const size = input.size ?? 20;
    const response = await this.postJson<MapSearchResponse>(
      `${this.transactionBaseUrl()}/ma/payment-transaction/search?page=${page}&size=${size}&sort=txnDate,desc`,
      request,
      {
        Authorization: `Bearer ${session.accessToken}`,
        ClientId: this.clientId(),
        merchantId: session.merchantId,
        'x-lang': 'vi',
      },
    );

    return {
      storeId,
      pageIndex: response.data?.pageIndex ?? page,
      pageSize: response.data?.pageSize ?? size,
      total: response.data?.total ?? 0,
      list: response.data?.list ?? [],
    };
  }

  private async getGlobalSession(
    username: string,
    password: string,
    forceRefresh = false,
  ) {
    return this.providerRuntime.getGlobalSession(
      username,
      this.globalSessionTtlSeconds(),
      forceRefresh,
      () => this.login(username, password, GLOBAL_SYNC_STATE_CODE),
    );
  }

  private async buildStatementQuery(
    user: any,
    input: ListMapVietinStatementsDto,
    options: { requireFilter: boolean },
  ) {
    await this.assertCanUseStatements(user);
    const filters = (() => {
      try {
        return this.normalizeStatementFilters(input);
      } catch (error) {
        this.logger.warn(
          `Statement search validation failed: user=${this.safeUserLabel(user)} error=${this.safeError(error).slice(0, 180)}`,
        );
        throw error;
      }
    })();
    if (options.requireFilter && !filters.hasEffectiveFilter) {
      this.logger.warn(
        `Statement search rejected without filter: user=${this.safeUserLabel(user)}`,
      );
      throw new BadRequestException('Vui lòng chọn bộ lọc trước khi tìm kiếm');
    }
    const scopeWhere = filters.globalLookup
      ? {}
      : await this.buildStatementScopeWhere(user, filters);
    const filterWhere = this.buildStatementFilterWhere(filters);
    const incomeTypeWhere = await this.buildStatementIncomeTypeWhere(user);
    return {
      where: this.andWhere(scopeWhere, filterWhere, incomeTypeWhere),
      page: input.page ?? 0,
      limit: input.limit ?? 20,
      filterSummary: filters.summary,
      verifiedOrderLookup: this.statementOrderLookupFromFilters(filters),
    };
  }

  private async buildSelectedStatementWhere(
    user: any,
    input: ExportMapVietinStatementsDto,
    ids: string[],
  ) {
    const filters = this.normalizeStatementFilters(input);
    const scopeWhere = filters.globalLookup
      ? {}
      : await this.buildStatementScopeWhere(user, filters);
    const filterWhere = filters.hasEffectiveFilter
      ? this.buildStatementFilterWhere(filters)
      : {};
    const incomeTypeWhere = await this.buildStatementIncomeTypeWhere(user);
    return this.andWhere(scopeWhere, filterWhere, incomeTypeWhere, {
      id: { in: ids },
    });
  }

  private async buildStatementIncomeTypeWhere(user: any) {
    const canReadPartnerInternal = await this.userBelongsToStatementAccessCodes(
      user,
      [FIN_ACC_DEPARTMENT_CODE],
    );
    this.logger.debug(
      `Statement income type visibility resolved: user=${this.safeUserLabel(user)} partnerInternal=${canReadPartnerInternal ? 'allowed' : 'blocked'} reason=fin_acc_membership`,
    );
    return canReadPartnerInternal
      ? {}
      : { incomeType: MAP_VIETIN_INCOME_TYPE.SALES };
  }

  private normalizeStatementFilters(input: ListMapVietinStatementsDto) {
    const storeIds = this.parseStoreCodes(input.storeIds);
    const requestedAllStores = this.parseBoolean(input.allStores);
    if (requestedAllStores && storeIds.length > 0) {
      throw new BadRequestException('Chỉ chọn tất cả hoặc danh sách showroom');
    }

    const orderText = this.cleanText(input.order);
    const order = orderText ? this.normalizeSingleOrderCode(orderText) : null;
    const statementNumber = this.cleanText(input.statementNumber);
    const amount = this.normalizeStatementAmount(input.amount);
    const content = this.cleanText(input.content);
    const orderStatus = input.orderStatus || STATEMENT_ORDER_STATUS_ALL;
    const dateRange = this.resolveStoredTransactionDateRange(input);
    const globalLookup =
      Boolean(statementNumber) ||
      Boolean(order) ||
      amount !== null ||
      Boolean(content);
    const primaryCount = [
      requestedAllStores || storeIds.length > 0,
      Boolean(statementNumber),
      Boolean(order),
      amount !== null,
      Boolean(content),
    ].filter(Boolean).length;
    if (primaryCount > 1) {
      throw new BadRequestException(
        'Chỉ được dùng độc lập một trong các bộ lọc chính',
      );
    }
    const hasEffectiveFilter =
      primaryCount > 0 ||
      Boolean(dateRange) ||
      orderStatus === STATEMENT_ORDER_STATUS_HAS_ORDER ||
      orderStatus === STATEMENT_ORDER_STATUS_MISSING_ORDER ||
      orderStatus === STATEMENT_ORDER_STATUS_OFFSET_PENDING ||
      orderStatus === STATEMENT_ORDER_STATUS_OFFSET_CONFIRMED ||
      orderStatus === STATEMENT_ORDER_STATUS_UNFOLLOWED;

    return {
      requestedAllStores,
      storeIds,
      statementNumber,
      order,
      amount,
      content,
      globalLookup,
      orderStatus,
      dateRange,
      hasEffectiveFilter,
      summary: [
        globalLookup ? 'globalLookup' : '',
        requestedAllStores ? 'allStores' : '',
        storeIds.length ? `stores:${storeIds.length}` : '',
        statementNumber ? 'statementNumber' : '',
        order ? 'order' : '',
        amount !== null ? 'amount' : '',
        content ? 'content' : '',
        orderStatus !== STATEMENT_ORDER_STATUS_ALL ? orderStatus : '',
        dateRange ? 'dateRange' : '',
      ]
        .filter(Boolean)
        .join('|'),
    };
  }

  private async buildStatementScopeWhere(
    user: any,
    filters: { requestedAllStores?: boolean; storeIds?: string[] },
  ): Promise<Prisma.MapVietinTransactionWhereInput> {
    const requestedAllStores = filters.requestedAllStores === true;
    const storeIds = filters.storeIds || [];
    if (await this.hasNationalStatementScope(user)) {
      if (requestedAllStores || storeIds.length === 0) return {};
      return { storeCode: { in: storeIds } };
    }
    const includeUnassigned =
      storeIds.length === 0 &&
      !requestedAllStores &&
      (await this.canReadUnassignedStatementTransactions(user));

    const allowedStores = await this.resolveUserStores(user);
    const allowedStoreCodes = allowedStores.map((store) => store.storeId);
    if (requestedAllStores) {
      throw new ForbiddenException('Không có quyền xem tất cả showroom');
    }
    const selectedStoreCodes =
      storeIds.length > 0 ? storeIds : allowedStoreCodes;
    const invalidStore = selectedStoreCodes.find(
      (storeCode) => !allowedStoreCodes.includes(storeCode),
    );
    if (invalidStore) {
      throw new ForbiddenException('Chỉ được xem giao dịch showroom được gán');
    }
    const storeWhere = { storeCode: this.storeCodeWhere(selectedStoreCodes) };
    return includeUnassigned
      ? { OR: [storeWhere, { storeCode: null }] }
      : storeWhere;
  }

  private statementScopeWhereForTransferRequests(
    scopeWhere: Prisma.MapVietinTransactionWhereInput,
  ): Prisma.MapVietinStatementOrderTransferRequestWhereInput {
    const storeCode = (scopeWhere as any).storeCode;
    if (!storeCode) return {};
    if (typeof storeCode === 'string') return { storeCode };
    const storeCodes = Array.isArray(storeCode.in) ? storeCode.in : null;
    return storeCodes ? { storeCode: { in: storeCodes } } : { storeCode };
  }

  private async buildStatementOrderTransferListWhere(
    user: any,
    filters: {
      requestedAllStores: boolean;
      storeIds: string[];
      status: string;
    },
    canReview: boolean,
  ): Promise<Prisma.MapVietinStatementOrderTransferRequestWhereInput> {
    const notificationMode =
      filters.status === STATEMENT_ORDER_TRANSFER_NOTIFICATION_STATUS;
    const statusWhere: Prisma.MapVietinStatementOrderTransferRequestWhereInput =
      notificationMode
        ? canReview
          ? { status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING }
          : {
              status: {
                in: [
                  STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
                  STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_REJECTED,
                ],
              },
            }
        : { status: filters.status };

    if (canReview) {
      const scopeWhere = await this.buildStatementScopeWhere(user, {
        requestedAllStores: filters.requestedAllStores,
        storeIds: filters.storeIds,
      });
      if (notificationMode) {
        return {
          OR: [
            {
              status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
              ...this.statementScopeWhereForTransferRequests(scopeWhere),
            },
            {
              status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_REJECTED,
              requestedByUserId: String(user?.id || '__missing_user__'),
            },
          ],
        };
      }
      return {
        ...statusWhere,
        ...this.statementScopeWhereForTransferRequests(scopeWhere),
      };
    }

    return {
      ...statusWhere,
      requestedByUserId: String(user?.id || '__missing_user__'),
    };
  }

  private storeCodeWhere(storeCodes: string[]) {
    return storeCodes.length === 1 ? storeCodes[0] : { in: storeCodes };
  }

  private statementOrderLookupFromFilters(filters: {
    statementNumber?: string | null;
    order?: string | null;
    amount?: number | null;
    content?: string | null;
  }) {
    if (filters.statementNumber) {
      return { statementNumber: filters.statementNumber };
    }
    if (filters.order) {
      return { order: filters.order };
    }
    if (filters.amount !== null && filters.amount !== undefined) {
      return { amount: filters.amount };
    }
    if (filters.content) {
      return { content: filters.content };
    }
    return null;
  }

  private buildStatementFilterWhere(filters: {
    statementNumber?: string | null;
    order?: string | null;
    amount?: number | null;
    content?: string;
    orderStatus?: string;
    dateRange?: { start: Date; end: Date } | null;
  }): Prisma.MapVietinTransactionWhereInput {
    const parts: Prisma.MapVietinTransactionWhereInput[] = [];
    if (filters.statementNumber) {
      parts.push({
        OR: [
          { transactionNumber: filters.statementNumber },
          {
            rawData: {
              path: ['txnReference'],
              equals: filters.statementNumber,
            },
          },
          {
            rawData: {
              path: ['trxId'],
              equals: filters.statementNumber,
            },
          },
          {
            rawData: {
              path: ['trxRefNo'],
              equals: filters.statementNumber,
            },
          },
          {
            rawData: {
              path: ['providerIdentifiers', 'mapTransactionNumber'],
              equals: filters.statementNumber,
            },
          },
          {
            rawData: {
              path: ['providerIdentifiers', 'efastTrxId'],
              equals: filters.statementNumber,
            },
          },
          {
            rawData: {
              path: ['providerIdentifiers', 'efastTrxRefNo'],
              equals: filters.statementNumber,
            },
          },
        ],
      });
    }
    if (filters.order) parts.push({ orders: { has: filters.order } });
    if (filters.amount !== null && filters.amount !== undefined) {
      parts.push({ amount: filters.amount });
    }
    if (filters.content) {
      parts.push({
        content: {
          contains: filters.content,
          mode: Prisma.QueryMode.insensitive,
        },
      });
    }
    if (
      filters.orderStatus === STATEMENT_ORDER_STATUS_HAS_ORDER ||
      filters.orderStatus === STATEMENT_ORDER_STATUS_MISSING_ORDER ||
      filters.orderStatus === STATEMENT_ORDER_STATUS_OFFSET_PENDING ||
      filters.orderStatus === STATEMENT_ORDER_STATUS_OFFSET_CONFIRMED
    ) {
      parts.push({ orderTrackingStatus: ORDER_TRACKING_STATUS_FOLLOWING });
    }
    if (filters.orderStatus === STATEMENT_ORDER_STATUS_HAS_ORDER) {
      parts.push({ orders: { isEmpty: false } });
    } else if (filters.orderStatus === STATEMENT_ORDER_STATUS_MISSING_ORDER) {
      parts.push({ orders: { isEmpty: true } });
    } else if (filters.orderStatus === STATEMENT_ORDER_STATUS_OFFSET_PENDING) {
      parts.push({
        orderTransferRequests: {
          some: { status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING },
        },
      });
    } else if (
      filters.orderStatus === STATEMENT_ORDER_STATUS_OFFSET_CONFIRMED
    ) {
      parts.push({ orderSource: ORDER_SOURCE_OFFSET });
    } else if (filters.orderStatus === STATEMENT_ORDER_STATUS_UNFOLLOWED) {
      parts.push({ orderTrackingStatus: ORDER_TRACKING_STATUS_UNFOLLOWED });
    }
    if (filters.dateRange) {
      parts.push({
        OR: [
          {
            paidAt: {
              gte: filters.dateRange.start,
              lt: filters.dateRange.end,
            },
          },
          {
            paidAt: null,
            firstSeenAt: {
              gte: filters.dateRange.start,
              lt: filters.dateRange.end,
            },
          },
        ],
      });
    }
    return this.andWhere(...parts);
  }

  private andWhere(
    ...parts: Prisma.MapVietinTransactionWhereInput[]
  ): Prisma.MapVietinTransactionWhereInput {
    const compact = parts.filter((part) => Object.keys(part).length > 0);
    if (compact.length === 0) return {};
    if (compact.length === 1) return compact[0];
    return { AND: compact };
  }

  private async assertCanReadStatementStore(
    user: any,
    storeCode?: string | null,
  ) {
    if (!(await this.canReadStatementStore(user, storeCode))) {
      throw new ForbiddenException('Chỉ được xem giao dịch showroom được gán');
    }
  }

  private async canReadStatementStore(user: any, storeCode?: string | null) {
    return this.statementPolicyRuntime.canReadStatementStore(user, storeCode);
  }

  private async canReadUnassignedStatementTransactions(user: any) {
    return this.statementPolicyRuntime.canReadUnassignedStatementTransactions(
      user,
    );
  }

  private async resolveStatementActionScope(user: any) {
    return this.statementPolicyRuntime.resolveStatementActionScope(user);
  }

  private statementActionScopeWhere(scope: {
    allStores: boolean;
    storeCodes: string[];
    includeUnassigned: boolean;
  }): Prisma.MapVietinTransactionWhereInput {
    return this.statementPolicyRuntime.statementActionScopeWhere(scope);
  }

  private async resolveUserStore(user: any) {
    const stores = await this.resolveUserStores(user);
    return stores[0];
  }

  private async resolveUserStores(user: any) {
    const storesByCode = new Map<string, any>();
    const pushStore = (store: any) => {
      const storeCode = String(store?.storeId || '')
        .trim()
        .toUpperCase();
      if (storeCode && !storesByCode.has(storeCode)) {
        storesByCode.set(storeCode, store);
      }
    };

    if (user?.id) {
      const savedUser = await this.prisma.user.findUnique({
        where: { id: user.id },
        include: {
          store: true,
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
      pushStore(savedUser?.store);
      for (const assignment of savedUser?.organizationAssignments ?? []) {
        for (const store of storesForOrganizationNodeTree(
          assignment.organizationNode,
        )) {
          pushStore(store);
        }
      }
    }

    if (storesByCode.size === 0 && user?.storeId) {
      const store = await this.prisma.store.findUnique({
        where: { id: user.storeId },
      });
      pushStore(store);
    }

    const stores = Array.from(storesByCode.values());
    if (stores.length === 0) {
      throw new ForbiddenException('Tài khoản chưa được gán showroom');
    }
    return stores;
  }

  private async hasNationalStatementScope(user: any) {
    return this.policyService.canAccessPolicy(
      user,
      ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE,
    );
  }

  private async hasStoredTransactionAllScope(user: any) {
    return (
      (await this.policyService.canAccessPolicy(
        user,
        ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE,
      )) ||
      (await this.policyService.canAccessPolicy(
        user,
        ADMIN_POLICY_CODES.PAYMENT_MONITOR_ALL_SCOPE,
      ))
    );
  }

  private async canUseStatements(user: any) {
    return this.featureService.canAccessFeature(
      user,
      FEATURE_KEYS.BANK_STATEMENTS,
    );
  }

  private async assertCanUseStatements(user: any) {
    return this.statementPolicyRuntime.assertCanUseStatements(user);
  }

  private assertStatementOrderEditAllowed(
    row: { orders?: string[] | null; orderSource?: string | null },
    canEditProtectedOrders: boolean,
  ) {
    const existingOrders = this.normalizeOrderCodes(row.orders || []);
    if (existingOrders.length === 0 || canEditProtectedOrders) return;
    throw new ForbiddenException(ORDER_EDIT_FORBIDDEN_MESSAGE);
  }

  private normalizeStatementOrderUpdateLookup(
    input: UpdateMapVietinStatementOrdersDto,
  ) {
    const statementNumber = this.cleanText(input.statementNumber);
    const orderText = this.cleanText(input.order);
    const order = orderText ? this.normalizeSingleOrderCode(orderText) : null;
    const amount = this.normalizeStatementAmount(input.amount);
    const content = this.cleanText(input.content);
    return {
      statementNumber,
      order,
      amount,
      content,
      hasExactField:
        Boolean(statementNumber) ||
        Boolean(order) ||
        amount !== null ||
        Boolean(content),
    };
  }

  private matchesStatementOrderUpdateLookup(
    row: {
      transactionNumber?: string | null;
      rawData?: Prisma.JsonValue | null;
      amount?: number | null;
      orders?: string[] | null;
      content?: string | null;
    },
    lookup: {
      statementNumber?: string | null;
      order?: string | null;
      amount?: number | null;
      content?: string | null;
    } | null,
  ) {
    if (!lookup) return false;
    if (lookup.statementNumber) {
      const statementNumber = String(lookup.statementNumber).trim();
      if (
        row.transactionNumber === statementNumber ||
        this.resolveStoredTransactionReference(row) === statementNumber
      ) {
        return true;
      }
    }
    if (lookup.order) {
      const order = String(lookup.order).trim();
      const existingOrders = this.normalizeOrderCodes(row.orders || []);
      if (existingOrders.includes(order)) return true;
    }
    if (lookup.amount !== null && lookup.amount !== undefined) {
      if (Number(row.amount) === Number(lookup.amount)) return true;
    }
    if (lookup.content) {
      const expectedContent = this.normalizeMatchText(lookup.content);
      const rowContent = this.normalizeMatchText(row.content || '');
      if (expectedContent && rowContent === expectedContent) return true;
    }
    return false;
  }

  private async canEditProtectedStatementOrders(user: any): Promise<boolean> {
    return this.statementPolicyRuntime.canEditProtectedStatementOrders(user);
  }

  private async canEditStatementIncomeType(user: any): Promise<boolean> {
    return this.statementPolicyRuntime.canEditStatementIncomeType(user);
  }

  private async canReviewStatementOrderTransferRequests(
    user: any,
  ): Promise<boolean> {
    return this.statementPolicyRuntime.canReviewStatementOrderTransferRequests(
      user,
    );
  }

  private async canManageStatementOrderTracking(user: any): Promise<boolean> {
    return this.statementPolicyRuntime.canManageStatementOrderTracking(user);
  }

  private async assertCanReviewStatementOrderTransferRequests(user: any) {
    return this.statementPolicyRuntime.assertCanReviewStatementOrderTransferRequests(
      user,
    );
  }

  private async reviewStatementOrderTransferRequest(
    user: any,
    requestId: string,
    approved: boolean,
    options: { note?: string } = {},
  ) {
    await this.assertCanReviewStatementOrderTransferRequests(user);
    const id = String(requestId || '').trim();
    if (!id) throw new BadRequestException('Yêu cầu không hợp lệ');
    const reviewNote = approved ? null : this.normalizeReviewNote(options.note);
    const request =
      await this.prisma.mapVietinStatementOrderTransferRequest.findUnique({
        where: { id },
        include: { transaction: true },
      });
    if (!request) throw new BadRequestException('Yêu cầu không hợp lệ');
    if (request.status !== STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING) {
      throw new BadRequestException('Yêu cầu đã được xử lý');
    }
    await this.assertCanReadStatementStore(user, request.storeCode);
    const reviewedAt = new Date();
    const nextStatus = approved
      ? STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_APPROVED
      : STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_REJECTED;

    let updatedTransaction: any = null;
    if (approved) {
      updatedTransaction = await this.prisma.mapVietinTransaction.update({
        where: { id: request.transactionId },
        data: {
          orders: request.requestedOrders,
          orderSource: ORDER_SOURCE_OFFSET,
          orderUpdatedAt: reviewedAt,
          orderUpdatedByUserId: user.id || null,
          orderUpdatedByEmail: this.safeUserEmail(user),
        },
      });
      await this.prisma.mapVietinTransactionOrderAudit.create({
        data: {
          transactionId: request.transactionId,
          storeCode: request.storeCode,
          oldOrders: request.oldOrders,
          newOrders: request.requestedOrders,
          changedByUserId: user.id || null,
          changedByEmail: this.safeUserEmail(user),
          source: ORDER_SOURCE_OFFSET,
        },
      });
    }

    const updatedRequest =
      await this.prisma.mapVietinStatementOrderTransferRequest.update({
        where: { id },
        data: {
          status: nextStatus,
          reviewedByUserId: user.id || null,
          reviewedByEmail: this.safeUserEmail(user),
          reviewNote,
          reviewedAt,
        },
        include: { transaction: true },
      });
    await this.publishStatementOrderTransferRequestEvent({
      id: updatedRequest.id,
      transactionId: updatedRequest.transactionId,
      storeCode: updatedRequest.storeCode,
      status: updatedRequest.status,
      createdAt: updatedRequest.createdAt,
      recipientUserId: request.requestedByUserId,
    });
    this.logger.log(
      `Statement order transfer ${approved ? 'approved' : 'rejected'}: user=${this.safeUserLabel(user)} request=${id} transaction=${request.transactionId} store=${request.storeCode} hasNote=${Boolean(reviewNote)}`,
    );
    return {
      request: this.toStatementOrderTransferRequestDto(updatedRequest),
      transaction: updatedTransaction
        ? this.toStoredTransactionDto(updatedTransaction, {
            canEditProtectedOrders: true,
          })
        : null,
    };
  }

  private async userMatchesStatementAccessCodes(
    user: any,
    allowedCodes: string[],
  ): Promise<boolean> {
    if (String(user?.role || '').toUpperCase() === 'SUPER_ADMIN') return true;
    return this.userBelongsToStatementAccessCodes(user, allowedCodes);
  }

  private async userBelongsToStatementAccessCodes(
    user: any,
    allowedCodes: string[],
  ): Promise<boolean> {
    const allowed = new Set(
      allowedCodes.map((code) => this.normalizeStatementAccessCode(code)),
    );
    let departmentCode = this.normalizeStatementAccessCode(
      user?.departmentCode,
    );
    let organizationNodeId = String(user?.organizationNodeId || '').trim();

    if ((!departmentCode || !organizationNodeId) && user?.id) {
      const userModel = (this.prisma as any).user;
      const stored = userModel?.findUnique
        ? await userModel.findUnique({
            where: { id: user.id },
            select: { departmentCode: true, organizationNodeId: true },
          })
        : null;
      departmentCode ||= this.normalizeStatementAccessCode(
        stored?.departmentCode,
      );
      organizationNodeId ||= String(stored?.organizationNodeId || '').trim();
    }

    if (allowed.has(departmentCode)) return true;
    if (!organizationNodeId) return false;
    return this.organizationNodeMatchesStatementAccessCodes(
      organizationNodeId,
      allowed,
    );
  }

  private async organizationNodeMatchesStatementAccessCodes(
    nodeId: string,
    allowedCodes: Set<string>,
  ) {
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany) return false;
    const nodes: Array<{
      id: string;
      parentId: string | null;
      code: string | null;
      businessCode: string | null;
    }> = await organizationNode.findMany({
      select: { id: true, parentId: true, code: true, businessCode: true },
    });
    const byId = new Map(nodes.map((node) => [node.id, node]));
    let cursor = byId.get(nodeId);
    for (let guard = 0; cursor && guard < 50; guard += 1) {
      if (
        allowedCodes.has(this.normalizeStatementAccessCode(cursor.code)) ||
        allowedCodes.has(this.normalizeStatementAccessCode(cursor.businessCode))
      ) {
        return true;
      }
      cursor = cursor.parentId ? byId.get(cursor.parentId) : undefined;
    }
    return false;
  }

  private normalizeStatementAccessCode(value: unknown) {
    return String(value || '')
      .trim()
      .toUpperCase();
  }

  private parseStoreCodes(value?: string) {
    return Array.from(
      new Set(
        String(value || '')
          .split(',')
          .map((item) => item.trim().toUpperCase())
          .filter(Boolean)
          .filter((item) => /^[A-Z0-9_-]{1,40}$/.test(item)),
      ),
    );
  }

  private parseBoolean(value?: string) {
    return ['true', '1', 'yes', 'y'].includes(
      String(value || '')
        .trim()
        .toLowerCase(),
    );
  }

  private normalizeStatementTransferRequestFilters(
    input: ListMapVietinStatementOrderTransferRequestsDto,
  ) {
    const storeIds = this.parseStoreCodes(input.storeIds);
    const requestedAllStores = this.parseBoolean(input.allStores);
    if (requestedAllStores && storeIds.length > 0) {
      throw new BadRequestException('Chỉ chọn tất cả hoặc danh sách showroom');
    }
    const status = String(
      input.status || STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
    )
      .trim()
      .toUpperCase();
    const page = Math.max(0, Math.trunc(Number(input.page ?? 0)));
    const rawLimit = Math.trunc(Number(input.limit ?? 50));
    const limit = Math.min(100, Math.max(1, rawLimit));
    return {
      requestedAllStores,
      storeIds,
      status,
      page,
      limit,
    };
  }

  private statementOrderTransferWindowAnchor(row: {
    paidAt?: Date | null;
    firstSeenAt?: Date | null;
  }) {
    return row.paidAt || row.firstSeenAt || null;
  }

  private vietnamDateToken(value: Date) {
    const vietnamTime = new Date(
      value.getTime() + VIETNAM_UTC_OFFSET_HOURS * 60 * 60 * 1000,
    );
    const month = String(vietnamTime.getUTCMonth() + 1).padStart(2, '0');
    const day = String(vietnamTime.getUTCDate()).padStart(2, '0');
    return `${vietnamTime.getUTCFullYear()}-${month}-${day}`;
  }

  private vietnamStartOfTodayUtc(value = new Date(Date.now())) {
    const vietnamTime = new Date(
      value.getTime() + VIETNAM_UTC_OFFSET_HOURS * 60 * 60 * 1000,
    );
    return new Date(
      Date.UTC(
        vietnamTime.getUTCFullYear(),
        vietnamTime.getUTCMonth(),
        vietnamTime.getUTCDate(),
        -VIETNAM_UTC_OFFSET_HOURS,
        0,
        0,
        0,
      ),
    );
  }

  private statementOrderTransferExpiredWhere(
    now = new Date(Date.now()),
  ): Prisma.MapVietinStatementOrderTransferRequestWhereInput {
    const startOfToday = this.vietnamStartOfTodayUtc(now);
    return {
      status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
      transaction: {
        is: {
          OR: [
            { paidAt: { lt: startOfToday } },
            {
              paidAt: null,
              firstSeenAt: { lt: startOfToday },
            },
          ],
        },
      },
    };
  }

  private async expireStaleStatementOrderTransferRequests() {
    const result =
      await this.prisma.mapVietinStatementOrderTransferRequest.updateMany({
        where: this.statementOrderTransferExpiredWhere(),
        data: {
          status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_EXPIRED,
          reviewNote: 'Yêu cầu tự động hết hạn sau 00:00.',
        },
      });
    if (result.count > 0) {
      this.logger.log(
        `Statement order transfer pending requests expired: count=${result.count}`,
      );
      await this.publishStatementOrderTransferRequestEvent({
        id: '__expired__',
        transactionId: '__expired__',
        storeCode: '__all__',
        status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_EXPIRED,
        createdAt: new Date(Date.now()),
      });
    }
  }

  private isStatementOrderTransferWindowOpen(row: {
    paidAt?: Date | null;
    firstSeenAt?: Date | null;
  }) {
    const anchor = this.statementOrderTransferWindowAnchor(row);
    if (!anchor) return false;
    return (
      this.vietnamDateToken(anchor) ===
      this.vietnamDateToken(new Date(Date.now()))
    );
  }

  private assertStatementOrderTransferWindow(row: {
    paidAt?: Date | null;
    firstSeenAt?: Date | null;
  }) {
    return this.statementPolicyRuntime.assertStatementOrderTransferWindow(row);
  }

  private normalizeStatementAmount(value?: string) {
    const text = this.cleanText(value);
    if (!text) return null;
    if (!/^[0-9.,\s]+$/.test(text)) {
      throw new BadRequestException('Số tiền không hợp lệ');
    }
    const normalized = text.replace(/[^0-9]/g, '');
    if (!normalized || normalized.length > 12) {
      throw new BadRequestException('Số tiền không hợp lệ');
    }
    return Number(normalized);
  }

  private normalizeSingleOrderCode(value: string) {
    const orders = this.normalizeOrderCodes([value]);
    if (orders.length !== 1) {
      throw new BadRequestException('Mã đơn hàng không hợp lệ');
    }
    return orders[0];
  }

  private normalizeTransactionIds(values?: string[]) {
    const output: string[] = [];
    const seen = new Set<string>();
    for (const raw of values || []) {
      const value = String(raw || '').trim();
      if (!value) continue;
      if (!/^[A-Za-z0-9_-]{1,80}$/.test(value)) {
        throw new BadRequestException('transactionIds không hợp lệ');
      }
      if (seen.has(value)) continue;
      seen.add(value);
      output.push(value);
    }
    return output;
  }

  private async resolveStore(admin: any, storeCode?: string) {
    await this.assertCanSearch(admin);
    const normalizedStoreCode = String(storeCode || '')
      .trim()
      .toUpperCase();

    if (
      await this.policyService.canAccessPolicy(
        admin,
        ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE,
      )
    ) {
      if (!normalizedStoreCode) {
        throw new BadRequestException('Vui lòng chọn showroom cần kiểm tra');
      }
      const store = await this.prisma.store.findUnique({
        where: { storeId: normalizedStoreCode },
      });
      if (!store) throw new BadRequestException('Showroom không hợp lệ');
      return store;
    }

    if (!admin.storeId) {
      throw new ForbiddenException('Tài khoản chưa được gán showroom');
    }

    const store = await this.prisma.store.findUnique({
      where: { id: admin.storeId },
    });
    if (!store) throw new BadRequestException('Showroom không hợp lệ');
    if (normalizedStoreCode && normalizedStoreCode !== store.storeId) {
      throw new ForbiddenException('Chỉ được kiểm tra showroom của mình');
    }
    return store;
  }

  private async resolveReadableStoreScope(
    user: any,
    input: { storeId?: string; storeIds?: string; allStores?: string },
  ) {
    const requestedStoreIds = Array.from(
      new Set([
        ...this.parseStoreCodes(input.storeId),
        ...this.parseStoreCodes(input.storeIds),
      ]),
    );
    const requestedAllStores = this.parseBoolean(input.allStores);
    if (requestedAllStores && requestedStoreIds.length > 0) {
      throw new BadRequestException('Chỉ chọn tất cả hoặc danh sách showroom');
    }

    if (await this.hasStoredTransactionAllScope(user)) {
      if (requestedAllStores) {
        return { storeCodes: [] as string[], allStores: true };
      }
      if (requestedStoreIds.length === 0) {
        throw new BadRequestException('Vui lòng chọn showroom cần theo dõi');
      }
      await this.assertStoresExist(requestedStoreIds);
      return { storeCodes: requestedStoreIds, allStores: false };
    }

    if (requestedAllStores) {
      throw new ForbiddenException('Không có quyền xem tất cả showroom');
    }
    const allowedStores = await this.resolveUserStores(user);
    const allowedStoreCodes = allowedStores.map((store) => store.storeId);
    const selectedStoreCodes =
      requestedStoreIds.length > 0 ? requestedStoreIds : allowedStoreCodes;
    const invalidStore = selectedStoreCodes.find(
      (storeCode) => !allowedStoreCodes.includes(storeCode),
    );
    if (invalidStore) {
      throw new ForbiddenException('Chỉ được xem giao dịch showroom được gán');
    }
    return { storeCodes: selectedStoreCodes, allStores: false };
  }

  private async resolveReadableStore(user: any, storeCode?: string) {
    const scope = await this.resolveReadableStoreScope(user, {
      storeId: storeCode,
    });
    if (scope.storeCodes.length !== 1) {
      throw new BadRequestException('Vui lòng chọn đúng một showroom');
    }
    const store = await this.prisma.store.findUnique({
      where: { storeId: scope.storeCodes[0] },
    });
    if (!store) throw new BadRequestException('Showroom không hợp lệ');
    return store;
  }

  private async assertStoresExist(storeCodes: string[]) {
    const stores = await this.prisma.store.findMany({
      where: { storeId: { in: storeCodes } },
      select: { storeId: true },
    });
    const existing = new Set(stores.map((store) => store.storeId));
    const missing = storeCodes.find((storeCode) => !existing.has(storeCode));
    if (missing) throw new BadRequestException('Showroom không hợp lệ');
  }

  private async persistTransactions(
    storeCode: string | null,
    rows: unknown[],
    stats: MapPersistStats = { updated: 0, unchanged: 0, cacheHits: 0 },
  ) {
    return this.persistenceRuntime.persistTransactions(storeCode, rows, stats);
  }

  private async persistGlobalTransactions(
    rows: unknown[],
    storeAccountIndex: Map<string, string[]>,
  ) {
    return this.accountRoutingRuntime.persistGlobalTransactions(
      rows,
      storeAccountIndex,
    );
  }

  private isEfastCreditRow(row: MapTransactionRow) {
    const dorc = this.normalizeMatchText(this.readText(row, 'dorc'));
    if (dorc) return dorc === 'C' || dorc.includes('CREDIT');
    const amount = this.readAmount(row);
    return Boolean(amount && amount > 0);
  }

  private toEfastMapTransactionRow(
    accountNo: string,
    row: MapTransactionRow,
  ): MapTransactionRow {
    const virtualAccount = this.readFirstText(
      row,
      this.efastVirtualAccountKeys,
    );
    const transactionNumber = this.firstNonEmptyText(
      row.trxId,
      row.trxRefNo,
      row.numberOrder,
    );
    const transactionReference = this.firstNonEmptyText(
      row.trxRefNo,
      row.trxId,
    );
    const content = this.firstNonEmptyText(row.remark);
    const paidAt = this.normalizeEfastTransactionDate(
      this.firstNonEmptyText(row.tranDate),
    );
    return {
      ...row,
      source: 'VIETIN_EFAST',
      virtualAccount,
      efastCreditAccountNo: accountNo,
      efastBankAccountNo: accountNo,
      transactionNumber,
      txnReference: transactionReference,
      transactionDescription: content,
      tranTime: paidAt,
      status: 'SUCCESS',
      transactionStatus: 'SUCCESS',
      reqCardNo: this.firstNonEmptyText(row.corresponsiveAccount),
      reqCardName: this.firstNonEmptyText(row.corresponsiveName),
    };
  }

  private resolveGlobalVirtualAccount(row: MapTransactionRow) {
    if (this.isEfastMapTransactionRow(row)) {
      return this.readFirstText(row, this.efastVirtualAccountKeys);
    }
    return this.readFirstText(row, this.virtualAccountKeys);
  }

  private resolveEfastSourceAccount(row: MapTransactionRow) {
    if (!this.isEfastMapTransactionRow(row)) return '';
    return this.firstNonEmptyText(
      this.readText(row, 'efastCreditAccountNo'),
      this.readText(row, 'efastBankAccountNo'),
    );
  }

  private isEfastMapTransactionRow(row: MapTransactionRow) {
    return this.readText(row, 'source') === 'VIETIN_EFAST';
  }

  private normalizeEfastTransactionDate(value: string) {
    const text = this.cleanText(value);
    if (!text) return '';
    const isoMatch =
      /^(\d{4})-(\d{2})-(\d{2})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?$/.exec(
        text,
      );
    if (isoMatch) {
      const time = isoMatch[4]
        ? ` ${isoMatch[4]}:${isoMatch[5] || '00'}:${isoMatch[6] || '00'}`
        : '';
      return `${isoMatch[3]}/${isoMatch[2]}/${isoMatch[1]}${time}`;
    }
    const dmyDashMatch =
      /^(\d{2})-(\d{2})-(\d{4})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?$/.exec(
        text,
      );
    if (dmyDashMatch) {
      const time = dmyDashMatch[4]
        ? ` ${dmyDashMatch[4]}:${dmyDashMatch[5] || '00'}:${dmyDashMatch[6] || '00'}`
        : '';
      return `${dmyDashMatch[1]}/${dmyDashMatch[2]}/${dmyDashMatch[3]}${time}`;
    }
    return text;
  }

  private hasNextEfastPage(
    response: EfastHistoryResponse,
    currentPage: number,
    rowCount: number,
    pageSize: number,
  ) {
    const nextPage = Number(response.nextPage);
    if (Number.isFinite(nextPage) && nextPage > currentPage) return true;
    return rowCount >= pageSize;
  }

  private async loadStoreAccountIndex() {
    return this.accountRoutingRuntime.loadStoreAccountIndex();
  }

  private async reassignUnassignedEfastTransactions(
    storeAccountIndex: Map<string, string[]>,
  ) {
    return this.accountRoutingRuntime.reassignUnassignedEfastTransactions(
      storeAccountIndex,
    );
  }

  private normalizeTransaction(
    storeCode: string | null,
    row: MapTransactionRow,
  ) {
    return this.persistenceRuntime.normalizeTransaction(storeCode, row);
  }

  extractOrderCodesFromContent(content: string) {
    const output: string[] = [];
    const seen = new Set<string>();
    const pattern = /(^|\D)(\d{14})(?=\D|$)/g;
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(content || '')) !== null) {
      const code = match[2];
      if (!this.isValidOrderCode(code) || seen.has(code)) continue;
      seen.add(code);
      output.push(code);
    }
    return output;
  }

  private normalizeOrderCodes(values: Array<string | null | undefined>) {
    const output: string[] = [];
    const seen = new Set<string>();
    for (const value of values) {
      const tokens = String(value || '')
        .split(/[\s,;]+/)
        .map((token) => token.trim())
        .filter(Boolean);
      for (const token of tokens) {
        if (!/^\d{14}$/.test(token)) {
          throw new BadRequestException('Mã đơn hàng phải gồm đúng 14 chữ số.');
        }
        if (!this.hasValidOrderDatePrefix(token)) {
          throw new BadRequestException(
            '6 chữ số đầu của mã đơn phải là ngày hợp lệ theo định dạng YYMMDD.',
          );
        }
        if (seen.has(token)) continue;
        seen.add(token);
        output.push(token);
      }
    }
    return output;
  }

  private isValidOrderCode(value: string) {
    if (!/^\d{14}$/.test(value)) return false;
    return this.hasValidOrderDatePrefix(value);
  }

  private hasValidOrderDatePrefix(value: string) {
    const year = 2000 + Number(value.slice(0, 2));
    const month = Number(value.slice(2, 4));
    const day = Number(value.slice(4, 6));
    if (month < 1 || month > 12 || day < 1 || day > 31) return false;
    const parsed = new Date(Date.UTC(year, month - 1, day));
    return (
      parsed.getUTCFullYear() === year &&
      parsed.getUTCMonth() === month - 1 &&
      parsed.getUTCDate() === day
    );
  }

  private sameOrderList(left: string[], right: string[]) {
    if (left.length !== right.length) return false;
    return left.every((value, index) => value === right[index]);
  }

  private toStoredTransactionDto(
    row: MapVietinStoredTransactionRow,
    options: {
      canEditProtectedOrders?: boolean;
      canUseStatements?: boolean;
      canEditIncomeType?: boolean;
      canManageTracking?: boolean;
    } = {},
  ) {
    return this.statementResponseRuntime.toStoredTransactionDto(row, options);
  }

  private toStatementOrderTransferRequestDto(
    row: {
      id: string;
      transactionId: string;
      storeCode: string;
      oldOrders: string[];
      requestedOrders: string[];
      status: string;
      requestedByUserId?: string | null;
      requestedByEmail?: string | null;
      reviewedByUserId?: string | null;
      reviewedByEmail?: string | null;
      resolutionSource?: string | null;
      reviewNote?: string | null;
      reviewedAt?: Date | null;
      createdAt: Date;
      updatedAt: Date;
      transaction?: {
        transactionNumber?: string | null;
        rawData?: Prisma.JsonValue | null;
        amount?: number | null;
        content?: string | null;
        paidAt?: Date | null;
        firstSeenAt?: Date | null;
      } | null;
    },
    notificationReadAt?: Date | null,
  ) {
    return {
      id: row.id,
      transactionId: row.transactionId,
      storeCode: row.storeCode,
      oldOrders: row.oldOrders || [],
      requestedOrders: row.requestedOrders || [],
      status: row.status,
      requestedByUserId: row.requestedByUserId || null,
      requestedByEmail: row.requestedByEmail || null,
      reviewedByUserId: row.reviewedByUserId || null,
      reviewedByEmail: row.reviewedByEmail || null,
      resolutionSource: row.resolutionSource || null,
      reviewNote: row.reviewNote || null,
      reviewedAt: row.reviewedAt || null,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      transactionNumber: row.transaction?.transactionNumber || null,
      transactionReference: row.transaction
        ? this.resolveStoredTransactionReference(row.transaction)
        : null,
      amount: row.transaction?.amount ?? null,
      content: row.transaction?.content || null,
      paidAt: row.transaction?.paidAt || null,
      firstSeenAt: row.transaction?.firstSeenAt || null,
      notificationReadAt: notificationReadAt || null,
    };
  }

  private async notificationReadAtById(
    user: any,
    source: typeof APP_NOTIFICATION_SOURCE_STATEMENT_ORDER_TRANSFER,
    ids: string[],
  ) {
    if (!this.notificationsService) return new Map<string, Date>();
    try {
      return await this.notificationsService.readAtByNotificationId(
        user,
        source,
        ids,
      );
    } catch (error) {
      this.logger.warn(
        `Statement order transfer read-state load failed: user=${this.safeUserLabel(user)} count=${ids.length} error=${this.safeError(error)}`,
      );
      return new Map<string, Date>();
    }
  }

  private async publishStatementOrderTransferRequestEvent(row: {
    id: string;
    transactionId: string;
    storeCode: string;
    status: string;
    createdAt: Date;
    recipientUserId?: string | null;
  }) {
    if (!this.redisService) {
      this.logger.warn(
        `Statement order transfer realtime skipped: redis unavailable request=${row.id}`,
      );
      return;
    }
    const occurredAt = new Date();
    const storeCodes = row.storeCode === '__all__' ? [] : [row.storeCode];
    await this.redisService.publishMessage(
      STATEMENT_ORDER_TRANSFER_CHANNEL,
      buildRealtimeRedisEnvelope({
        type: 'STATEMENT_ORDER_TRANSFER_REQUEST',
        occurredAt,
        audience: {
          storeCodes,
          recipientUserIds: row.recipientUserId ? [row.recipientUserId] : [],
          roles: ['SUPER_ADMIN'],
          policyCodes: [ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE],
          featureCodes: [FEATURE_KEYS.BANK_STATEMENTS],
        },
        payload: {
          requestId: row.id,
          transactionId: row.transactionId,
          storeCode: row.storeCode,
          status: row.status,
          createdAt: row.createdAt.toISOString(),
          ...(row.recipientUserId
            ? { recipientUserId: row.recipientUserId }
            : {}),
        },
      }),
    );
  }

  private resolveStoredPayer(row: {
    payerName?: string | null;
    payerAccount?: string | null;
    rawData?: Prisma.JsonValue | null;
  }) {
    const rawData = this.rawDataAsMapRow(row.rawData);
    const rawName = rawData
      ? this.readFirstText(rawData, this.payerNameKeys)
      : '';
    const rawAccount = rawData
      ? this.readFirstText(rawData, this.payerAccountKeys)
      : '';
    return {
      name: this.firstNonEmptyText(row.payerName, rawName) || null,
      account: this.firstNonEmptyText(row.payerAccount, rawAccount) || null,
    };
  }

  private resolveStoredTransactionReference(row: {
    transactionNumber?: string | null;
    rawData?: Prisma.JsonValue | null;
  }) {
    return resolveStoredStatementNumber(row);
  }

  private resolveStoredReceivingAccount(row: {
    rawData?: Prisma.JsonValue | null;
  }) {
    const rawData = this.rawDataAsMapRow(row.rawData);
    if (!rawData) return null;
    return (
      this.firstNonEmptyText(
        this.readText(rawData, 'efastCreditAccountNo'),
        this.readText(rawData, 'efastBankAccountNo'),
        this.readFirstText(rawData, this.virtualAccountKeys),
        this.readText(rawData, 'toAccount'),
        this.readText(rawData, 'toAccountNo'),
        this.readText(rawData, 'beneficiaryAccount'),
        this.readText(rawData, 'beneficiaryAccountNo'),
      ) || null
    );
  }

  private storedIncomeType(row: {
    content?: string | null;
    storeCode?: string | null;
    payerAccount?: string | null;
    incomeType?: string | null;
  }) {
    const value = String(row.incomeType || '')
      .trim()
      .toUpperCase();
    if (
      value === MAP_VIETIN_INCOME_TYPE.SALES ||
      value === MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL
    ) {
      return value;
    }
    return classifyMapVietinIncomeType(row.content, row.payerAccount);
  }

  private storedOrderTrackingStatus(row: {
    orderTrackingStatus?: string | null;
  }) {
    return String(row.orderTrackingStatus || ORDER_TRACKING_STATUS_FOLLOWING)
      .trim()
      .toUpperCase() === ORDER_TRACKING_STATUS_UNFOLLOWED
      ? ORDER_TRACKING_STATUS_UNFOLLOWED
      : ORDER_TRACKING_STATUS_FOLLOWING;
  }

  private rawDataAsMapRow(value?: Prisma.JsonValue | null) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      return null;
    }
    return value as MapTransactionRow;
  }

  private isSuccessfulTransaction(row: MapTransactionRow) {
    const values = this.statusKeys
      .map((key) => this.readText(row, key))
      .filter(Boolean);
    const statusText = this.normalizeMatchText(values.join(' '));
    const statusCodes = values.map((value) => value.trim().toUpperCase());

    return (
      statusText.includes('THANH CONG') ||
      statusText.includes('SUCCESS') ||
      statusText.includes('DA THANH TOAN') ||
      statusText.includes('HOAN THANH') ||
      statusText.includes('COMPLETED') ||
      statusText.includes('APPROVED') ||
      statusCodes.includes('00')
    );
  }

  private readAmount(row: MapTransactionRow) {
    for (const key of this.amountKeys) {
      const value = row[key];
      if (typeof value === 'number') return Math.trunc(value);
      const normalized = String(value || '').replace(/[^0-9]/g, '');
      if (normalized) return Number(normalized);
    }
    return null;
  }

  private readTransactionTime(row: MapTransactionRow) {
    const raw = this.readFirstText(row, this.transactionTimeKeys);
    if (!raw) return null;
    const match =
      /^(\d{2})[/-](\d{2})[/-](\d{4})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?$/.exec(
        raw,
      );
    if (match) {
      return this.vietnamDatePartsToUtc({
        year: Number(match[3]),
        month: Number(match[2]),
        day: Number(match[1]),
        hour: Number(match[4] || '0'),
        minute: Number(match[5] || '0'),
        second: Number(match[6] || '0'),
      });
    }
    const isoMatch =
      /^(\d{4})-(\d{2})-(\d{2})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?$/.exec(raw);
    if (isoMatch) {
      return this.vietnamDatePartsToUtc({
        year: Number(isoMatch[1]),
        month: Number(isoMatch[2]),
        day: Number(isoMatch[3]),
        hour: Number(isoMatch[4] || '0'),
        minute: Number(isoMatch[5] || '0'),
        second: Number(isoMatch[6] || '0'),
      });
    }
    const parsed = new Date(raw);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  private vietnamDatePartsToUtc(input: {
    year: number;
    month: number;
    day: number;
    hour: number;
    minute: number;
    second: number;
  }) {
    return new Date(
      Date.UTC(
        input.year,
        input.month - 1,
        input.day,
        input.hour - VIETNAM_UTC_OFFSET_HOURS,
        input.minute,
        input.second,
      ),
    );
  }

  private readText(row: MapTransactionRow, key: string) {
    const value = row[key];
    return value === null || value === undefined ? '' : String(value).trim();
  }

  private readFirstText(row: MapTransactionRow, keys: string[]) {
    for (const key of keys) {
      const value = this.readText(row, key);
      if (value) return value;
    }
    return '';
  }

  private firstNonEmptyText(...values: unknown[]) {
    for (const value of values) {
      const text =
        value === null || value === undefined ? '' : String(value).trim();
      if (text) return text;
    }
    return '';
  }

  private normalizeMatchText(value: string) {
    return (value || '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/Đ/g, 'D')
      .replace(/đ/g, 'd')
      .toUpperCase()
      .replace(/[^A-Z0-9]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private normalizeAccountNumber(value: string) {
    return String(value || '')
      .toUpperCase()
      .replace(/[^A-Z0-9]/g, '')
      .trim();
  }

  private scrubJson(value: unknown): unknown {
    if (Array.isArray(value)) return value.map((item) => this.scrubJson(item));
    if (!value || typeof value !== 'object') return value;
    const output: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value)) {
      const normalizedKey = key.toLowerCase();
      if (
        normalizedKey.includes('password') ||
        normalizedKey.includes('token') ||
        normalizedKey.includes('authorization') ||
        normalizedKey.includes('secret')
      ) {
        output[key] = '[REDACTED]';
      } else {
        output[key] = this.scrubJson(item);
      }
    }
    return output;
  }

  private maskAccount(value: string) {
    const normalized = this.normalizeAccountNumber(value);
    if (!normalized) return 'missing';
    if (normalized.length <= 4) return '****';
    return `****${normalized.slice(-4)}`;
  }

  private parseDate(value: string, fieldName: string) {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
      throw new BadRequestException(`${fieldName} không hợp lệ`);
    }
    return parsed;
  }

  private resolveStoredTransactionDateRange(
    input: ListStoredMapVietinTransactionsDto,
  ) {
    if (input.startDate || input.endDate) {
      return this.parseVietnamDateRange(
        input.startDate || input.endDate,
        input.endDate || input.startDate,
      );
    }
    if (input.date) return this.parseVietnamDateRange(input.date, input.date);
    return null;
  }

  private parseVietnamDateRange(startValue?: string, endValue?: string) {
    const startMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(
      String(startValue || ''),
    );
    const endMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(
      String(endValue || startValue || ''),
    );
    if (!startMatch || !endMatch) {
      throw new BadRequestException('date không hợp lệ');
    }
    const year = Number(startMatch[1]);
    const month = Number(startMatch[2]);
    const day = Number(startMatch[3]);
    const endYear = Number(endMatch[1]);
    const endMonth = Number(endMatch[2]);
    const endDay = Number(endMatch[3]);
    const start = new Date(Date.UTC(year, month - 1, day, -7, 0, 0, 0));
    const end = new Date(
      Date.UTC(endYear, endMonth - 1, endDay + 1, -7, 0, 0, 0),
    );
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
      throw new BadRequestException('date không hợp lệ');
    }
    if (end <= start) {
      throw new BadRequestException('endDate phải sau startDate');
    }
    return { start, end };
  }

  private async assertCanSearch(admin: any) {
    if (await this.canUseStatements(admin)) {
      return;
    }
    throw new ForbiddenException('Không có quyền kiểm tra giao dịch MAP');
  }

  private decryptMapPassword(cipherText: string) {
    try {
      return decryptSecret(cipherText);
    } catch (error) {
      this.logger.warn(`Cannot decrypt MAP password: ${this.safeError(error)}`);
      throw new BadRequestException(
        'Không giải mã được mật khẩu VietinBank MAP',
      );
    }
  }

  private async login(username: string, password: string, storeId: string) {
    const body = {
      username,
      password: this.sha256(password),
      captcha_resp: '123456',
      device: {
        os: { name: 'linux', version: '' },
        browser: { name: 'node', version: process.version },
        location: { long: 0, lat: 0 },
      },
      ip_address: process.env.MAP_VIETIN_LOGIN_IP || '118.70.124.48',
      language: 'vi',
    };

    const response = await this.postJson<MapLoginResponse>(
      `${this.noAuthBaseUrl()}/login`,
      body,
      {
        ClientId: this.clientId(),
        Signature: this.signature(body),
      },
    );

    if (response.error_code && response.error_code !== '00') {
      throw new UnauthorizedException(
        response.error_desc || response.message || 'Đăng nhập MAP thất bại',
      );
    }
    if (!response.access_token) {
      throw new BadGatewayException('MAP không trả access token');
    }

    const defaultMerchant =
      response.merchant_info?.find((merchant) => merchant.is_default) ??
      response.merchant_info?.[0];
    const merchantId = String(defaultMerchant?.merchant_id || '').trim();
    if (!merchantId) {
      throw new BadGatewayException('MAP không trả merchant id');
    }

    this.logger.log(`MAP login succeeded for store ${storeId}`);
    return { accessToken: response.access_token, merchantId };
  }

  private buildSearchRequest(input: SearchMapVietinTransactionsDto) {
    const today = this.formatMapDate(new Date());
    const request: Record<string, string | string[]> = {
      searchType: input.searchType || '0',
      searchInput: this.cleanText(input.searchInput),
      branchIds: this.cleanSelect(input.branchId),
      terminalIds: this.cleanSelect(input.terminalId),
      methodInfoId: this.cleanSelect(input.paymentMethod),
      status: this.cleanSelect(input.transactionStatus),
      startDate: this.normalizeMapDate(input.startDate) || today,
      endDate: this.normalizeMapDate(input.endDate) || today,
      amount: this.cleanAmount(input.amount),
      tranNumber: this.cleanText(input.tranNumber),
    };

    return Object.fromEntries(
      Object.entries(request).filter(([, value]) => {
        if (Array.isArray(value)) return value.length > 0;
        return value !== '' && value !== 'all';
      }),
    );
  }

  private cleanText(value?: string) {
    return String(value || '').trim();
  }

  private normalizeReviewNote(value?: string | null) {
    const text = String(value || '').trim();
    return text ? text.slice(0, 500) : null;
  }

  private cleanSelect(value?: string) {
    return this.cleanText(value) || 'all';
  }

  private cleanAmount(value?: string) {
    const amount = this.cleanText(value).replace(/,/g, '');
    if (!amount) return '';
    if (!/^\d{1,12}$/.test(amount)) {
      throw new BadRequestException('Số tiền MAP không hợp lệ');
    }
    return amount;
  }

  private normalizeMapDate(value?: string) {
    const text = this.cleanText(value);
    if (!text) return '';
    if (/^\d{2}\/\d{2}\/\d{4}$/.test(text)) return text;
    const isoMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
    if (isoMatch) return `${isoMatch[3]}/${isoMatch[2]}/${isoMatch[1]}`;
    throw new BadRequestException('Ngày MAP không hợp lệ');
  }

  private formatMapDate(value: Date) {
    const vietnamDate = new Date(this.vietnamTimeMs(value));
    return [
      String(vietnamDate.getUTCDate()).padStart(2, '0'),
      String(vietnamDate.getUTCMonth() + 1).padStart(2, '0'),
      vietnamDate.getUTCFullYear(),
    ].join('/');
  }

  private vietnamTimeMs(value: Date) {
    return value.getTime() + VIETNAM_UTC_OFFSET_HOURS * 60 * 60 * 1000;
  }

  private async postJson<T>(
    url: string,
    body: Record<string, unknown>,
    headers: Record<string, string>,
    providerLabel = 'MAP',
  ): Promise<T> {
    return this.providerRuntime.postJson<T>(url, body, headers, providerLabel);
  }

  private registerMapProviderBackoff(
    providerStatus: 403 | 429,
    providerRetryAfterMs?: number,
  ) {
    this.providerRuntime.registerMapProviderBackoff(
      providerStatus,
      providerRetryAfterMs,
    );
  }

  private clearMapProviderBackoff() {
    this.providerRuntime.clearMapProviderBackoff();
  }

  private retryAfterMs(value?: string | null) {
    return this.providerRuntime.retryAfterMs(value);
  }

  private readPositiveInt(name: string, fallback: number) {
    const parsed = Number(process.env[name]);
    return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
  }

  private safeProviderMessage(value: unknown) {
    if (!value || typeof value !== 'object') return 'Không rõ lỗi';
    const record = value as Record<string, unknown>;
    const status =
      record.status && typeof record.status === 'object'
        ? (record.status as Record<string, unknown>)
        : {};
    return String(
      status.message ||
        status.subCode ||
        record.message ||
        record.error_desc ||
        record.error ||
        'Không rõ lỗi',
    ).slice(0, 180);
  }

  private signature(body: Record<string, unknown>) {
    return createHash('md5')
      .update(JSON.stringify(body) + this.signatureKey())
      .digest('hex');
  }

  private sha256(value: string) {
    return createHash('sha256').update(value).digest('hex');
  }

  private clientId() {
    return process.env.MAP_VIETIN_CLIENT_ID || MAP_CLIENT_ID;
  }

  private signatureKey() {
    return process.env.MAP_VIETIN_SIGNATURE_KEY || MAP_SIGNATURE_KEY;
  }

  private noAuthBaseUrl() {
    return process.env.MAP_VIETIN_NO_AUTH_BASE_URL || MAP_NO_AUTH_BASE_URL;
  }

  private transactionBaseUrl() {
    return (
      process.env.MAP_VIETIN_TRANSACTION_BASE_URL || MAP_TRANSACTION_BASE_URL
    );
  }

  private isEfastSyncEnabled() {
    return process.env.VIETIN_EFAST_SYNC_ENABLED === 'true';
  }

  private efastUsername() {
    return String(process.env.VIETIN_EFAST_USERNAME || '').trim();
  }

  private efastPassword() {
    return String(process.env.VIETIN_EFAST_PASSWORD || '').trim();
  }

  private efastCifno() {
    return this.normalizeAccountNumber(process.env.VIETIN_EFAST_CIFNO || '');
  }

  private efastBankAccounts() {
    return String(process.env.VIETIN_EFAST_BANK_ACCOUNTS || '')
      .split(',')
      .map((account) => this.normalizeAccountNumber(account))
      .filter(Boolean);
  }

  private efastBaseUrl() {
    return (process.env.VIETIN_EFAST_BASE_URL || EFAST_BASE_URL).replace(
      /\/+$/,
      '',
    );
  }

  private efastApiUrl(path: string) {
    const normalizedPath = path.replace(/^\/+/, '');
    return `${this.efastBaseUrl()}${EFAST_API_PREFIX}/${normalizedPath}`;
  }

  private efastHeaders() {
    return { 'x-lang': 'vi' };
  }

  private efastPageSize() {
    const parsed = Number(process.env.VIETIN_EFAST_PAGE_SIZE);
    return Number.isFinite(parsed) && parsed > 0
      ? Math.min(Math.trunc(parsed), EFAST_DEFAULT_PAGE_SIZE)
      : EFAST_DEFAULT_PAGE_SIZE;
  }

  private efastSyncMaxPages() {
    const parsed = Number(process.env.VIETIN_EFAST_SYNC_MAX_PAGES);
    return Number.isFinite(parsed) && parsed > 0
      ? Math.min(Math.trunc(parsed), EFAST_DEFAULT_MAX_PAGES)
      : EFAST_DEFAULT_MAX_PAGES;
  }

  private efastSessionTtlSeconds() {
    const parsed = Number(process.env.VIETIN_EFAST_SESSION_TTL_SECONDS);
    return Number.isFinite(parsed) && parsed > 0
      ? Math.trunc(parsed)
      : EFAST_DEFAULT_SESSION_TTL_SECONDS;
  }

  private efastDeviceId(username: string) {
    const configured = String(process.env.VIETIN_EFAST_DEVICE_ID || '').trim();
    if (configured) return configured;
    return this.sha256(`opshub-efast:${username}`).slice(0, 32);
  }

  private newEfastRequestId() {
    return `${Date.now().toString(36)}${Math.random().toString(36).slice(2)}`;
  }

  private encryptEfastText(value: string) {
    const publicKey = [
      '-----BEGIN PUBLIC KEY-----',
      EFAST_PUBLIC_KEY.match(/.{1,64}/g)?.join('\n') || EFAST_PUBLIC_KEY,
      '-----END PUBLIC KEY-----',
    ].join('\n');
    return publicEncrypt(
      {
        key: publicKey,
        padding: cryptoConstants.RSA_PKCS1_PADDING,
      },
      Buffer.from(value, 'utf8'),
    ).toString('base64');
  }

  private isEfastSuccess(status?: EfastStatus) {
    const code = String(status?.code || '').trim();
    return code === EFAST_SUCCESS_CODE || code === '00';
  }

  private shouldUseGlobalSync() {
    if (process.env.MAP_VIETIN_GLOBAL_SYNC_ENABLED === 'false') return false;
    const hasCredentials = Boolean(
      this.globalUsername() && this.globalPassword(),
    );
    if (
      process.env.MAP_VIETIN_GLOBAL_SYNC_ENABLED === 'true' &&
      !hasCredentials
    ) {
      this.logger.warn(
        'Global MAP sync is enabled but MAP_VIETIN_GLOBAL_USERNAME or MAP_VIETIN_GLOBAL_PASSWORD is missing; falling back to per-store sync',
      );
    }
    return hasCredentials;
  }

  private globalUsername() {
    return String(process.env.MAP_VIETIN_GLOBAL_USERNAME || '').trim();
  }

  private globalPassword() {
    return String(process.env.MAP_VIETIN_GLOBAL_PASSWORD || '').trim();
  }

  private globalSyncMaxPages() {
    const parsed = Number(process.env.MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES);
    return Number.isFinite(parsed) && parsed > 0
      ? Math.trunc(parsed)
      : DEFAULT_GLOBAL_SYNC_MAX_PAGES;
  }

  private globalSessionTtlSeconds() {
    const parsed = Number(process.env.MAP_VIETIN_GLOBAL_SESSION_TTL_SECONDS);
    return Number.isFinite(parsed) && parsed > 0
      ? Math.trunc(parsed)
      : DEFAULT_GLOBAL_SESSION_TTL_SECONDS;
  }

  private toStatementsXlsx(rows: MapVietinStoredTransactionRow[]) {
    return this.statementResponseRuntime.toStatementsXlsx(rows);
  }

  private safeUserLabel(user: any) {
    const userId = String(user?.id || '').trim();
    if (userId) return `userId:${userId.slice(0, 80)}`;
    const email = this.safeUserEmail(user);
    return email ? `emailHash:${this.sha256(email).slice(0, 12)}` : 'unknown';
  }

  private safeUserEmail(user: any) {
    const email = String(user?.email || '')
      .trim()
      .toLowerCase();
    return email || null;
  }

  private isPhongVuEmail(value: unknown) {
    const email = String(value || '')
      .trim()
      .toLowerCase();
    return email.endsWith('@phongvu.vn');
  }

  private isProviderAuthError(error: unknown) {
    const message = this.safeError(error);
    const providerStatus = this.providerHttpStatus(error);
    return (
      providerStatus === 401 ||
      providerStatus === 403 ||
      message.includes(EFAST_INVALID_SESSION_CODE) ||
      message.toLowerCase().includes('session is invalid')
    );
  }

  private providerHttpStatus(error: unknown) {
    if (error instanceof BankProviderHttpException) {
      return error.providerStatus;
    }
    const match = this.safeError(error).match(
      /(?:trả lỗi|returned)\s+(\d{3})/i,
    );
    return match ? Number(match[1]) : null;
  }

  private safeError(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }
}
