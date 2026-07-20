import {
  BadGatewayException,
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
  Optional,
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
import {
  HttpResponseTooLargeError,
  readBoundedHttpResponse,
} from '../common/bounded-http-response';
import { buildRealtimeRedisEnvelope } from '../common/realtime-event';
import * as XLSX from 'xlsx';
import {
  CreateMapVietinStatementOrderTransferRequestDto,
  ExportMapVietinStatementsDto,
  ListMapVietinStatementOrderTransferRequestsDto,
  ListStoredMapVietinTransactionsDto,
  ListMapVietinStatementsDto,
  ReviewMapVietinStatementOrderTransferRequestDto,
  SearchMapVietinTransactionsDto,
  UpdateMapVietinStatementIncomeTypeDto,
  UpdateMapVietinStatementOrdersDto,
} from './map-vietin.dto';
import {
  classifyMapVietinIncomeType,
  mapVietinIncomeTypeLabel,
  MAP_VIETIN_INCOME_TYPE,
} from './income-type';

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
const EFAST_SYNC_START_HOUR_VN = 8;
const EFAST_SYNC_END_HOUR_VN = 22;
const EFAST_FAST_SYNC_DELAY_MIN_MS = 50 * 1000;
const EFAST_FAST_SYNC_DELAY_MAX_MS = 60 * 1000;
const EFAST_NIGHT_SYNC_DELAY_MS = 30 * 60 * 1000;
const MAP_SYNC_PAGE_SIZE = 100;
const MAP_SYNC_START_HOUR_VN = 7;
const MAP_SYNC_END_HOUR_VN = 22;
const DEFAULT_MAP_HISTORY_SYNC_DELAY_MIN_MS = 1000;
const DEFAULT_MAP_HISTORY_SYNC_DELAY_MAX_MS = 2000;
const MIN_MAP_HISTORY_SYNC_DELAY_MS = 500;
const DEFAULT_MAP_DEEP_SWEEP_DELAY_MIN_MS = 30 * 1000;
const DEFAULT_MAP_DEEP_SWEEP_DELAY_MAX_MS = 60 * 1000;
const MIN_MAP_DEEP_SWEEP_DELAY_MS = 30 * 1000;
const DEFAULT_MAP_RATE_LIMIT_BACKOFF_BASE_MS = 30 * 1000;
const DEFAULT_MAP_RATE_LIMIT_BACKOFF_MAX_MS = 2 * 60 * 1000;
const DEFAULT_MAP_FORBIDDEN_BACKOFF_MS = 5 * 60 * 1000;
const MAP_PROVIDER_BACKOFF_JITTER_MAX_MS = 5 * 1000;
const MAP_PROVIDER_RETRY_AFTER_MAX_MS = 15 * 60 * 1000;
const DEFAULT_MAP_SYNC_FINGERPRINT_CACHE_TTL_MS = 5 * 60 * 1000;
const DEFAULT_MAP_SYNC_FINGERPRINT_CACHE_MAX_ENTRIES = 20_000;
const MAX_MAP_SYNC_FINGERPRINT_CACHE_ENTRIES = 100_000;
const MAP_HISTORY_SYNC_NIGHT_DELAY_MS = 30 * 60 * 1000;
const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const DEFAULT_GLOBAL_SYNC_MAX_PAGES = 2;
const DEFAULT_GLOBAL_SESSION_TTL_SECONDS = 10 * 60;
const VIETNAM_UTC_OFFSET_HOURS = 7;
const ORDER_SOURCE_AUTO = 'AUTO';
const ORDER_SOURCE_MANUAL = 'MANUAL';
const ORDER_SOURCE_OFFSET = 'OFFSET';
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
const STATEMENT_EXPORT_MAX_DATE_SPAN_DAYS = 31;
const STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING = 'PENDING';
const STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_APPROVED = 'APPROVED';
const STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_REJECTED = 'REJECTED';
const STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_EXPIRED = 'EXPIRED';
const STATEMENT_ORDER_TRANSFER_NOTIFICATION_STATUS = 'NOTIFICATION';
const STATEMENT_ORDER_TRANSFER_CHANNEL = 'STATEMENT_ORDER_TRANSFER_REQUESTED';
const MS_PER_DAY = 24 * 60 * 60 * 1000;
const DEFAULT_PROVIDER_TIMEOUT_MS = 30_000;
const DEFAULT_PROVIDER_RESPONSE_MAX_BYTES = 10 * 1024 * 1024;

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

type MapTransactionRow = Record<string, unknown>;

type MapSession = {
  accessToken: string;
  merchantId: string;
};

type MapGlobalSyncMode =
  | 'fast_page'
  | 'deep_sweep'
  | 'session_recovery'
  | 'manual';

type MapGlobalSyncOptions = {
  mode?: MapGlobalSyncMode;
  maxPages?: number;
};

class BankProviderHttpException extends BadGatewayException {
  constructor(
    readonly providerStatus: number,
    providerLabel: string,
    providerMessage: string,
    readonly retryAfterMs?: number,
  ) {
    super(`${providerLabel} trả lỗi ${providerStatus}: ${providerMessage}`);
  }
}

type MapPersistStats = {
  updated: number;
  unchanged: number;
  cacheHits: number;
};

type MapSyncFingerprintCacheEntry = {
  fingerprint: string;
  expiresAt: number;
};

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

type EfastSession = {
  username: string;
  cifno: string;
  sessionId: string;
};

type StoreAccountRow = {
  storeId: string;
  transferAccountNumber?: string | null;
};

type UnmappedReason =
  | 'MISSING_VIRTUAL_ACCOUNT'
  | 'UNMAPPED_ACCOUNT'
  | 'AMBIGUOUS_ACCOUNT';

@Injectable()
export class MapVietinService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MapVietinService.name);
  private syncInProgress = false;
  private efastSyncInProgress = false;
  private lastSyncWindowOpen?: boolean;
  private lastEfastSyncWindowOpen?: boolean;
  private mapHistorySyncTimer?: NodeJS.Timeout;
  private efastSyncTimer?: NodeJS.Timeout;
  private mapHistorySyncStopped = false;
  private efastSyncStopped = false;
  private mapHistoryDeepSweepDueAt = 0;
  private mapProviderBackoffUntil = 0;
  private mapProviderBackoffAttempt = 0;
  private readonly mapSyncFingerprintCache = new Map<
    string,
    MapSyncFingerprintCacheEntry
  >();
  private mapPersistenceQueue: Promise<void> = Promise.resolve();
  private globalSessionCache?: {
    username: string;
    session: MapSession;
    expiresAt: number;
  };
  private efastSessionCache?: {
    username: string;
    cifno: string;
    session: EfastSession;
    expiresAt: number;
  };
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
  ) {}

  onModuleInit() {
    this.mapHistorySyncStopped = false;
    this.efastSyncStopped = false;
    this.mapHistoryDeepSweepDueAt = 0;
    this.mapProviderBackoffUntil = 0;
    this.mapProviderBackoffAttempt = 0;
    if (this.isMapHistorySyncDisabled()) {
      this.logger.log(
        'MAP history sync scheduler disabled by MAP_VIETIN_SYNC_ENABLED=false',
      );
    } else {
      this.scheduleNextMapHistorySync(0);
    }
    this.scheduleNextEfastSync();
  }

  onModuleDestroy() {
    this.mapHistorySyncStopped = true;
    this.efastSyncStopped = true;
    if (this.mapHistorySyncTimer) {
      clearTimeout(this.mapHistorySyncTimer);
      this.mapHistorySyncTimer = undefined;
    }
    if (this.efastSyncTimer) {
      clearTimeout(this.efastSyncTimer);
      this.efastSyncTimer = undefined;
    }
    this.mapSyncFingerprintCache.clear();
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
    const [canEditProtectedOrders, canReviewOrderTransfers] = canUseStatements
      ? await Promise.all([
          this.canEditProtectedStatementOrders(user),
          this.canReviewStatementOrderTransferRequests(user),
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
          canEditProtectedOrders,
          canUseStatements,
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
    const canEditProtectedOrders =
      await this.canEditProtectedStatementOrders(user);
    const canEditIncomeType = await this.canEditStatementIncomeType(user);
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
        return this.toStoredTransactionDto(row, {
          canEditProtectedOrders:
            canEditProtectedOrders || verifiedOrderLookupEdit,
          canUseStatements: canUseStatementActions,
          canEditIncomeType: canEditIncomeType && canUseStatementActions,
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
    await this.assertCanUseStatements(user);
    await this.expireStaleStatementOrderTransferRequests();
    const id = String(transactionId || '').trim();
    if (!id) throw new BadRequestException('transactionId không hợp lệ');
    const orders = this.normalizeOrderCodes(input.orders || []);
    const transactionKey = String(input.transactionKey || '').trim();
    let existing = await this.prisma.mapVietinTransaction.findUnique({
      where: { id },
    });
    let resolvedId = id;
    let resolvedByTransactionKey = false;
    if (!existing && transactionKey) {
      existing = await this.prisma.mapVietinTransaction.findUnique({
        where: { transactionKey },
      });
      if (existing) {
        resolvedId = existing.id;
        resolvedByTransactionKey = true;
        this.logger.warn(
          `Statement order update resolved stale id by transaction key: user=${this.safeUserLabel(user)} requestedTransaction=${id} resolvedTransaction=${resolvedId} store=${existing.storeCode}`,
        );
      }
    }
    if (!existing) {
      this.logger.warn(
        `Statement order update rejected: user=${this.safeUserLabel(user)} transaction=${id} hasTransactionKey=${Boolean(transactionKey)} reason=missing_transaction`,
      );
      throw new BadRequestException('Giao dịch không hợp lệ');
    }
    const lookup = this.normalizeStatementOrderUpdateLookup(input);
    const canReadStore = await this.canReadStatementStore(
      user,
      existing.storeCode,
    );
    const verifiedOrderLookupEdit = this.matchesStatementOrderUpdateLookup(
      existing,
      lookup.hasExactField ? lookup : null,
    );
    if (!canReadStore && !verifiedOrderLookupEdit) {
      this.logger.warn(
        `Statement order update rejected: user=${this.safeUserLabel(user)} transaction=${resolvedId} store=${existing.storeCode} reason=cross_store_lookup_not_verified hasLookup=${lookup.hasExactField}`,
      );
      throw new ForbiddenException(
        'Chỉ được sửa giao dịch showroom khác khi tìm chính xác bằng mã sao kê, mã đơn, số tiền hoặc nội dung chuyển khoản.',
      );
    }
    const pendingTransferRequest =
      await this.prisma.mapVietinStatementOrderTransferRequest.findFirst({
        where: {
          transactionId: resolvedId,
          status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
        },
      });
    if (pendingTransferRequest) {
      throw new BadRequestException('Giao dịch đang chờ Kế toán xác nhận');
    }

    const oldOrders = this.normalizeOrderCodes(existing.orders || []);
    const changed = !this.sameOrderList(oldOrders, orders);
    const canEditProtectedOrders =
      await this.canEditProtectedStatementOrders(user);
    const canEditIncomeType = await this.canEditStatementIncomeType(user);
    const canEditThisProtectedOrder =
      canEditProtectedOrders || verifiedOrderLookupEdit;
    this.assertStatementOrderEditAllowed(existing, canEditThisProtectedOrder);
    const assignedStoreCode = existing.storeCode
      ? existing.storeCode
      : (await this.resolveUserStore(user)).storeId;
    const now = new Date();
    const updated = await this.prisma.mapVietinTransaction.update({
      where: { id: resolvedId },
      data: {
        storeCode: assignedStoreCode,
        orders,
        orderSource: ORDER_SOURCE_MANUAL,
        orderUpdatedAt: now,
        orderUpdatedByUserId: user.id || null,
        orderUpdatedByEmail: this.safeUserEmail(user),
      },
    });

    if (changed) {
      await this.prisma.mapVietinTransactionOrderAudit.create({
        data: {
          transactionId: resolvedId,
          storeCode: assignedStoreCode,
          oldOrders,
          newOrders: orders,
          changedByUserId: user.id || null,
          changedByEmail: this.safeUserEmail(user),
          source: ORDER_SOURCE_MANUAL,
        },
      });
    }

    this.logger.log(
      `Statement orders updated: user=${this.safeUserLabel(user)} transaction=${resolvedId} requestedTransaction=${id} store=${assignedStoreCode} oldStore=${existing.storeCode || 'null'} oldCount=${oldOrders.length} newCount=${orders.length} changed=${changed} protected=${oldOrders.length > 0} finAcc=${canEditProtectedOrders} resolvedByTransactionKey=${resolvedByTransactionKey} crossStoreVerified=${!canReadStore && verifiedOrderLookupEdit}`,
    );
    return this.toStoredTransactionDto(updated, {
      canEditProtectedOrders: canEditThisProtectedOrder,
      canEditIncomeType,
    });
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

  async createStatementOrderTransferRequest(
    user: any,
    transactionId: string,
    input: CreateMapVietinStatementOrderTransferRequestDto,
  ) {
    await this.assertCanUseStatements(user);
    await this.expireStaleStatementOrderTransferRequests();
    const startedAt = Date.now();
    const id = String(transactionId || '').trim();
    if (!id) throw new BadRequestException('transactionId không hợp lệ');
    const requestedOrders = this.normalizeOrderCodes(input.orders || []);
    if (requestedOrders.length === 0) {
      throw new BadRequestException('Vui lòng nhập mã đơn hàng mới');
    }
    const existing = await this.prisma.mapVietinTransaction.findUnique({
      where: { id },
    });
    if (!existing) throw new BadRequestException('Giao dịch không hợp lệ');
    if (!existing.storeCode) {
      throw new BadRequestException(
        'Giao dịch chưa có showroom nên không tạo yêu cầu cấn trừ.',
      );
    }
    await this.assertCanReadStatementStore(user, existing.storeCode);
    this.assertStatementOrderTransferWindow(existing);
    const oldOrders = this.normalizeOrderCodes(existing.orders || []);
    if (this.sameOrderList(oldOrders, requestedOrders)) {
      throw new BadRequestException('Mã đơn mới đang trùng mã hiện tại');
    }
    const pending =
      await this.prisma.mapVietinStatementOrderTransferRequest.findFirst({
        where: {
          transactionId: id,
          status: STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING,
        },
      });
    if (pending) {
      throw new BadRequestException('Giao dịch đang chờ Kế toán xác nhận');
    }

    try {
      const request =
        await this.prisma.mapVietinStatementOrderTransferRequest.create({
          data: {
            transactionId: id,
            storeCode: existing.storeCode,
            oldOrders,
            requestedOrders,
            requestedByUserId: user.id || null,
            requestedByEmail: this.safeUserEmail(user),
          },
          include: { transaction: true },
        });
      await this.publishStatementOrderTransferRequestEvent(request);
      this.logger.log(
        `Statement order transfer requested: user=${this.safeUserLabel(user)} transaction=${id} request=${request.id} store=${existing.storeCode} oldCount=${oldOrders.length} requestedCount=${requestedOrders.length} durationMs=${Date.now() - startedAt}`,
      );
      return this.toStatementOrderTransferRequestDto(request);
    } catch (error) {
      if ((error as any)?.code === 'P2002') {
        throw new BadRequestException('Giao dịch đang chờ Kế toán xác nhận');
      }
      this.logger.error(
        `Statement order transfer request failed: user=${this.safeUserLabel(user)} transaction=${id} store=${existing.storeCode} requestedCount=${requestedOrders.length} durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
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
    if (this.mapHistorySyncStopped || this.isMapHistorySyncDisabled()) return;
    const now = Date.now();
    const normalDelayMs =
      delayOverrideMs ?? this.nextMapHistorySyncDelayMs(new Date(now));
    const backoffDelayMs = Math.max(0, this.mapProviderBackoffUntil - now);
    const delayMs = Math.max(normalDelayMs, backoffDelayMs);
    if (this.mapHistorySyncTimer) {
      clearTimeout(this.mapHistorySyncTimer);
    }
    this.mapHistorySyncTimer = setTimeout(() => {
      void this.runScheduledMapHistorySync();
    }, delayMs);
    this.mapHistorySyncTimer.unref?.();
    this.logger.debug(
      `Next MAP history sync scheduled in ${delayMs}ms mode=${this.mapHistoryDeepSweepDueAt <= now ? 'deep_sweep' : 'fast_page'} backoffMs=${backoffDelayMs}`,
    );
  }

  private async runScheduledMapHistorySync() {
    try {
      const deepSweep = this.mapHistoryDeepSweepDueAt <= Date.now();
      await this.syncConfiguredStores({
        mode: deepSweep ? 'deep_sweep' : 'fast_page',
        maxPages: deepSweep ? this.globalSyncMaxPages() : 1,
      });
    } catch (error) {
      this.logger.warn(
        `Scheduled MAP history sync failed: ${this.safeError(error).slice(0, 500)}`,
      );
    } finally {
      this.scheduleNextMapHistorySync();
    }
  }

  private scheduleNextEfastSync() {
    if (this.efastSyncStopped || !this.isEfastSyncEnabled()) return;
    const delayMs = this.nextEfastSyncDelayMs();
    if (this.efastSyncTimer) {
      clearTimeout(this.efastSyncTimer);
    }
    this.efastSyncTimer = setTimeout(() => {
      void this.runScheduledEfastSync();
    }, delayMs);
    this.efastSyncTimer.unref?.();
    this.logger.debug(`Next VietinBank eFAST sync scheduled in ${delayMs}ms`);
  }

  private async runScheduledEfastSync() {
    try {
      const inFastWindow = this.isWithinEfastFastSyncWindow();
      if (this.lastEfastSyncWindowOpen !== inFastWindow) {
        this.logger.log(
          inFastWindow
            ? 'VietinBank eFAST sync fast cadence active'
            : 'VietinBank eFAST sync night cadence active',
        );
      }
      this.lastEfastSyncWindowOpen = inFastWindow;
      if (this.efastSyncInProgress) return;
      this.efastSyncInProgress = true;
      try {
        await this.syncEfastTransactions();
      } finally {
        this.efastSyncInProgress = false;
      }
    } catch (error) {
      this.logger.warn(
        `Scheduled VietinBank eFAST sync failed: ${this.safeError(error).slice(0, 500)}`,
      );
    } finally {
      this.scheduleNextEfastSync();
    }
  }

  private randomMapHistorySyncDelayMs() {
    const configuredMin = this.readPositiveInt(
      'MAP_VIETIN_SYNC_DELAY_MIN_MS',
      DEFAULT_MAP_HISTORY_SYNC_DELAY_MIN_MS,
    );
    const configuredMax = this.readPositiveInt(
      'MAP_VIETIN_SYNC_DELAY_MAX_MS',
      DEFAULT_MAP_HISTORY_SYNC_DELAY_MAX_MS,
    );
    const min = Math.max(MIN_MAP_HISTORY_SYNC_DELAY_MS, configuredMin);
    const max = Math.max(min, configuredMax);
    const span = max - min;
    return min + Math.floor(Math.random() * (span + 1));
  }

  private randomMapDeepSweepDelayMs() {
    const configuredMin = this.readPositiveInt(
      'MAP_VIETIN_DEEP_SWEEP_DELAY_MIN_MS',
      DEFAULT_MAP_DEEP_SWEEP_DELAY_MIN_MS,
    );
    const configuredMax = this.readPositiveInt(
      'MAP_VIETIN_DEEP_SWEEP_DELAY_MAX_MS',
      DEFAULT_MAP_DEEP_SWEEP_DELAY_MAX_MS,
    );
    const min = Math.max(MIN_MAP_DEEP_SWEEP_DELAY_MS, configuredMin);
    const max = Math.max(min, configuredMax);
    return min + Math.floor(Math.random() * (max - min + 1));
  }

  private randomEfastFastSyncDelayMs() {
    const span = EFAST_FAST_SYNC_DELAY_MAX_MS - EFAST_FAST_SYNC_DELAY_MIN_MS;
    return (
      EFAST_FAST_SYNC_DELAY_MIN_MS + Math.floor(Math.random() * (span + 1))
    );
  }

  private nextMapHistorySyncDelayMs(value = new Date(Date.now())) {
    if (this.isWithinMapSyncWindow(value)) {
      return this.randomMapHistorySyncDelayMs();
    }
    return Math.min(
      MAP_HISTORY_SYNC_NIGHT_DELAY_MS,
      this.msUntilNextMapFastWindowStart(value),
    );
  }

  private nextEfastSyncDelayMs(value = new Date(Date.now())) {
    if (this.isWithinEfastFastSyncWindow(value)) {
      const fastDelay = this.randomEfastFastSyncDelayMs();
      const msUntilNight = this.msUntilEfastNightWindowStart(value);
      return msUntilNight <= fastDelay
        ? msUntilNight + EFAST_NIGHT_SYNC_DELAY_MS
        : fastDelay;
    }
    return Math.min(
      EFAST_NIGHT_SYNC_DELAY_MS,
      this.msUntilNextEfastFastWindowStart(value),
    );
  }

  private msUntilNextMapFastWindowStart(value: Date) {
    const vietnamTimeMs =
      value.getTime() + VIETNAM_UTC_OFFSET_HOURS * 60 * 60 * 1000;
    const vietnamDate = new Date(vietnamTimeMs);
    const startTodayVietnamMs = Date.UTC(
      vietnamDate.getUTCFullYear(),
      vietnamDate.getUTCMonth(),
      vietnamDate.getUTCDate(),
      MAP_SYNC_START_HOUR_VN,
      0,
      0,
      0,
    );
    const nextStartVietnamMs =
      vietnamTimeMs < startTodayVietnamMs
        ? startTodayVietnamMs
        : startTodayVietnamMs + ONE_DAY_MS;
    return Math.max(1, nextStartVietnamMs - vietnamTimeMs);
  }

  private msUntilNextEfastFastWindowStart(value: Date) {
    const vietnamTimeMs = this.vietnamTimeMs(value);
    const vietnamDate = new Date(vietnamTimeMs);
    const startTodayVietnamMs = Date.UTC(
      vietnamDate.getUTCFullYear(),
      vietnamDate.getUTCMonth(),
      vietnamDate.getUTCDate(),
      EFAST_SYNC_START_HOUR_VN,
      0,
      0,
      0,
    );
    const nextStartVietnamMs =
      vietnamTimeMs < startTodayVietnamMs
        ? startTodayVietnamMs
        : startTodayVietnamMs + ONE_DAY_MS;
    return Math.max(1, nextStartVietnamMs - vietnamTimeMs);
  }

  private msUntilEfastNightWindowStart(value: Date) {
    const vietnamTimeMs = this.vietnamTimeMs(value);
    const vietnamDate = new Date(vietnamTimeMs);
    const nightStartVietnamMs = Date.UTC(
      vietnamDate.getUTCFullYear(),
      vietnamDate.getUTCMonth(),
      vietnamDate.getUTCDate(),
      EFAST_SYNC_END_HOUR_VN,
      1,
      0,
      0,
    );
    return Math.max(1, nightStartVietnamMs - vietnamTimeMs);
  }

  private isMapHistorySyncDisabled() {
    return process.env.MAP_VIETIN_SYNC_ENABLED === 'false';
  }

  async syncConfiguredStores(options: MapGlobalSyncOptions = {}) {
    if (this.isMapHistorySyncDisabled()) return;
    if (this.mapProviderBackoffUntil > Date.now()) {
      this.logger.debug(
        `MAP sync skipped by provider backoff retryAt=${new Date(this.mapProviderBackoffUntil).toISOString()}`,
      );
      return;
    }
    const inFastWindow = this.isWithinMapSyncWindow();
    if (this.lastSyncWindowOpen !== inFastWindow) {
      this.logger.log(
        inFastWindow
          ? 'MAP sync fast cadence active'
          : 'MAP sync night cadence active',
      );
    }
    this.lastSyncWindowOpen = inFastWindow;
    if (this.syncInProgress) return;
    this.syncInProgress = true;
    try {
      if (this.shouldUseGlobalSync()) {
        await this.syncGlobalTransactions(options);
      } else {
        await this.syncPerStoreTransactions();
      }
    } finally {
      this.syncInProgress = false;
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
    const now = Date.now();
    const configuredCifno = this.efastCifno();
    if (
      !forceRefresh &&
      this.efastSessionCache?.username === username &&
      this.efastSessionCache.cifno === configuredCifno &&
      this.efastSessionCache.expiresAt > now
    ) {
      return this.efastSessionCache.session;
    }

    const session = await this.loginEfast(username, password, configuredCifno);
    this.efastSessionCache = {
      username,
      cifno: configuredCifno,
      session,
      expiresAt: now + this.efastSessionTtlSeconds() * 1000,
    };
    return session;
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
    const now = Date.now();
    if (
      !forceRefresh &&
      this.globalSessionCache?.username === username &&
      this.globalSessionCache.expiresAt > now
    ) {
      return this.globalSessionCache.session;
    }

    const session = await this.login(
      username,
      password,
      GLOBAL_SYNC_STATE_CODE,
    );
    this.globalSessionCache = {
      username,
      session,
      expiresAt: now + this.globalSessionTtlSeconds() * 1000,
    };
    return session;
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
      orderStatus === STATEMENT_ORDER_STATUS_OFFSET_CONFIRMED;

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
    await this.assertCanUseStatements(user);
    if (!storeCode) return this.canReadUnassignedStatementTransactions(user);
    if (await this.hasNationalStatementScope(user)) return true;
    const stores = await this.resolveUserStores(user);
    return stores.some((store) => store.storeId === storeCode);
  }

  private async canReadUnassignedStatementTransactions(user: any) {
    await this.assertCanUseStatements(user);
    if (String(user?.role || '').toUpperCase() === 'SUPER_ADMIN') return true;
    if (this.isPhongVuEmail(user?.email)) return true;
    return this.userMatchesStatementAccessCodes(user, [
      FIN_ACC_DEPARTMENT_CODE,
    ]);
  }

  private async resolveStatementActionScope(user: any) {
    await this.assertCanUseStatements(user);
    if (await this.hasNationalStatementScope(user)) {
      return {
        allStores: true,
        storeCodes: [] as string[],
        includeUnassigned: true,
      };
    }
    const stores = await this.resolveUserStores(user);
    return {
      allStores: false,
      storeCodes: stores.map((store) => store.storeId),
      includeUnassigned:
        await this.canReadUnassignedStatementTransactions(user),
    };
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
    if (
      await this.policyService.canAccessPolicy(
        user,
        ADMIN_POLICY_CODES.BANK_STATEMENTS,
      )
    ) {
      return true;
    }
    if (
      await this.featureService.canAccessFeature(
        user,
        FEATURE_KEYS.BANK_STATEMENTS,
      )
    ) {
      return true;
    }
    return this.hasNationalStatementScope(user);
  }

  private async assertCanUseStatements(user: any) {
    if (await this.canUseStatements(user)) {
      return;
    }
    throw new ForbiddenException('Không có quyền xem sao kê');
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
    return this.userMatchesStatementAccessCodes(user, [
      FIN_ACC_DEPARTMENT_CODE,
    ]);
  }

  private async canEditStatementIncomeType(user: any): Promise<boolean> {
    return this.userBelongsToStatementAccessCodes(user, [
      FIN_ACC_DEPARTMENT_CODE,
    ]);
  }

  private async canReviewStatementOrderTransferRequests(
    user: any,
  ): Promise<boolean> {
    return this.userMatchesStatementAccessCodes(user, [
      FIN_ACC_DEPARTMENT_CODE,
      ACC_DEPARTMENT_CODE,
    ]);
  }

  private async assertCanReviewStatementOrderTransferRequests(user: any) {
    await this.assertCanUseStatements(user);
    if (await this.canReviewStatementOrderTransferRequests(user)) return;
    throw new ForbiddenException('Bạn không có quyền xác nhận cấn trừ.');
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
    if (this.isStatementOrderTransferWindowOpen(row)) return;
    throw new BadRequestException(ORDER_TRANSFER_WINDOW_FORBIDDEN_MESSAGE);
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
    let releaseQueue!: () => void;
    const previous = this.mapPersistenceQueue;
    this.mapPersistenceQueue = new Promise<void>((resolve) => {
      releaseQueue = resolve;
    });
    await previous;
    try {
      return await this.persistTransactionsUnlocked(storeCode, rows, stats);
    } finally {
      releaseQueue();
    }
  }

  private async persistTransactionsUnlocked(
    storeCode: string | null,
    rows: unknown[],
    stats: MapPersistStats,
  ) {
    let created = 0;
    let withOrders = 0;
    let withoutOrders = 0;
    let manualProtected = 0;
    let offsetProtected = 0;
    let manualIncomeTypeProtected = 0;
    let duplicateStatementSkipped = 0;
    let duplicateFingerprintSkipped = 0;
    let salesIncome = 0;
    let partnerInternalIncome = 0;
    for (const raw of rows) {
      if (!raw || typeof raw !== 'object') continue;
      const row = raw as MapTransactionRow;
      const normalized = this.normalizeTransaction(storeCode, row);
      if (!normalized) continue;
      if (normalized.incomeType === MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL) {
        partnerInternalIncome += 1;
      } else {
        salesIncome += 1;
      }
      const syncFingerprint = this.mapSyncFingerprint(normalized);
      if (
        this.mapSyncFingerprintCacheHit(
          normalized.transactionKey,
          syncFingerprint,
        )
      ) {
        stats.unchanged += 1;
        stats.cacheHits += 1;
        continue;
      }
      let existing = await this.prisma.mapVietinTransaction.findUnique({
        where: { transactionKey: normalized.transactionKey },
      });
      if (!existing) {
        const legacyTransactionKey = this.legacyTransactionKeyForRow(
          storeCode,
          row,
        );
        if (legacyTransactionKey !== normalized.transactionKey) {
          existing = await this.prisma.mapVietinTransaction.findUnique({
            where: { transactionKey: legacyTransactionKey },
          });
        }
      }
      if (!existing) {
        const existingStatement = await this.findExistingTransactionByStatement(
          normalized.transactionKey,
          row,
        );
        if (existingStatement) {
          duplicateStatementSkipped += 1;
          this.rememberMapSyncFingerprint(
            normalized.transactionKey,
            syncFingerprint,
          );
          continue;
        }
        const existingFingerprint =
          await this.findExistingTransactionByBankFingerprint(
            normalized.transactionKey,
            normalized,
            row,
          );
        if (existingFingerprint) {
          duplicateFingerprintSkipped += 1;
          this.logger.warn(
            `MAP sync duplicate skipped by bank fingerprint: incoming=${normalized.transactionKey} existing=${existingFingerprint.transactionKey} store=${normalized.storeCode || 'null'} source=${this.isEfastMapTransactionRow(row) ? 'VIETIN_EFAST' : 'MAP'}`,
          );
          this.rememberMapSyncFingerprint(
            normalized.transactionKey,
            syncFingerprint,
          );
          continue;
        }
      }
      if (normalized.orders.length > 0) {
        withOrders += 1;
      } else {
        withoutOrders += 1;
      }
      if (!existing) created += 1;
      const preservesProtectedOrders =
        existing?.orderSource === ORDER_SOURCE_MANUAL ||
        existing?.orderSource === ORDER_SOURCE_OFFSET;
      const preservesManualIncomeType =
        existing?.incomeTypeSource === INCOME_TYPE_SOURCE_MANUAL;
      if (preservesManualIncomeType) manualIncomeTypeProtected += 1;
      if (existing?.orderSource === ORDER_SOURCE_MANUAL) manualProtected += 1;
      if (existing?.orderSource === ORDER_SOURCE_OFFSET) offsetProtected += 1;
      const updateData = {
        transactionNumber: normalized.transactionNumber,
        amount: normalized.amount,
        content: normalized.content,
        ...(preservesManualIncomeType
          ? {}
          : {
              incomeType: normalized.incomeType,
              incomeTypeSource: INCOME_TYPE_SOURCE_AUTO,
            }),
        ...(preservesProtectedOrders
          ? {}
          : {
              orders: normalized.orders,
              orderSource: ORDER_SOURCE_AUTO,
            }),
        status: normalized.status,
        paidAt: normalized.paidAt,
        payerName: normalized.payerName,
        payerAccount: normalized.payerAccount,
        rawData: normalized.rawData,
      };
      const isNoOp =
        existing && this.mapTransactionSyncIsNoOp(existing, updateData);
      const stored = isNoOp
        ? existing
        : await this.prisma.mapVietinTransaction.upsert({
            where: {
              transactionKey:
                existing?.transactionKey ?? normalized.transactionKey,
            },
            create: normalized,
            update: updateData,
          });
      if (isNoOp) {
        stats.unchanged += 1;
      } else if (existing) {
        stats.updated += 1;
      }
      this.rememberMapSyncFingerprint(
        normalized.transactionKey,
        syncFingerprint,
      );
      if (
        !existing &&
        stored?.id &&
        stored.storeCode &&
        this.paymentNotifications
      ) {
        const storedWithStore = stored as typeof stored & { storeCode: string };
        void this.paymentNotifications
          .createForTransaction(storedWithStore)
          .catch((error) => {
            this.logger.warn(
              `Payment notification failed for ${stored.id}: ${this.safeError(error)}`,
            );
          });
      }
    }
    if (
      created > 0 ||
      stats.updated > 0 ||
      duplicateStatementSkipped > 0 ||
      duplicateFingerprintSkipped > 0
    ) {
      const storeLabel = storeCode || 'null';
      this.logger.log(
        `MAP sync order extraction: store=${storeLabel} created=${created} updated=${stats.updated} unchanged=${stats.unchanged} withOrders=${withOrders} withoutOrders=${withoutOrders} salesIncome=${salesIncome} partnerInternalIncome=${partnerInternalIncome} manualProtected=${manualProtected} offsetProtected=${offsetProtected} manualIncomeTypeProtected=${manualIncomeTypeProtected} duplicateStatementSkipped=${duplicateStatementSkipped} duplicateFingerprintSkipped=${duplicateFingerprintSkipped}`,
      );
    }
    return created;
  }

  private mapTransactionSyncIsNoOp(
    existing: Record<string, unknown>,
    updateData: Record<string, unknown>,
  ) {
    return Object.entries(updateData).every(([key, value]) =>
      this.mapSyncValueEquals(existing[key], value),
    );
  }

  private mapSyncValueEquals(left: unknown, right: unknown): boolean {
    if (left instanceof Date || right instanceof Date) {
      if (!(left instanceof Date) || !(right instanceof Date)) return false;
      return left.getTime() === right.getTime();
    }
    if (Array.isArray(left) || Array.isArray(right)) {
      if (!Array.isArray(left) || !Array.isArray(right)) return false;
      if (left.length !== right.length) return false;
      return left.every((value, index) =>
        this.mapSyncValueEquals(value, right[index]),
      );
    }
    if (
      left !== null &&
      right !== null &&
      typeof left === 'object' &&
      typeof right === 'object'
    ) {
      return this.stableJson(left) === this.stableJson(right);
    }
    return left === right;
  }

  private stableJson(value: unknown): string {
    const normalize = (input: unknown): unknown => {
      if (Array.isArray(input)) return input.map(normalize);
      if (input && typeof input === 'object') {
        return Object.fromEntries(
          Object.entries(input as Record<string, unknown>)
            .sort(([left], [right]) => left.localeCompare(right))
            .map(([key, nested]) => [key, normalize(nested)]),
        );
      }
      return input;
    };
    return JSON.stringify(normalize(value));
  }

  private mapSyncFingerprint(normalized: Record<string, unknown>) {
    return createHash('sha256')
      .update(this.stableJson(normalized))
      .digest('hex');
  }

  private mapSyncFingerprintCacheHit(key: string, fingerprint: string) {
    const cached = this.mapSyncFingerprintCache.get(key);
    if (!cached) return false;
    if (cached.expiresAt <= Date.now() || cached.fingerprint !== fingerprint) {
      this.mapSyncFingerprintCache.delete(key);
      return false;
    }
    // Map giữ thứ tự chèn; đưa entry vừa dùng xuống cuối để có LRU giới hạn.
    this.mapSyncFingerprintCache.delete(key);
    this.mapSyncFingerprintCache.set(key, cached);
    return true;
  }

  private rememberMapSyncFingerprint(key: string, fingerprint: string) {
    const maxEntries = Math.min(
      MAX_MAP_SYNC_FINGERPRINT_CACHE_ENTRIES,
      this.readPositiveInt(
        'MAP_VIETIN_SYNC_FINGERPRINT_CACHE_MAX_ENTRIES',
        DEFAULT_MAP_SYNC_FINGERPRINT_CACHE_MAX_ENTRIES,
      ),
    );
    while (this.mapSyncFingerprintCache.size >= maxEntries) {
      const oldestKey = this.mapSyncFingerprintCache.keys().next().value as
        | string
        | undefined;
      if (!oldestKey) break;
      this.mapSyncFingerprintCache.delete(oldestKey);
    }
    this.mapSyncFingerprintCache.set(key, {
      fingerprint,
      expiresAt:
        Date.now() +
        this.readPositiveInt(
          'MAP_VIETIN_SYNC_FINGERPRINT_CACHE_TTL_MS',
          DEFAULT_MAP_SYNC_FINGERPRINT_CACHE_TTL_MS,
        ),
    });
  }

  private async findExistingTransactionByStatement(
    transactionKey: string,
    row: MapTransactionRow,
  ) {
    const identifiers = this.statementIdentifiersForRow(row);
    if (identifiers.length === 0) return null;
    const referenceWhere = identifiers.flatMap((identifier) => [
      { transactionNumber: identifier },
      {
        rawData: {
          path: ['txnReference'],
          equals: identifier,
        },
      },
      {
        rawData: {
          path: ['trxId'],
          equals: identifier,
        },
      },
      {
        rawData: {
          path: ['trxRefNo'],
          equals: identifier,
        },
      },
    ]);
    return this.prisma.mapVietinTransaction.findFirst({
      where: {
        transactionKey: { not: transactionKey },
        OR: referenceWhere,
      },
      select: { id: true, transactionKey: true, storeCode: true },
    });
  }

  private async findExistingTransactionByBankFingerprint(
    transactionKey: string,
    normalized: {
      storeCode: string | null;
      amount: number;
      content: string;
      paidAt: Date | null;
    },
    row: MapTransactionRow,
  ) {
    if (
      !normalized.storeCode ||
      !normalized.paidAt ||
      !normalized.content.trim()
    ) {
      return null;
    }
    const incomingIsEfast = this.isEfastMapTransactionRow(row);
    const candidates = await this.prisma.mapVietinTransaction.findMany({
      where: {
        transactionKey: { not: transactionKey },
        storeCode: normalized.storeCode,
        amount: normalized.amount,
        paidAt: normalized.paidAt,
        content: normalized.content,
      },
      select: {
        id: true,
        transactionKey: true,
        storeCode: true,
        rawData: true,
      },
      take: 5,
    });
    return (
      candidates.find((candidate) => {
        const candidateRaw = this.rawDataAsMapRow(candidate.rawData);
        const candidateIsEfast = candidateRaw
          ? this.isEfastMapTransactionRow(candidateRaw)
          : false;
        return candidateIsEfast !== incomingIsEfast;
      }) || null
    );
  }

  private async persistGlobalTransactions(
    rows: unknown[],
    storeAccountIndex: Map<string, string[]>,
  ) {
    let created = 0;
    let updated = 0;
    let unchanged = 0;
    let cacheHits = 0;
    let quarantined = 0;
    let sourceAccountMapped = 0;
    for (const raw of rows) {
      if (!raw || typeof raw !== 'object') continue;
      const row = raw as MapTransactionRow;
      const amount = this.readAmount(row);
      if (!amount || amount <= 0) continue;
      if (!this.isSuccessfulTransaction(row)) continue;

      const virtualAccount = this.resolveGlobalVirtualAccount(row);
      const sourceAccount = this.resolveEfastSourceAccount(row);
      const accountCandidates = this.isEfastMapTransactionRow(row)
        ? [
            { value: virtualAccount, sourceAccount: false },
            { value: sourceAccount, sourceAccount: true },
          ]
        : [{ value: virtualAccount, sourceAccount: false }];
      let accountKey = '';
      let accountValue = '';
      let storeCodes: string[] = [];
      let matchedBySourceAccount = false;
      for (const candidate of accountCandidates) {
        const candidateKey = this.normalizeAccountNumber(candidate.value);
        if (!candidateKey) continue;
        if (!accountKey) {
          accountKey = candidateKey;
          accountValue = candidate.value;
        }
        const candidateStoreCodes = storeAccountIndex.get(candidateKey) || [];
        if (candidateStoreCodes.length === 0) continue;
        accountKey = candidateKey;
        accountValue = candidate.value;
        storeCodes = candidateStoreCodes;
        matchedBySourceAccount = candidate.sourceAccount;
        break;
      }

      if (storeCodes.length === 0) {
        if (
          this.isEfastMapTransactionRow(row) &&
          !this.normalizeAccountNumber(virtualAccount)
        ) {
          const stats: MapPersistStats = {
            updated: 0,
            unchanged: 0,
            cacheHits: 0,
          };
          created += await this.persistTransactions(null, [row], stats);
          updated += stats.updated;
          unchanged += stats.unchanged;
          cacheHits += stats.cacheHits;
          continue;
        }
        if (accountKey) {
          await this.quarantineGlobalTransaction(
            row,
            'UNMAPPED_ACCOUNT',
            accountValue,
          );
          quarantined += 1;
          continue;
        }
        await this.quarantineGlobalTransaction(
          row,
          'MISSING_VIRTUAL_ACCOUNT',
          virtualAccount,
        );
        quarantined += 1;
        continue;
      }
      if (storeCodes.length > 1) {
        await this.quarantineGlobalTransaction(
          row,
          'AMBIGUOUS_ACCOUNT',
          accountValue,
        );
        quarantined += 1;
        continue;
      }
      if (matchedBySourceAccount) sourceAccountMapped += 1;

      const stats: MapPersistStats = {
        updated: 0,
        unchanged: 0,
        cacheHits: 0,
      };
      created += await this.persistTransactions(storeCodes[0], [row], stats);
      updated += stats.updated;
      unchanged += stats.unchanged;
      cacheHits += stats.cacheHits;
    }
    return {
      created,
      updated,
      unchanged,
      cacheHits,
      quarantined,
      sourceAccountMapped,
    };
  }

  private async quarantineGlobalTransaction(
    row: MapTransactionRow,
    reason: UnmappedReason,
    virtualAccount: string,
  ) {
    const amount = this.readAmount(row);
    const content = this.readFirstText(row, this.contentKeys);
    const transactionNumber = this.readFirstText(
      row,
      this.transactionNumberKeys,
    );
    const paidAt = this.readTransactionTime(row);
    const status = this.readFirstText(row, this.statusKeys);
    const payerName = this.readFirstText(row, this.payerNameKeys);
    const payerAccount = this.readFirstText(row, this.payerAccountKeys);
    const fallback = [
      virtualAccount,
      transactionNumber,
      amount ?? '',
      paidAt?.toISOString() ?? '',
      content,
    ].join('|');
    const hash = createHash('sha256')
      .update(`${reason}|${fallback}`)
      .digest('hex');
    const unmappedKey = `${reason}:${hash}`;

    await this.prisma.mapVietinUnmappedTransaction.upsert({
      where: { unmappedKey },
      create: {
        unmappedKey,
        virtualAccount: virtualAccount || null,
        reason,
        transactionNumber: transactionNumber || null,
        amount,
        content,
        status: status || null,
        paidAt,
        payerName: payerName || null,
        payerAccount: payerAccount || null,
        rawData: this.scrubJson(row) as Prisma.InputJsonObject,
      },
      update: {
        virtualAccount: virtualAccount || null,
        reason,
        transactionNumber: transactionNumber || null,
        amount,
        content,
        status: status || null,
        paidAt,
        payerName: payerName || null,
        payerAccount: payerAccount || null,
        rawData: this.scrubJson(row) as Prisma.InputJsonObject,
      },
    });
    this.logger.warn(
      `Global MAP transaction quarantined: ${reason} virtualAccount=${this.maskAccount(virtualAccount)}`,
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

  private statementIdentifiersForRow(row: MapTransactionRow) {
    const seen = new Set<string>();
    const output: string[] = [];
    const candidates = [
      this.readFirstText(row, this.transactionNumberKeys),
      this.readFirstText(row, this.transactionReferenceKeys),
      this.readText(row, 'trxId'),
      this.readText(row, 'trxRefNo'),
      this.readText(row, 'numberOrder'),
    ];
    for (const candidate of candidates) {
      const value = this.cleanText(candidate);
      if (!value || seen.has(value)) continue;
      seen.add(value);
      output.push(value);
    }
    return output;
  }

  private canonicalStatementIdentifierForRow(row: MapTransactionRow) {
    const candidates = this.isEfastMapTransactionRow(row)
      ? [
          this.readText(row, 'trxId'),
          this.readFirstText(row, this.transactionNumberKeys),
          this.readText(row, 'trxRefNo'),
          this.readFirstText(row, this.transactionReferenceKeys),
        ]
      : [
          this.readText(row, 'txnReference'),
          this.readText(row, 'trxId'),
          this.readText(row, 'trxRefNo'),
          this.readFirstText(row, this.transactionNumberKeys),
        ];
    for (const candidate of candidates) {
      const value = this.cleanText(candidate).toUpperCase();
      if (value) return value;
    }
    return '';
  }

  private legacyTransactionKeyForRow(
    storeCode: string | null,
    row: MapTransactionRow,
  ) {
    const transactionNumber = this.readFirstText(
      row,
      this.transactionNumberKeys,
    );
    const amount = this.readAmount(row) ?? 0;
    const paidAt = this.readTransactionTime(row);
    const content = this.readFirstText(row, this.contentKeys);
    const fallback = [
      transactionNumber,
      amount,
      paidAt?.toISOString() ?? '',
      content,
    ].join('|');
    const storeKey = storeCode || '__NO_STORE__';
    const hash = createHash('sha256')
      .update(`${storeKey}|${fallback}`)
      .digest('hex');
    return `${storeKey}:${hash}`;
  }

  private transactionKeyForIdentity(
    storeCode: string | null,
    identity: string,
  ) {
    const storeKey = storeCode || '__NO_STORE__';
    const hash = createHash('sha256')
      .update(`${storeKey}|${identity}`)
      .digest('hex');
    return `${storeKey}:${hash}`;
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
    const stores = (await this.prisma.store.findMany({
      where: { transferAccountNumber: { not: null } },
      select: { storeId: true, transferAccountNumber: true },
    })) as StoreAccountRow[];
    const index = new Map<string, string[]>();
    for (const store of stores) {
      const accountKey = this.normalizeAccountNumber(
        store.transferAccountNumber || '',
      );
      if (!accountKey) continue;
      const storeCodes = index.get(accountKey) || [];
      if (!storeCodes.includes(store.storeId)) storeCodes.push(store.storeId);
      index.set(accountKey, storeCodes);
    }
    return index;
  }

  private async reassignUnassignedEfastTransactions(
    storeAccountIndex: Map<string, string[]>,
  ) {
    let remapped = 0;
    let uniqueAccountCount = 0;
    for (const [accountKey, storeCodes] of storeAccountIndex.entries()) {
      if (storeCodes.length !== 1) continue;
      uniqueAccountCount += 1;
      const result = await this.prisma.mapVietinTransaction.updateMany({
        where: {
          storeCode: null,
          AND: [
            {
              rawData: {
                path: ['source'],
                equals: 'VIETIN_EFAST',
              },
            },
            {
              OR: [
                {
                  rawData: {
                    path: ['efastCreditAccountNo'],
                    equals: accountKey,
                  },
                },
                {
                  rawData: {
                    path: ['efastBankAccountNo'],
                    equals: accountKey,
                  },
                },
              ],
            },
          ],
        },
        data: { storeCode: storeCodes[0] },
      });
      remapped += result.count;
    }
    if (remapped > 0) {
      this.logger.log(
        `VietinBank eFAST account remap completed: uniqueAccounts=${uniqueAccountCount} remapped=${remapped}`,
      );
    }
    return remapped;
  }

  private normalizeTransaction(
    storeCode: string | null,
    row: MapTransactionRow,
  ) {
    const amount = this.readAmount(row);
    if (!amount || amount <= 0) return null;
    if (!this.isSuccessfulTransaction(row)) return null;
    const content = this.readFirstText(row, this.contentKeys);
    const transactionNumber = this.readFirstText(
      row,
      this.transactionNumberKeys,
    );
    const paidAt = this.readTransactionTime(row);
    const status = this.readFirstText(row, this.statusKeys);
    const payerName = this.readFirstText(row, this.payerNameKeys);
    const payerAccount = this.readFirstText(row, this.payerAccountKeys);
    const orders = this.extractOrderCodesFromContent(content);
    const canonicalStatementIdentifier =
      this.canonicalStatementIdentifierForRow(row);
    const fallback = [
      transactionNumber,
      amount,
      paidAt?.toISOString() ?? '',
      content,
    ].join('|');
    const identity = canonicalStatementIdentifier
      ? `STATEMENT|${canonicalStatementIdentifier}`
      : `FALLBACK|${fallback}`;

    return {
      storeCode,
      transactionKey: this.transactionKeyForIdentity(storeCode, identity),
      transactionNumber: transactionNumber || null,
      amount,
      content,
      orders,
      orderSource: ORDER_SOURCE_AUTO,
      status: status || null,
      paidAt,
      payerName: payerName || null,
      payerAccount: payerAccount || null,
      incomeType: classifyMapVietinIncomeType(content, payerAccount),
      incomeTypeSource: INCOME_TYPE_SOURCE_AUTO,
      rawData: row as Prisma.InputJsonObject,
    };
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
    row: {
      id: string;
      storeCode: string | null;
      transactionKey: string;
      transactionNumber: string | null;
      amount: number;
      content: string;
      orders?: string[] | null;
      orderSource?: string | null;
      orderUpdatedAt?: Date | null;
      orderUpdatedByUserId?: string | null;
      orderUpdatedByEmail?: string | null;
      status: string | null;
      paidAt: Date | null;
      payerName: string | null;
      payerAccount: string | null;
      incomeType?: string | null;
      incomeTypeSource?: string | null;
      incomeTypeUpdatedAt?: Date | null;
      incomeTypeUpdatedByUserId?: string | null;
      incomeTypeUpdatedByEmail?: string | null;
      rawData?: Prisma.JsonValue | null;
      firstSeenAt: Date;
      orderTransferRequests?: Array<{
        id: string;
        requestedOrders: string[];
        status: string;
        requestedByUserId?: string | null;
        requestedByEmail?: string | null;
        reviewNote?: string | null;
        createdAt: Date;
      }>;
    },
    options: {
      canEditProtectedOrders?: boolean;
      canUseStatements?: boolean;
      canEditIncomeType?: boolean;
    } = {},
  ) {
    const payer = this.resolveStoredPayer(row);
    const incomeType = this.storedIncomeType(row);
    const orders = row.orders || [];
    const pendingTransferRequest = row.orderTransferRequests?.[0] || null;
    const canUseStatements = options.canUseStatements !== false;
    const transferWindowOpen = this.isStatementOrderTransferWindowOpen(row);
    const hasStoreCode = Boolean(row.storeCode);
    const canEditOrders =
      canUseStatements &&
      !pendingTransferRequest &&
      (orders.length === 0 || options.canEditProtectedOrders === true);
    let orderEditBlockedReason: string | null = null;
    if (!canEditOrders) {
      orderEditBlockedReason = !canUseStatements
        ? ORDER_ACTION_REQUIRES_STATEMENT_PERMISSION_MESSAGE
        : pendingTransferRequest
          ? 'Giao dịch đang chờ Kế toán xác nhận.'
          : ORDER_EDIT_FORBIDDEN_MESSAGE;
    }
    const canRequestOrderTransfer =
      canUseStatements &&
      hasStoreCode &&
      !pendingTransferRequest &&
      transferWindowOpen;
    let orderTransferBlockedReason: string | null = null;
    if (!canRequestOrderTransfer) {
      orderTransferBlockedReason = pendingTransferRequest
        ? 'Giao dịch đang chờ Kế toán xác nhận.'
        : !hasStoreCode
          ? 'Giao dịch chưa có showroom nên không tạo yêu cầu cấn trừ.'
          : !canUseStatements
            ? ORDER_ACTION_REQUIRES_STATEMENT_PERMISSION_MESSAGE
            : ORDER_TRANSFER_WINDOW_FORBIDDEN_MESSAGE;
    }
    return {
      id: row.id,
      storeId: row.storeCode,
      transactionKey: row.transactionKey,
      transactionNumber: row.transactionNumber,
      transactionReference: this.resolveStoredTransactionReference(row),
      amount: row.amount,
      content: row.content,
      orders,
      orderSource: row.orderSource || null,
      orderUpdatedAt: row.orderUpdatedAt || null,
      orderUpdatedByUserId: row.orderUpdatedByUserId || null,
      orderUpdatedByEmail: row.orderUpdatedByEmail || null,
      canEditOrders,
      orderEditBlockedReason,
      canRequestOrderTransfer,
      orderTransferRequestBlockedReason: orderTransferBlockedReason,
      hasPendingOrderTransferRequest: Boolean(pendingTransferRequest),
      orderTransferRequestId: pendingTransferRequest?.id || null,
      orderTransferRequestedOrders:
        pendingTransferRequest?.requestedOrders || [],
      orderTransferRequestedByUserId:
        pendingTransferRequest?.requestedByUserId || null,
      orderTransferRequestedByEmail:
        pendingTransferRequest?.requestedByEmail || null,
      orderTransferRequestedAt: pendingTransferRequest?.createdAt || null,
      orderTransferReviewNote: pendingTransferRequest?.reviewNote || null,
      orderTransferStatus: pendingTransferRequest
        ? STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_PENDING
        : row.orderSource === ORDER_SOURCE_OFFSET
          ? STATEMENT_ORDER_TRANSFER_REQUEST_STATUS_APPROVED
          : null,
      isOrderOffsetConfirmed: row.orderSource === ORDER_SOURCE_OFFSET,
      status: row.status,
      paidAt: row.paidAt,
      payerName: payer.name,
      payerAccount: payer.account,
      receivingAccount: this.resolveStoredReceivingAccount(row),
      incomeType,
      incomeTypeLabel: mapVietinIncomeTypeLabel(incomeType),
      incomeTypeSource: row.incomeTypeSource || INCOME_TYPE_SOURCE_AUTO,
      incomeTypeUpdatedAt: row.incomeTypeUpdatedAt || null,
      incomeTypeUpdatedByUserId: row.incomeTypeUpdatedByUserId || null,
      incomeTypeUpdatedByEmail: row.incomeTypeUpdatedByEmail || null,
      canEditIncomeType: canUseStatements && options.canEditIncomeType === true,
      firstSeenAt: row.firstSeenAt,
    };
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
    const rawData = this.rawDataAsMapRow(row.rawData);
    if (!rawData) return row.transactionNumber?.trim() || null;
    if (this.isEfastMapTransactionRow(rawData)) {
      return (
        this.firstNonEmptyText(
          this.readText(rawData, 'trxId'),
          row.transactionNumber,
          this.readText(rawData, 'transactionNumber'),
          this.readText(rawData, 'trxRefNo'),
          this.readText(rawData, 'txnReference'),
        ) || null
      );
    }
    return (
      this.readFirstText(rawData, this.transactionReferenceKeys) ||
      row.transactionNumber?.trim() ||
      null
    );
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
    return classifyMapVietinIncomeType(
      row.content,
      row.payerAccount,
    );
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

  private isWithinMapSyncWindow(value = new Date(Date.now())) {
    const vietnamHour = (value.getUTCHours() + VIETNAM_UTC_OFFSET_HOURS) % 24;
    return (
      vietnamHour >= MAP_SYNC_START_HOUR_VN &&
      vietnamHour < MAP_SYNC_END_HOUR_VN
    );
  }

  private isWithinEfastFastSyncWindow(value = new Date(Date.now())) {
    const vietnamDate = new Date(this.vietnamTimeMs(value));
    const minutes =
      vietnamDate.getUTCHours() * 60 + vietnamDate.getUTCMinutes();
    return (
      minutes >= EFAST_SYNC_START_HOUR_VN * 60 &&
      minutes <= EFAST_SYNC_END_HOUR_VN * 60
    );
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
    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      this.providerTimeoutMs(),
    );
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...headers,
        },
        body: JSON.stringify(body),
        redirect: 'manual',
        signal: controller.signal,
      });

      if (response.status >= 300 && response.status < 400) {
        throw new BadGatewayException(
          `${providerLabel} chuyển hướng ngoài dự kiến`,
        );
      }

      let responseBuffer: Buffer;
      try {
        responseBuffer = await readBoundedHttpResponse(
          response,
          this.providerResponseMaxBytes(),
        );
      } catch (error) {
        if (error instanceof HttpResponseTooLargeError) {
          throw new BadGatewayException(
            `${providerLabel} trả dữ liệu vượt giới hạn an toàn`,
          );
        }
        throw error;
      }
      const text = responseBuffer.toString('utf8');
      const json = text ? this.parseJson(text, providerLabel) : {};

      if (!response.ok) {
        throw new BankProviderHttpException(
          response.status,
          providerLabel,
          this.safeProviderMessage(json),
          this.retryAfterMs(response.headers?.get?.('retry-after')),
        );
      }
      return json as T;
    } finally {
      clearTimeout(timeout);
    }
  }

  private providerTimeoutMs() {
    return this.readPositiveInt(
      'BANK_PROVIDER_TIMEOUT_MS',
      DEFAULT_PROVIDER_TIMEOUT_MS,
    );
  }

  private providerResponseMaxBytes() {
    return this.readPositiveInt(
      'BANK_PROVIDER_RESPONSE_MAX_BYTES',
      DEFAULT_PROVIDER_RESPONSE_MAX_BYTES,
    );
  }

  private readPositiveInt(name: string, fallback: number) {
    const parsed = Number(process.env[name]);
    return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
  }

  private registerMapProviderBackoff(
    providerStatus: 403 | 429,
    providerRetryAfterMs?: number,
  ) {
    this.mapProviderBackoffAttempt += 1;
    const jitterMs = Math.floor(
      Math.random() * (MAP_PROVIDER_BACKOFF_JITTER_MAX_MS + 1),
    );
    let delayMs: number;
    if (providerStatus === 403) {
      delayMs =
        Math.max(
          DEFAULT_MAP_FORBIDDEN_BACKOFF_MS,
          this.readPositiveInt(
            'MAP_VIETIN_FORBIDDEN_BACKOFF_MS',
            DEFAULT_MAP_FORBIDDEN_BACKOFF_MS,
          ),
        ) + jitterMs;
    } else {
      const baseMs = Math.max(
        DEFAULT_MAP_RATE_LIMIT_BACKOFF_BASE_MS,
        this.readPositiveInt(
          'MAP_VIETIN_RATE_LIMIT_BACKOFF_BASE_MS',
          DEFAULT_MAP_RATE_LIMIT_BACKOFF_BASE_MS,
        ),
      );
      const maxMs = Math.max(
        baseMs,
        this.readPositiveInt(
          'MAP_VIETIN_RATE_LIMIT_BACKOFF_MAX_MS',
          DEFAULT_MAP_RATE_LIMIT_BACKOFF_MAX_MS,
        ),
      );
      const exponent = Math.min(this.mapProviderBackoffAttempt - 1, 10);
      delayMs = Math.min(maxMs, baseMs * 2 ** exponent) + jitterMs;
    }
    const safeProviderRetryAfterMs = Math.min(
      MAP_PROVIDER_RETRY_AFTER_MAX_MS,
      Math.max(0, providerRetryAfterMs ?? 0),
    );
    delayMs = Math.max(delayMs, safeProviderRetryAfterMs);
    this.mapProviderBackoffUntil = Date.now() + delayMs;
    this.logger.warn(
      `MAP provider backoff activated status=${providerStatus} attempt=${this.mapProviderBackoffAttempt} delayMs=${delayMs} retryAt=${new Date(this.mapProviderBackoffUntil).toISOString()}`,
    );
  }

  private clearMapProviderBackoff() {
    if (this.mapProviderBackoffAttempt > 0) {
      this.logger.log(
        `MAP provider recovered after backoff attempts=${this.mapProviderBackoffAttempt}`,
      );
    }
    this.mapProviderBackoffAttempt = 0;
    this.mapProviderBackoffUntil = 0;
  }

  private retryAfterMs(value?: string | null) {
    const normalized = String(value || '').trim();
    if (!normalized) return undefined;
    const seconds = Number(normalized);
    if (Number.isFinite(seconds) && seconds >= 0) {
      return Math.round(seconds * 1000);
    }
    const retryAt = Date.parse(normalized);
    if (!Number.isFinite(retryAt)) return undefined;
    return Math.max(0, retryAt - Date.now());
  }

  private parseJson(text: string, providerLabel = 'MAP') {
    try {
      return JSON.parse(text) as unknown;
    } catch {
      throw new BadGatewayException(
        `${providerLabel} trả dữ liệu không phải JSON`,
      );
    }
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

  private toStatementsXlsx(rows: Array<Record<string, any>>) {
    const headers = [
      'Mã showroom',
      'Loại giao dịch',
      'Mã sao kê',
      'Số tiền',
      'Nội dung chuyển khoản',
      'Mã đơn hàng',
      'Trạng thái',
      'Ngày giao dịch',
      'Người chuyển',
      'Tài khoản chuyển',
      'Tài khoản nhận',
      'Lần đầu thấy',
      'Nguồn đơn hàng',
      'Người sửa đơn hàng',
      'Thời gian sửa đơn hàng',
    ];
    const values: unknown[][] = [headers];
    for (const row of rows) {
      const payer = this.resolveStoredPayer(row);
      const transactionReference = this.resolveStoredTransactionReference(row);
      const statementNumber = transactionReference || row.transactionNumber;
      const incomeType = this.storedIncomeType(row);
      values.push([
        this.csvText(row.storeCode),
        mapVietinIncomeTypeLabel(incomeType),
        this.csvText(statementNumber),
        this.csvAmountValue(row.amount),
        this.csvText(row.content),
        this.csvText((row.orders || []).join('\n')),
        this.csvText(row.status),
        this.csvVietnamDate(row.paidAt),
        this.csvText(payer.name),
        this.csvText(payer.account),
        this.csvText(this.resolveStoredReceivingAccount(row)),
        this.csvVietnamDate(row.firstSeenAt),
        this.csvText(row.orderSource),
        this.csvText(row.orderUpdatedByEmail),
        this.csvVietnamDate(row.orderUpdatedAt),
      ]);
    }
    const worksheet = XLSX.utils.aoa_to_sheet(values);
    worksheet['!cols'] = [
      { wch: 14 },
      { wch: 18 },
      { wch: 24 },
      { wch: 16 },
      { wch: 52 },
      { wch: 30 },
      { wch: 16 },
      { wch: 22 },
      { wch: 28 },
      { wch: 24 },
      { wch: 24 },
      { wch: 22 },
      { wch: 18 },
      { wch: 28 },
      { wch: 22 },
    ];
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Sao kê');
    return XLSX.write(workbook, { bookType: 'xlsx', type: 'buffer' });
  }

  private csvAmountValue(value: unknown) {
    const amount = Number(value);
    return Number.isFinite(amount) ? Math.trunc(amount) : null;
  }

  private csvVietnamDate(value: unknown) {
    if (!value) return '';
    const date = value instanceof Date ? value : new Date(String(value));
    if (Number.isNaN(date.getTime())) return '';
    const vietnamTime = new Date(
      date.getTime() + VIETNAM_UTC_OFFSET_HOURS * 60 * 60 * 1000,
    );
    const two = (part: number) => String(part).padStart(2, '0');
    return [
      `${two(vietnamTime.getUTCDate())}/${two(vietnamTime.getUTCMonth() + 1)}/${vietnamTime.getUTCFullYear()}`,
      `${two(vietnamTime.getUTCHours())}:${two(vietnamTime.getUTCMinutes())}:${two(vietnamTime.getUTCSeconds())}`,
    ].join(' ');
  }

  private csvText(value: unknown) {
    return value === null || value === undefined ? '' : String(value);
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
