import {
  BadGatewayException,
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  Optional,
  UnauthorizedException,
} from '@nestjs/common';
import { Interval } from '@nestjs/schedule';
import { Prisma } from '@prisma/client';
import { createHash } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { decryptSecret } from '../common/secret-cipher';
import { PaymentNotificationsService } from '../payment-notifications/payment-notifications.service';
import {
  ListStoredMapVietinTransactionsDto,
  SearchMapVietinTransactionsDto,
} from './map-vietin.dto';

const SUPER_ADMIN_ROLE = 'SUPER_ADMIN';
const ADMIN_ROLE = 'ADMIN';
const MANAGER_ROLE = 'MANAGER';
const MAP_CLIENT_ID = 'c4a59ac3630f6d8f1abe722eac7052b5';
const MAP_SIGNATURE_KEY = '***REMOVED***';
const MAP_NO_AUTH_BASE_URL =
  'https://map.vietinbank.vn/vtb/public/map/api/ma/no-auth';
const MAP_TRANSACTION_BASE_URL =
  'https://map.vietinbank.vn/vtb/public/map/api/rpt-txnmng/api';

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

@Injectable()
export class MapVietinService {
  private readonly logger = new Logger(MapVietinService.name);
  private syncInProgress = false;
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
    'senderAccount',
    'senderAccountNo',
    'fromAccount',
    'fromAccountNo',
    'debitAccount',
    'debitAccountNo',
  ];

  constructor(
    private prisma: PrismaService,
    @Optional()
    private paymentNotifications?: PaymentNotificationsService,
  ) {}

  async searchTransactions(admin: any, input: SearchMapVietinTransactionsDto) {
    const store = await this.resolveStore(admin, input.storeId);
    return this.searchTransactionsForStore(store, input);
  }

  async listStoredTransactions(
    user: any,
    input: ListStoredMapVietinTransactionsDto,
  ) {
    const store = await this.resolveReadableStore(user, input.storeId);
    const afterFirstSeenAt = input.afterFirstSeenAt
      ? this.parseDate(input.afterFirstSeenAt, 'afterFirstSeenAt')
      : null;
    const localDateRange = this.resolveStoredTransactionDateRange(input);
    const limit = input.limit ?? 10;
    const page = input.page ?? 0;
    const where: Prisma.MapVietinTransactionWhereInput = {
      storeCode: store.storeId,
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
    const [rows, total] = await Promise.all([
      this.prisma.mapVietinTransaction.findMany({
        where,
        orderBy: [{ paidAt: 'desc' }, { firstSeenAt: 'desc' }],
        skip: page * limit,
        take: limit,
      }),
      this.prisma.mapVietinTransaction.count({ where }),
    ]);

    return {
      storeId: store.storeId,
      page,
      limit,
      total,
      list: rows.map((row) => this.toStoredTransactionDto(row)),
    };
  }

  @Interval(5000)
  async syncConfiguredStores() {
    if (process.env.MAP_VIETIN_SYNC_ENABLED === 'false') return;
    if (this.syncInProgress) return;
    this.syncInProgress = true;
    try {
      const stores = await this.prisma.store.findMany({
        where: {
          mapVietinUsername: { not: null },
          mapVietinPasswordCipher: { not: null },
        },
      });
      for (const store of stores) {
        await this.syncStoreTransactions(store);
      }
    } finally {
      this.syncInProgress = false;
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
        size: 100,
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
      storeId: store.storeId,
      pageIndex: response.data?.pageIndex ?? page,
      pageSize: response.data?.pageSize ?? size,
      total: response.data?.total ?? 0,
      list: response.data?.list ?? [],
    };
  }

  private async resolveStore(admin: any, storeCode?: string) {
    this.assertCanSearch(admin);
    const normalizedStoreCode = String(storeCode || '')
      .trim()
      .toUpperCase();

    if (admin.role === SUPER_ADMIN_ROLE) {
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

  private async resolveReadableStore(user: any, storeCode?: string) {
    const normalizedStoreCode = String(storeCode || '')
      .trim()
      .toUpperCase();

    if (user.role === SUPER_ADMIN_ROLE) {
      if (!normalizedStoreCode) {
        throw new BadRequestException('Vui lòng chọn showroom cần theo dõi');
      }
      const store = await this.prisma.store.findUnique({
        where: { storeId: normalizedStoreCode },
      });
      if (!store) throw new BadRequestException('Showroom không hợp lệ');
      return store;
    }

    if (!user.storeId) {
      throw new ForbiddenException('Tài khoản chưa được gán showroom');
    }

    const store = await this.prisma.store.findUnique({
      where: { id: user.storeId },
    });
    if (!store) throw new BadRequestException('Showroom không hợp lệ');
    if (normalizedStoreCode && normalizedStoreCode !== store.storeId) {
      throw new ForbiddenException('Chỉ được xem giao dịch showroom của mình');
    }
    return store;
  }

  private async persistTransactions(storeCode: string, rows: unknown[]) {
    let created = 0;
    for (const raw of rows) {
      if (!raw || typeof raw !== 'object') continue;
      const row = raw as MapTransactionRow;
      const normalized = this.normalizeTransaction(storeCode, row);
      if (!normalized) continue;
      const existing = await this.prisma.mapVietinTransaction.findUnique({
        where: { transactionKey: normalized.transactionKey },
      });
      if (!existing) created += 1;
      const stored = await this.prisma.mapVietinTransaction.upsert({
        where: { transactionKey: normalized.transactionKey },
        create: normalized,
        update: {
          transactionNumber: normalized.transactionNumber,
          amount: normalized.amount,
          content: normalized.content,
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
    return created;
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
      status: status || null,
      paidAt,
      payerName: payerName || null,
      payerAccount: payerAccount || null,
      rawData: row as Prisma.InputJsonObject,
    };
  }

  private toStoredTransactionDto(row: {
    id: string;
    storeCode: string;
    transactionKey: string;
    transactionNumber: string | null;
    amount: number;
    content: string;
    status: string | null;
    paidAt: Date | null;
    payerName: string | null;
    payerAccount: string | null;
    firstSeenAt: Date;
  }) {
    return {
      id: row.id,
      storeId: row.storeCode,
      transactionKey: row.transactionKey,
      transactionNumber: row.transactionNumber,
      amount: row.amount,
      content: row.content,
      status: row.status,
      paidAt: row.paidAt,
      payerName: row.payerName,
      payerAccount: row.payerAccount,
      firstSeenAt: row.firstSeenAt,
    };
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
      throw new BadRequestException('date khÃ´ng há»£p lá»‡');
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
      throw new BadRequestException('date khÃ´ng há»£p lá»‡');
    }
    if (end <= start) {
      throw new BadRequestException('endDate pháº£i sau startDate');
    }
    return { start, end };
  }

  private assertCanSearch(admin: any) {
    if (
      ![SUPER_ADMIN_ROLE, ADMIN_ROLE, MANAGER_ROLE].includes(
        String(admin.role || ''),
      )
    ) {
      throw new ForbiddenException('Không có quyền kiểm tra giao dịch MAP');
    }
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
    throw new BadRequestException(
      'Ngày MAP phải có dạng dd/MM/yyyy hoặc yyyy-MM-dd',
    );
  }

  private formatMapDate(value: Date) {
    return [
      String(value.getDate()).padStart(2, '0'),
      String(value.getMonth() + 1).padStart(2, '0'),
      value.getFullYear(),
    ].join('/');
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

  private safeError(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }
}
