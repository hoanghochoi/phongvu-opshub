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
import { createHash } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { decryptSecret } from '../common/secret-cipher';
import { PaymentNotificationsService } from '../payment-notifications/payment-notifications.service';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { FeatureService } from '../feature/feature.service';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { PolicyService } from '../policy/policy.service';
import { RedisService } from '../redis/redis.service';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import {
  CreateMapVietinStatementOrderTransferRequestDto,
  ExportMapVietinStatementsDto,
  ListMapVietinStatementOrderTransferRequestsDto,
  ListStoredMapVietinTransactionsDto,
  ListMapVietinStatementsDto,
  ReviewMapVietinStatementOrderTransferRequestDto,
  SearchMapVietinTransactionsDto,
  UpdateMapVietinStatementOrdersDto,
} from './map-vietin.dto';

const MAP_CLIENT_ID = 'c4a59ac3630f6d8f1abe722eac7052b5';
const MAP_SIGNATURE_KEY = '***REMOVED***';
const MAP_NO_AUTH_BASE_URL =
  'https://map.vietinbank.vn/vtb/public/map/api/ma/no-auth';
const MAP_TRANSACTION_BASE_URL =
  'https://map.vietinbank.vn/vtb/public/map/api/rpt-txnmng/api';
const GLOBAL_SYNC_STATE_CODE = '__GLOBAL__';
const MAP_SYNC_PAGE_SIZE = 100;
const MAP_SYNC_START_HOUR_VN = 8;
const MAP_SYNC_END_HOUR_VN = 22;
const MAP_HISTORY_SYNC_DELAY_MIN_MS = 3000;
const MAP_HISTORY_SYNC_DELAY_MAX_MS = 5000;
const MAP_HISTORY_SYNC_NIGHT_DELAY_MS = 30 * 60 * 1000;
const DEFAULT_GLOBAL_SYNC_MAX_PAGES = 2;
const DEFAULT_GLOBAL_SESSION_TTL_SECONDS = 10 * 60;
const VIETNAM_UTC_OFFSET_HOURS = 7;
const ORDER_SOURCE_AUTO = 'AUTO';
const ORDER_SOURCE_MANUAL = 'MANUAL';
const ORDER_SOURCE_OFFSET = 'OFFSET';
const FIN_ACC_DEPARTMENT_CODE = 'FIN_ACC';
const ACC_DEPARTMENT_CODE = 'ACC';
const ORDER_EDIT_FORBIDDEN_MESSAGE = 'Bạn không có quyền sửa đơn hàng.';
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
  private lastSyncWindowOpen?: boolean;
  private mapHistorySyncTimer?: NodeJS.Timeout;
  private mapHistorySyncStopped = false;
  private globalSessionCache?: {
    username: string;
    session: MapSession;
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
    'id',
  ];
  private readonly transactionReferenceKeys = ['txnReference'];
  private readonly transactionTimeKeys = [
    'tranTime',
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

  constructor(
    private prisma: PrismaService,
    private policyService: PolicyService,
    private featureService: FeatureService,
    @Optional()
    private paymentNotifications?: PaymentNotificationsService,
    @Optional()
    private redisService?: RedisService,
  ) {}

  onModuleInit() {
    this.mapHistorySyncStopped = false;
    if (this.isMapHistorySyncDisabled()) {
      this.logger.log(
        'MAP history sync scheduler disabled by MAP_VIETIN_SYNC_ENABLED=false',
      );
      return;
    }
    this.scheduleNextMapHistorySync();
  }

  onModuleDestroy() {
    this.mapHistorySyncStopped = true;
    if (this.mapHistorySyncTimer) {
      clearTimeout(this.mapHistorySyncTimer);
      this.mapHistorySyncTimer = undefined;
    }
  }

  async searchTransactions(admin: any, input: SearchMapVietinTransactionsDto) {
    const store = await this.resolveStore(admin, input.storeId);
    return this.searchTransactionsForStore(store, input);
  }

  async listStoredTransactions(
    user: any,
    input: ListStoredMapVietinTransactionsDto,
  ) {
    const storeScope = await this.resolveReadableStoreScope(user, {
      storeId: input.storeId,
      storeIds: input.storeIds,
      allStores: input.allStores,
    });
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
      list: rows.map((row) => this.toStoredTransactionDto(row)),
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

    return {
      page: query.page,
      limit: query.limit,
      total,
      list: rows.map((row) =>
        this.toStoredTransactionDto(row, { canEditProtectedOrders }),
      ),
    };
  }

  async exportStatementsCsv(user: any, input: ExportMapVietinStatementsDto) {
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
        ? await this.buildSelectedStatementWhere(user, selectedIds)
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
      return this.toStatementsCsv(rows);
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
    const existing = await this.prisma.mapVietinTransaction.findUnique({
      where: { id },
    });
    if (!existing) throw new BadRequestException('Giao dịch không hợp lệ');
    await this.assertCanReadStatementStore(user, existing.storeCode);
    const pendingTransferRequest =
      await this.prisma.mapVietinStatementOrderTransferRequest.findFirst({
        where: {
          transactionId: id,
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
    this.assertStatementOrderEditAllowed(existing, canEditProtectedOrders);
    const now = new Date();
    const updated = await this.prisma.mapVietinTransaction.update({
      where: { id },
      data: {
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
          transactionId: id,
          storeCode: existing.storeCode,
          oldOrders,
          newOrders: orders,
          changedByUserId: user.id || null,
          changedByEmail: this.safeUserEmail(user),
          source: ORDER_SOURCE_MANUAL,
        },
      });
    }

    this.logger.log(
      `Statement orders updated: user=${this.safeUserLabel(user)} transaction=${id} store=${existing.storeCode} oldCount=${oldOrders.length} newCount=${orders.length} changed=${changed} protected=${oldOrders.length > 0} finAcc=${canEditProtectedOrders}`,
    );
    return this.toStoredTransactionDto(updated, { canEditProtectedOrders });
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
    this.logger.log(
      `Statement order transfer requests listed: user=${this.safeUserLabel(user)} status=${filters.status} canReview=${canReview} count=${rows.length} total=${total} page=${filters.page} limit=${filters.limit}`,
    );
    return {
      page: filters.page,
      limit: filters.limit,
      total,
      canReview,
      list: rows.map((row) => this.toStatementOrderTransferRequestDto(row)),
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

  private scheduleNextMapHistorySync() {
    if (this.mapHistorySyncStopped || this.isMapHistorySyncDisabled()) return;
    const delayMs = this.nextMapHistorySyncDelayMs();
    if (this.mapHistorySyncTimer) {
      clearTimeout(this.mapHistorySyncTimer);
    }
    this.mapHistorySyncTimer = setTimeout(() => {
      void this.runScheduledMapHistorySync();
    }, delayMs);
    this.mapHistorySyncTimer.unref?.();
    this.logger.debug(`Next MAP history sync scheduled in ${delayMs}ms`);
  }

  private async runScheduledMapHistorySync() {
    try {
      await this.syncConfiguredStores();
    } catch (error) {
      this.logger.warn(
        `Scheduled MAP history sync failed: ${this.safeError(error).slice(0, 500)}`,
      );
    } finally {
      this.scheduleNextMapHistorySync();
    }
  }

  private randomMapHistorySyncDelayMs() {
    const span = MAP_HISTORY_SYNC_DELAY_MAX_MS - MAP_HISTORY_SYNC_DELAY_MIN_MS;
    return (
      MAP_HISTORY_SYNC_DELAY_MIN_MS + Math.floor(Math.random() * (span + 1))
    );
  }

  private nextMapHistorySyncDelayMs(value = new Date(Date.now())) {
    return this.isWithinMapSyncWindow(value)
      ? this.randomMapHistorySyncDelayMs()
      : MAP_HISTORY_SYNC_NIGHT_DELAY_MS;
  }

  private isMapHistorySyncDisabled() {
    return process.env.MAP_VIETIN_SYNC_ENABLED === 'false';
  }

  async syncConfiguredStores() {
    if (this.isMapHistorySyncDisabled()) return;
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
        await this.syncGlobalTransactions();
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
      await this.syncStoreTransactions(store);
    }
  }

  async syncGlobalTransactions() {
    const now = new Date();
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
      let quarantined = 0;
      let page = 0;
      const size = MAP_SYNC_PAGE_SIZE;
      const maxPages = this.globalSyncMaxPages();

      this.logger.log('Global MAP sync started');
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
          this.logger.warn(
            'Global MAP session was rejected; refreshing token and retrying current page',
          );
          session = await this.getGlobalSession(username, password, true);
          result = await this.searchTransactionsWithSession(
            GLOBAL_SYNC_STATE_CODE,
            session,
            input,
          );
        }
        const persisted = await this.persistGlobalTransactions(
          result.list,
          storeAccountIndex,
        );
        created += persisted.created;
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
      if (created > 0 || quarantined > 0) {
        this.logger.log(
          `Global MAP sync stored ${created} transactions and quarantined ${quarantined}`,
        );
      }
      return { created, quarantined };
    } catch (error) {
      const message = this.safeError(error).slice(0, 500);
      this.logger.warn(`Global MAP sync failed: ${message}`);
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

  async syncStoreTransactions(store: {
    storeId: string;
    mapVietinUsername?: string | null;
    mapVietinPasswordCipher?: string | null;
  }) {
    const now = new Date();
    try {
      const today = this.formatMapDate(now);
      const result = await this.searchTransactionsForStore(store, {
        startDate: today,
        endDate: today,
        page: 0,
        size: MAP_SYNC_PAGE_SIZE,
      });
      const created = await this.persistTransactions(
        store.storeId,
        result.list,
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
      if (created > 0) {
        this.logger.log(
          `MAP sync stored ${created} new transactions for ${store.storeId}`,
        );
      }
      return created;
    } catch (error) {
      const message = this.safeError(error).slice(0, 500);
      this.logger.warn(`MAP sync failed for ${store.storeId}: ${message}`);
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
    const scopeWhere = await this.buildStatementScopeWhere(user, filters);
    const filterWhere = this.buildStatementFilterWhere(filters);
    return {
      where: this.andWhere(scopeWhere, filterWhere),
      page: input.page ?? 0,
      limit: input.limit ?? 20,
      filterSummary: filters.summary,
    };
  }

  private async buildSelectedStatementWhere(user: any, ids: string[]) {
    const scopeWhere = await this.buildStatementScopeWhere(user, {
      requestedAllStores: false,
      storeIds: [],
    });
    return this.andWhere(scopeWhere, { id: { in: ids } });
  }

  private normalizeStatementFilters(input: ListMapVietinStatementsDto) {
    const storeIds = this.parseStoreCodes(input.storeIds);
    const requestedAllStores = this.parseBoolean(input.allStores);
    if (requestedAllStores && storeIds.length > 0) {
      throw new BadRequestException('Chỉ chọn tất cả hoặc danh sách showroom');
    }

    const orderText = this.cleanText(input.order);
    const order = orderText ? this.normalizeSingleOrderCode(orderText) : null;
    const amount = this.normalizeStatementAmount(input.amount);
    const content = this.cleanText(input.content);
    const orderStatus = input.orderStatus || STATEMENT_ORDER_STATUS_ALL;
    const dateRange = this.resolveStoredTransactionDateRange(input);
    const primaryCount = [
      requestedAllStores || storeIds.length > 0,
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
      order,
      amount,
      content,
      orderStatus,
      dateRange,
      hasEffectiveFilter,
      summary: [
        requestedAllStores ? 'allStores' : '',
        storeIds.length ? `stores:${storeIds.length}` : '',
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
    return { storeCode: this.storeCodeWhere(selectedStoreCodes) };
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

  private buildStatementFilterWhere(filters: {
    order?: string | null;
    amount?: number | null;
    content?: string;
    orderStatus?: string;
    dateRange?: { start: Date; end: Date } | null;
  }): Prisma.MapVietinTransactionWhereInput {
    const parts: Prisma.MapVietinTransactionWhereInput[] = [];
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

  private async assertCanReadStatementStore(user: any, storeCode: string) {
    await this.assertCanUseStatements(user);
    if (await this.hasNationalStatementScope(user)) return;
    const stores = await this.resolveUserStores(user);
    if (!stores.some((store) => store.storeId === storeCode)) {
      throw new ForbiddenException('Chỉ được xem giao dịch showroom được gán');
    }
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

  private async canEditProtectedStatementOrders(user: any): Promise<boolean> {
    return this.userMatchesStatementAccessCodes(user, [
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

  private async persistTransactions(storeCode: string, rows: unknown[]) {
    let created = 0;
    let withOrders = 0;
    let withoutOrders = 0;
    let manualProtected = 0;
    for (const raw of rows) {
      if (!raw || typeof raw !== 'object') continue;
      const row = raw as MapTransactionRow;
      const normalized = this.normalizeTransaction(storeCode, row);
      if (!normalized) continue;
      if (normalized.orders.length > 0) {
        withOrders += 1;
      } else {
        withoutOrders += 1;
      }
      const existing = await this.prisma.mapVietinTransaction.findUnique({
        where: { transactionKey: normalized.transactionKey },
      });
      if (!existing) created += 1;
      const preservesManualOrders =
        existing?.orderSource === ORDER_SOURCE_MANUAL;
      if (preservesManualOrders) manualProtected += 1;
      const stored = await this.prisma.mapVietinTransaction.upsert({
        where: { transactionKey: normalized.transactionKey },
        create: normalized,
        update: {
          transactionNumber: normalized.transactionNumber,
          amount: normalized.amount,
          content: normalized.content,
          ...(preservesManualOrders
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
        },
      });
      if (!existing && stored?.id && this.paymentNotifications) {
        void this.paymentNotifications
          .createForTransaction(stored)
          .catch((error) => {
            this.logger.warn(
              `Payment notification failed for ${stored.id}: ${this.safeError(error)}`,
            );
          });
      }
    }
    if (created > 0) {
      this.logger.log(
        `MAP sync order extraction: store=${storeCode} created=${created} withOrders=${withOrders} withoutOrders=${withoutOrders} manualProtected=${manualProtected}`,
      );
    }
    return created;
  }

  private async persistGlobalTransactions(
    rows: unknown[],
    storeAccountIndex: Map<string, string[]>,
  ) {
    let created = 0;
    let quarantined = 0;
    for (const raw of rows) {
      if (!raw || typeof raw !== 'object') continue;
      const row = raw as MapTransactionRow;
      const amount = this.readAmount(row);
      if (!amount || amount <= 0) continue;
      if (!this.isSuccessfulTransaction(row)) continue;

      const virtualAccount = this.readFirstText(row, this.virtualAccountKeys);
      const accountKey = this.normalizeAccountNumber(virtualAccount);
      const storeCodes = accountKey
        ? storeAccountIndex.get(accountKey) || []
        : [];

      if (!accountKey) {
        await this.quarantineGlobalTransaction(
          row,
          'MISSING_VIRTUAL_ACCOUNT',
          virtualAccount,
        );
        quarantined += 1;
        continue;
      }
      if (storeCodes.length === 0) {
        await this.quarantineGlobalTransaction(
          row,
          'UNMAPPED_ACCOUNT',
          virtualAccount,
        );
        quarantined += 1;
        continue;
      }
      if (storeCodes.length > 1) {
        await this.quarantineGlobalTransaction(
          row,
          'AMBIGUOUS_ACCOUNT',
          virtualAccount,
        );
        quarantined += 1;
        continue;
      }

      created += await this.persistTransactions(storeCodes[0], [row]);
    }
    return { created, quarantined };
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

  private normalizeTransaction(storeCode: string, row: MapTransactionRow) {
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
    const fallback = [
      transactionNumber,
      amount,
      paidAt?.toISOString() ?? '',
      content,
    ].join('|');
    const hash = createHash('sha256')
      .update(`${storeCode}|${fallback}`)
      .digest('hex');

    return {
      storeCode,
      transactionKey: `${storeCode}:${hash}`,
      transactionNumber: transactionNumber || null,
      amount,
      content,
      orders,
      orderSource: ORDER_SOURCE_AUTO,
      status: status || null,
      paidAt,
      payerName: payerName || null,
      payerAccount: payerAccount || null,
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
        if (!this.isValidOrderCode(token)) {
          throw new BadRequestException('Mã đơn hàng không hợp lệ');
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
      storeCode: string;
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
    options: { canEditProtectedOrders?: boolean } = {},
  ) {
    const payer = this.resolveStoredPayer(row);
    const orders = row.orders || [];
    const pendingTransferRequest = row.orderTransferRequests?.[0] || null;
    const transferWindowOpen = this.isStatementOrderTransferWindowOpen(row);
    const canEditOrders =
      !pendingTransferRequest &&
      (orders.length === 0 || options.canEditProtectedOrders === true);
    const orderTransferBlockedReason = pendingTransferRequest
      ? 'Giao dịch đang chờ Kế toán xác nhận.'
      : transferWindowOpen
        ? null
        : ORDER_TRANSFER_WINDOW_FORBIDDEN_MESSAGE;
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
      orderEditBlockedReason: canEditOrders
        ? null
        : pendingTransferRequest
          ? 'Giao dịch đang chờ Kế toán xác nhận.'
          : ORDER_EDIT_FORBIDDEN_MESSAGE,
      canRequestOrderTransfer: !pendingTransferRequest && transferWindowOpen,
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
      firstSeenAt: row.firstSeenAt,
    };
  }

  private toStatementOrderTransferRequestDto(row: {
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
  }) {
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
    };
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
    await this.redisService.publishMessage(STATEMENT_ORDER_TRANSFER_CHANNEL, {
      requestId: row.id,
      transactionId: row.transactionId,
      storeCode: row.storeCode,
      status: row.status,
      createdAt: row.createdAt.toISOString(),
      ...(row.recipientUserId ? { recipientUserId: row.recipientUserId } : {}),
    });
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
    rawData?: Prisma.JsonValue | null;
  }) {
    const rawData = this.rawDataAsMapRow(row.rawData);
    return rawData
      ? this.readFirstText(rawData, this.transactionReferenceKeys) || null
      : null;
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
      /^(\d{2})\/(\d{2})\/(\d{4})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?$/.exec(
        raw,
      );
    if (!match) {
      const parsed = new Date(raw);
      return Number.isNaN(parsed.getTime()) ? null : parsed;
    }
    return new Date(
      Date.UTC(
        Number(match[3]),
        Number(match[2]) - 1,
        Number(match[1]),
        Number(match[4] || '0') - 7,
        Number(match[5] || '0'),
        Number(match[6] || '0'),
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
    return [
      String(value.getDate()).padStart(2, '0'),
      String(value.getMonth() + 1).padStart(2, '0'),
      value.getFullYear(),
    ].join('/');
  }

  private isWithinMapSyncWindow(value = new Date(Date.now())) {
    const vietnamHour = (value.getUTCHours() + VIETNAM_UTC_OFFSET_HOURS) % 24;
    return (
      vietnamHour >= MAP_SYNC_START_HOUR_VN &&
      vietnamHour < MAP_SYNC_END_HOUR_VN
    );
  }

  private async postJson<T>(
    url: string,
    body: Record<string, unknown>,
    headers: Record<string, string>,
  ): Promise<T> {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...headers,
      },
      body: JSON.stringify(body),
    });
    const text = await response.text();
    const json = text ? this.parseJson(text) : {};

    if (!response.ok) {
      throw new BadGatewayException(
        `MAP trả lỗi ${response.status}: ${this.safeProviderMessage(json)}`,
      );
    }
    return json as T;
  }

  private parseJson(text: string) {
    try {
      return JSON.parse(text) as unknown;
    } catch {
      throw new BadGatewayException('MAP trả dữ liệu không phải JSON');
    }
  }

  private safeProviderMessage(value: unknown) {
    if (!value || typeof value !== 'object') return 'Không rõ lỗi';
    const record = value as Record<string, unknown>;
    return String(
      record.message || record.error_desc || record.error || 'Không rõ lỗi',
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

  private toStatementsCsv(rows: Array<Record<string, any>>) {
    const headers = [
      'Mã showroom',
      'Mã sao kê',
      'Số tiền',
      'Nội dung chuyển khoản',
      'Mã đơn hàng',
      'Trạng thái',
      'Ngày giao dịch',
      'Người chuyển',
      'Tài khoản chuyển',
      'Lần đầu thấy',
      'Nguồn đơn hàng',
      'Người sửa đơn hàng',
      'Thời gian sửa đơn hàng',
    ];
    const lines = [headers.map((value) => this.csvCell(value)).join(',')];
    for (const row of rows) {
      const payer = this.resolveStoredPayer(row);
      const transactionReference = this.resolveStoredTransactionReference(row);
      const statementNumber = transactionReference || row.transactionNumber;
      lines.push(
        [
          this.csvCell(row.storeCode),
          this.csvExcelTextCell(statementNumber),
          this.csvAmountCell(row.amount),
          this.csvCell(row.content),
          this.csvExcelTextCell((row.orders || []).join('\n'), {
            preserveLineBreaks: true,
          }),
          this.csvCell(row.status),
          this.csvCell(this.csvVietnamDate(row.paidAt)),
          this.csvCell(payer.name),
          this.csvExcelTextCell(payer.account),
          this.csvCell(this.csvVietnamDate(row.firstSeenAt)),
          this.csvCell(row.orderSource),
          this.csvCell(row.orderUpdatedByEmail),
          this.csvCell(this.csvVietnamDate(row.orderUpdatedAt)),
        ].join(','),
      );
    }
    return `${String.fromCharCode(0xfeff)}${lines.join('\r\n')}`;
  }

  private csvCell(value: unknown) {
    const text = this.csvText(value);
    if (!/[",\r\n]/.test(text)) return text;
    return `"${text.replace(/"/g, '""')}"`;
  }

  private csvExcelTextCell(
    value: unknown,
    options: { preserveLineBreaks?: boolean } = {},
  ) {
    const text = this.csvText(value);
    if (!text) return '';
    const normalizedText = options.preserveLineBreaks
      ? text.replace(/\r\n?/g, '\n')
      : text.replace(/[\r\n]+/g, ' ');
    const formulaText = normalizedText.replace(/"/g, '""');
    return this.csvCell(`="${formulaText}"`);
  }

  private csvAmountCell(value: unknown) {
    const amount = Number(value);
    if (!Number.isFinite(amount)) return '';
    return String(Math.trunc(amount));
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
    return this.safeUserEmail(user) || user.id || 'unknown';
  }

  private safeUserEmail(user: any) {
    const email = String(user?.email || '')
      .trim()
      .toLowerCase();
    return email || null;
  }

  private isProviderAuthError(error: unknown) {
    const message = this.safeError(error);
    return message.includes('401') || message.includes('403');
  }

  private safeError(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }
}
