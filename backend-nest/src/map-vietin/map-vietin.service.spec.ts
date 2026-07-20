import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { createHash } from 'crypto';
import * as XLSX from 'xlsx';
import { encryptSecret } from '../common/secret-cipher';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { MapVietinService } from './map-vietin.service';

describe('MapVietinService', () => {
  const originalEnv = process.env;
  const manager = { role: 'MANAGER', storeId: 'store-uuid-1' };
  let prisma: any;
  let fetchMock: jest.Mock;
  let paymentNotifications: { createForTransaction: jest.Mock };
  let redisService: { publishMessage: jest.Mock };
  let notificationsService: { readAtByNotificationId: jest.Mock };
  let policyService: { canAccessPolicy: jest.Mock };
  let featureService: { canAccessFeature: jest.Mock };
  let service: MapVietinService;

  beforeEach(() => {
    process.env = {
      ...originalEnv,
      JWT_SECRET: 'test-jwt-secret',
      MAP_VIETIN_CREDENTIAL_SECRET: 'test-map-secret',
    };
    prisma = {
      user: {
        findUnique: jest.fn(async ({ where }: any) => {
          if (where.id === 'fin-node-user') {
            return {
              departmentCode: null,
              organizationNodeId: 'org-fin-child',
            };
          }
          if (where.id === 'acc-node-user') {
            return {
              departmentCode: null,
              organizationNodeId: 'org-acc-child',
            };
          }
          return null;
        }),
      },
      organizationNode: {
        findMany: jest.fn(async () => [
          {
            id: 'org-fin',
            parentId: null,
            code: 'FIN_ACC',
            businessCode: 'FIN_ACC',
          },
          {
            id: 'org-fin-child',
            parentId: 'org-fin',
            code: 'FIN_CHILD',
            businessCode: 'FIN_CHILD',
          },
          {
            id: 'org-acc',
            parentId: null,
            code: 'ACC',
            businessCode: 'ACC',
          },
          {
            id: 'org-acc-child',
            parentId: 'org-acc',
            code: 'ACC_CHILD',
            businessCode: 'ACC_CHILD',
          },
        ]),
      },
      store: {
        findUnique: jest.fn(),
        findMany: jest.fn(),
      },
      mapVietinTransaction: {
        findMany: jest.fn(async () => []),
        count: jest.fn(),
        findFirst: jest.fn(),
        findUnique: jest.fn(),
        upsert: jest.fn(),
        update: jest.fn(),
        updateMany: jest.fn(async () => ({ count: 0 })),
      },
      mapVietinTransactionOrderAudit: {
        create: jest.fn(),
        findMany: jest.fn(),
      },
      mapVietinStatementOrderTransferRequest: {
        updateMany: jest.fn(async () => ({ count: 0 })),
        findFirst: jest.fn(),
        create: jest.fn(),
        findMany: jest.fn(),
        count: jest.fn(),
        findUnique: jest.fn(),
        update: jest.fn(),
      },
      mapVietinUnmappedTransaction: {
        upsert: jest.fn(),
      },
      mapVietinSyncState: {
        upsert: jest.fn(),
      },
    };
    delete process.env.MAP_VIETIN_GLOBAL_USERNAME;
    delete process.env.MAP_VIETIN_GLOBAL_PASSWORD;
    delete process.env.MAP_VIETIN_GLOBAL_SYNC_ENABLED;
    delete process.env.MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES;
    delete process.env.MAP_VIETIN_GLOBAL_SESSION_TTL_SECONDS;
    delete process.env.MAP_VIETIN_DEEP_SWEEP_DELAY_MIN_MS;
    delete process.env.MAP_VIETIN_DEEP_SWEEP_DELAY_MAX_MS;
    delete process.env.MAP_VIETIN_RATE_LIMIT_BACKOFF_BASE_MS;
    delete process.env.MAP_VIETIN_RATE_LIMIT_BACKOFF_MAX_MS;
    delete process.env.MAP_VIETIN_FORBIDDEN_BACKOFF_MS;
    delete process.env.MAP_VIETIN_SYNC_FINGERPRINT_CACHE_TTL_MS;
    delete process.env.MAP_VIETIN_SYNC_FINGERPRINT_CACHE_MAX_ENTRIES;
    delete process.env.MAP_VIETIN_SYNC_ENABLED;
    paymentNotifications = { createForTransaction: jest.fn() };
    redisService = { publishMessage: jest.fn().mockResolvedValue(undefined) };
    policyService = {
      canAccessPolicy: jest.fn(async (user: any, code: string) => {
        if (user?.role === 'SUPER_ADMIN') return true;
        const role = String(user?.role || '').toUpperCase();
        const policyCode = String(code || '').toUpperCase();
        if (policyCode === ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE) {
          return user?.statementAllScope === true;
        }
        if (policyCode === ADMIN_POLICY_CODES.BANK_STATEMENTS) {
          return ['ADMIN_PHONGVU', 'ADMIN_ACARE', 'MANAGER', 'STAFF'].includes(
            role,
          );
        }
        return false;
      }),
    };
    featureService = {
      canAccessFeature: jest.fn(async (user: any, code: string) => {
        return (
          code === FEATURE_KEYS.BANK_STATEMENTS &&
          user?.featureBankStatements !== false
        );
      }),
    };
    fetchMock = jest.fn();
    notificationsService = {
      readAtByNotificationId: jest.fn().mockResolvedValue(new Map()),
    };
    global.fetch = fetchMock as any;
    jest
      .spyOn(Date, 'now')
      .mockReturnValue(new Date('2026-05-21T03:00:00.000Z').getTime());
    service = new MapVietinService(
      prisma,
      policyService as any,
      featureService as any,
      paymentNotifications as any,
      redisService as any,
      notificationsService as any,
    );
  });

  afterEach(() => {
    process.env = originalEnv;
    jest.restoreAllMocks();
  });

  it('logs in to MAP and searches transactions for manager store', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
      mapVietinUsername: 'map-user',
      mapVietinPasswordCipher: encryptSecret('map-pass'),
    });
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [
            { merchant_id: 'merchant-fallback', is_default: false },
            { merchant_id: 'merchant-default', is_default: true },
          ],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [{ transactionNumber: 'masked-in-test' }],
            pageIndex: 0,
            pageSize: 20,
            total: 1,
          },
        }),
      );

    await expect(
      service.searchTransactions(manager, {
        startDate: '2026-05-20',
        endDate: '20/05/2026',
        amount: '150,000',
      }),
    ).resolves.toMatchObject({
      storeId: 'CP01',
      pageIndex: 0,
      pageSize: 20,
      total: 1,
      list: [{ transactionNumber: 'masked-in-test' }],
    });

    expect(prisma.store.findUnique).toHaveBeenCalledWith({
      where: { id: 'store-uuid-1' },
    });
    const loginBody = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(loginBody).toMatchObject({
      username: 'map-user',
      captcha_resp: '123456',
      language: 'vi',
    });
    expect(loginBody.password).not.toBe('map-pass');
    expect(loginBody.password).toMatch(/^[a-f0-9]{64}$/);
    expect(fetchMock.mock.calls[0][1].headers).toEqual(
      expect.objectContaining({
        ClientId: 'c4a59ac3630f6d8f1abe722eac7052b5',
        Signature: expect.stringMatching(/^[a-f0-9]{32}$/),
      }),
    );

    expect(fetchMock.mock.calls[1][0]).toContain(
      '/ma/payment-transaction/search?page=0&size=20&sort=txnDate,desc',
    );
    expect(fetchMock.mock.calls[1][1].headers).toEqual(
      expect.objectContaining({
        Authorization: 'Bearer access-token',
        merchantId: 'merchant-default',
        'x-lang': 'vi',
      }),
    );
    expect(JSON.parse(fetchMock.mock.calls[1][1].body)).toEqual({
      searchType: '0',
      startDate: '20/05/2026',
      endDate: '20/05/2026',
      amount: '150000',
    });
  });

  it('requires super admin to choose a store', async () => {
    await expect(
      service.searchTransactions({ role: 'SUPER_ADMIN' }, {}),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('blocks manager from searching a different store', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
      mapVietinUsername: 'map-user',
      mapVietinPasswordCipher: encryptSecret('map-pass'),
    });

    await expect(
      service.searchTransactions(manager, { storeId: 'CP02' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('limits a non-FIN all-scope user to sales statements', async () => {
    const financeUser = {
      id: 'finance-1',
      role: 'USER',
      statementAllScope: true,
    };
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await expect(
      service.listStatements(financeUser, { allStores: 'true' } as any),
    ).resolves.toMatchObject({
      page: 0,
      limit: 20,
      total: 0,
      list: [],
    });

    expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { incomeType: 'SALES' } }),
    );
    expect(policyService.canAccessPolicy).toHaveBeenCalledWith(
      financeUser,
      ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE,
    );
  });

  it('allows store-scoped statement reads from feature-tree access without statement policy', async () => {
    const cashUser = {
      id: 'cash-1',
      role: 'USER',
      storeId: 'store-uuid-1',
      featureBankStatements: true,
    };
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await expect(
      service.listStatements(cashUser, {
        storeIds: 'CP01',
        page: 0,
        limit: 20,
      }),
    ).resolves.toMatchObject({
      page: 0,
      limit: 20,
      total: 0,
      list: [],
    });

    expect(featureService.canAccessFeature).toHaveBeenCalledWith(
      cashUser,
      FEATURE_KEYS.BANK_STATEMENTS,
    );
    expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          AND: expect.arrayContaining([
            { storeCode: 'CP01' },
            { incomeType: 'SALES' },
          ]),
        },
      }),
    );
  });

  it('limits SR users to sales income even for global lookup', async () => {
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await service.listStatements({ role: 'MANAGER', storeId: 'store-uuid-1' }, {
      amount: '1250000',
    } as any);

    const where = prisma.mapVietinTransaction.findMany.mock.calls[0][0].where;
    expect(JSON.stringify(where)).toContain('incomeType');
    expect(JSON.stringify(where)).toContain('SALES');
  });

  it('allows FIN_ACC users to see both income types in the same scope', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await service.listStatements(
      {
        id: 'fin-node-user',
        role: 'USER',
        departmentCode: 'FIN_ACC',
        storeId: 'store-uuid-1',
        featureBankStatements: true,
      },
      { storeIds: 'CP01' } as any,
    );

    expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { storeCode: 'CP01' } }),
    );
  });

  it('classifies a configured payer account from the provider payload as partner/internal', () => {
    const normalized = (service as any).normalizeTransaction('CP01', {
      amount: 1250000,
      transactionDescription: 'Khach chuyen tien',
      transactionStatus: 'SUCCESS',
      senderAccount: '8637988888',
    });

    expect(normalized).toMatchObject({
      payerAccount: '8637988888',
      incomeType: 'PARTNER_INTERNAL',
      incomeTypeSource: 'AUTO',
    });
  });

  it('classifies provider content starting with TNG independent of mapped store', () => {
    const normalized = (service as any).normalizeTransaction('CP01', {
      amount: 40708000,
      transactionDescription: 'TNG CP69 NOP TIEN N 20.07.2026',
      transactionStatus: 'SUCCESS',
    });

    expect(normalized).toMatchObject({
      storeCode: 'CP01',
      incomeType: 'PARTNER_INTERNAL',
      incomeTypeSource: 'AUTO',
    });
  });

  it('limits SUPER_ADMIN to sales unless the user belongs to FIN_ACC', async () => {
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await service.listStatements({ id: 'super-1', role: 'SUPER_ADMIN' }, {
      allStores: 'true',
    } as any);

    expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { incomeType: 'SALES' } }),
    );
  });

  it('allows statement reads for the parent showroom of assigned Lv5 nodes', async () => {
    prisma.user.findUnique.mockResolvedValueOnce({
      store: null,
      organizationAssignments: [
        {
          organizationNode: {
            stores: [],
            parent: {
              stores: [{ storeId: 'CP75' }],
            },
          },
        },
      ],
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await expect(
      service.listStatements(
        {
          id: 'multi-lv5-user',
          role: 'USER',
          featureBankStatements: true,
        },
        { storeIds: 'CP75', page: 0, limit: 20 },
      ),
    ).resolves.toMatchObject({
      page: 0,
      limit: 20,
      total: 0,
      list: [],
    });

    expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          AND: expect.arrayContaining([
            { storeCode: 'CP75' },
            { incomeType: 'SALES' },
          ]),
        },
      }),
    );
  });

  it('rejects statement reads without feature-tree access', async () => {
    await expect(
      service.listStatements(
        {
          id: 'staff-1',
          role: 'USER',
          storeId: 'store-uuid-1',
          featureBankStatements: false,
        },
        { storeIds: 'CP01', page: 0, limit: 20 },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(prisma.store.findUnique).not.toHaveBeenCalled();
    expect(prisma.mapVietinTransaction.findMany).not.toHaveBeenCalled();
  });

  it('does not reopen statement reads from all-scope policy alone', async () => {
    await expect(
      service.listStatements(
        {
          id: 'policy-only-user',
          role: 'USER',
          storeId: 'store-uuid-1',
          statementAllScope: true,
          featureBankStatements: false,
        },
        { storeIds: 'CP01', page: 0, limit: 20 },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(prisma.mapVietinTransaction.findMany).not.toHaveBeenCalled();
  });

  it('requires MAP credentials before calling VietinBank', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
      mapVietinUsername: null,
      mapVietinPasswordCipher: null,
    });

    await expect(
      service.searchTransactions(manager, {}),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('syncs successful MAP transactions into OpsHub database', async () => {
    const store = {
      storeId: 'CP01',
      mapVietinUsername: 'map-user',
      mapVietinPasswordCipher: encryptSecret('map-pass'),
    };
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [
              {
                txnNo: 'TXN-001',
                txnAmount: '1,250,000',
                txnDate: '21/05/2026 10:00:00',
                txnDesc: 'Khach chuyen tien 26052112345678 va 26052287654321',
                status: '00',
              },
              {
                txnNo: 'TXN-002',
                txnAmount: '500,000',
                txnDate: '21/05/2026 10:01:00',
                status: 'PENDING',
              },
            ],
          },
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({});
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(service.syncStoreTransactions(store)).resolves.toBe(1);

    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledTimes(1);
    expect(
      prisma.mapVietinTransaction.upsert.mock.calls[0][0].create,
    ).toMatchObject({
      storeCode: 'CP01',
      transactionNumber: 'TXN-001',
      amount: 1250000,
      content: 'Khach chuyen tien 26052112345678 va 26052287654321',
      orders: ['26052112345678', '26052287654321'],
      orderSource: 'AUTO',
    });
  });

  it('syncs global MAP transactions by virtual account and creates notifications', async () => {
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: ' 18-PV ICU ' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [
              {
                txnNo: 'TXN-001',
                txnAmount: '1,250,000',
                txnDate: '21/05/2026 10:00:00',
                txnDesc: 'Khach chuyen tien',
                status: '00',
                virtualAccount: '18pv-icu',
                reqCardName: 'NGUYEN VAN A',
                reqCardNo: '9704361234567890',
              },
            ],
            pageIndex: 0,
            pageSize: 100,
            total: 1,
          },
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({
      id: 'stored-1',
      storeCode: 'CP01',
      amount: 1250000,
    });
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});
    paymentNotifications.createForTransaction.mockResolvedValue({});

    await expect(service.syncConfiguredStores()).resolves.toBeUndefined();

    const loginBody = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(loginBody.username).toBe('global-user');
    expect(loginBody.password).not.toBe('global-pass');
    expect(prisma.store.findMany).toHaveBeenCalledWith({
      where: { transferAccountNumber: { not: null } },
      select: { storeId: true, transferAccountNumber: true },
    });
    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({
          storeCode: 'CP01',
          transactionNumber: 'TXN-001',
          amount: 1250000,
          payerName: 'NGUYEN VAN A',
          payerAccount: '9704361234567890',
        }),
      }),
    );
    expect(paymentNotifications.createForTransaction).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'stored-1', storeCode: 'CP01' }),
    );
    expect(prisma.mapVietinUnmappedTransaction.upsert).not.toHaveBeenCalled();
  });

  it('syncs eFAST transactions with the browser-compatible login payload', async () => {
    jest.spyOn(Math, 'random').mockReturnValue(0.5);
    process.env.VIETIN_EFAST_USERNAME = 'efast-user';
    process.env.VIETIN_EFAST_PASSWORD = 'efast-pass';
    process.env.VIETIN_EFAST_BANK_ACCOUNTS = '123456789012';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          status: { code: '1', message: 'LOGON_SUCCESS' },
          sessionId: 'efast-session-id',
          corpUser: { cifno: '1234561361' },
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          status: { code: '1', message: 'SUCCESS' },
          currentPage: 0,
          nextPage: 0,
          transactions: [
            {
              trxId: 'TRX-001',
              trxRefNo: 'REF-001',
              pmtId: '18PVICU',
              amount: 1250000,
              remark: 'Khach chuyen tien 26052112345678',
              tranDate: '21-05-2026 10:00:00',
              dorc: 'C',
              corresponsiveName: 'NGUYEN VAN A',
              corresponsiveAccount: '9704361234567890',
            },
          ],
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({
      id: 'stored-efast-1',
      storeCode: 'CP01',
      amount: 1250000,
    });
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});
    paymentNotifications.createForTransaction.mockResolvedValue({});

    await expect(service.syncEfastTransactions()).resolves.toEqual({
      created: 1,
      quarantined: 0,
      fetched: 1,
      creditRows: 1,
    });

    const loginBody = JSON.parse(fetchMock.mock.calls[0][1].body);
    const expectedRequestPrefix = new Date('2026-05-21T03:00:00.000Z')
      .getTime()
      .toString(36);
    expect(loginBody.requestId).toBe(`${expectedRequestPrefix}i`);
    expect(loginBody.username).not.toBe('efast-user');
    expect(loginBody.password).not.toBe('efast-pass');
    expect(loginBody.cifno).toBe(false);
    expect(loginBody.sessionId).toBeUndefined();

    const historyBody = JSON.parse(fetchMock.mock.calls[1][1].body);
    expect(historyBody.accountNo).toBe('123456789012');
    expect(historyBody.sessionId).toBe('efast-session-id');
    expect(historyBody.cifno).not.toBe('1234561361');
    expect(historyBody.dorcC).toBe('Credit');
    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({
          storeCode: 'CP01',
          transactionNumber: 'TRX-001',
          amount: 1250000,
          paidAt: new Date('2026-05-21T03:00:00.000Z'),
          payerName: 'NGUYEN VAN A',
          payerAccount: '9704361234567890',
          rawData: expect.objectContaining({
            virtualAccount: '18PVICU',
            efastCreditAccountNo: '123456789012',
            tranTime: '21/05/2026 10:00:00',
          }),
        }),
      }),
    );
  });

  it('skips eFAST rows when the statement id already exists from MAP', async () => {
    process.env.VIETIN_EFAST_USERNAME = 'efast-user';
    process.env.VIETIN_EFAST_PASSWORD = 'efast-pass';
    process.env.VIETIN_EFAST_BANK_ACCOUNTS = '123456789012';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          status: { code: '1', message: 'LOGON_SUCCESS' },
          sessionId: 'efast-session-id',
          corpUser: { cifno: '1234561361' },
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          status: { code: '1', message: 'SUCCESS' },
          currentPage: 0,
          nextPage: 0,
          transactions: [
            {
              trxId: 'MAP-STATEMENT-001',
              trxRefNo: 'MAP-REF-001',
              pmtId: '18PVICU',
              amount: 1250000,
              remark: 'Khach chuyen tien 26052112345678',
              tranDate: '21-05-2026 10:00:00',
              dorc: 'C',
            },
          ],
        }),
      );
    prisma.mapVietinTransaction.findFirst.mockResolvedValue({
      id: 'existing-map-transaction',
      transactionKey: 'CP01:existing-map',
      storeCode: 'CP01',
    });
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(service.syncEfastTransactions()).resolves.toEqual({
      created: 0,
      quarantined: 0,
      fetched: 1,
      creditRows: 1,
    });

    expect(prisma.mapVietinTransaction.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          transactionKey: expect.objectContaining({ not: expect.any(String) }),
          OR: expect.arrayContaining([
            { transactionNumber: 'MAP-STATEMENT-001' },
            {
              rawData: {
                path: ['txnReference'],
                equals: 'MAP-REF-001',
              },
            },
          ]),
        }),
      }),
    );
    expect(prisma.mapVietinTransaction.findUnique).toHaveBeenCalledTimes(2);
    expect(prisma.mapVietinTransaction.upsert).not.toHaveBeenCalled();
    expect(paymentNotifications.createForTransaction).not.toHaveBeenCalled();
  });

  it('derives the same transaction key for matching eFAST and MAP rows', () => {
    const normalizeTransaction = (service as any).normalizeTransaction.bind(
      service,
    );
    const efast = normalizeTransaction('CP75', {
      source: 'VIETIN_EFAST',
      trxId: '904T2670LCEG5P9N',
      trxRefNo: '331029',
      transactionNumber: '904T2670LCEG5P9N',
      txnReference: '331029',
      amount: 1390000,
      transactionDescription: '26071336553080 CP75',
      tranTime: '13/07/2026 16:07:42',
      status: 'SUCCESS',
    });
    const map = normalizeTransaction('CP75', {
      transactionNumber: '2026194045053',
      txnReference: '904T2670LCEG5P9N',
      amount: 1390000,
      transactionDescription: '26071336553080 CP75',
      tranTime: '13/07/2026 16:07:42',
      status: 'SUCCESS',
    });

    expect(efast).not.toBeNull();
    expect(map).not.toBeNull();
    expect(efast.transactionKey).toBe(map.transactionKey);
  });

  it('skips a MAP row when the matching eFAST statement already exists', async () => {
    prisma.mapVietinTransaction.findFirst.mockResolvedValue({
      id: 'existing-efast-transaction',
      transactionKey: 'CP75:legacy-efast-key',
      storeCode: 'CP75',
    });

    await expect(
      (service as any).persistTransactions('CP75', [
        {
          transactionNumber: '2026194045053',
          txnReference: '904T2670LCEG5P9N',
          amount: 1390000,
          transactionDescription: '26071336553080 CP75',
          tranTime: '13/07/2026 16:07:42',
          status: 'SUCCESS',
        },
      ]),
    ).resolves.toBe(0);

    expect(prisma.mapVietinTransaction.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          OR: expect.arrayContaining([
            { transactionNumber: '904T2670LCEG5P9N' },
            {
              rawData: {
                path: ['txnReference'],
                equals: '904T2670LCEG5P9N',
              },
            },
          ]),
        }),
      }),
    );
    expect(prisma.mapVietinTransaction.findUnique).toHaveBeenCalledTimes(2);
    expect(prisma.mapVietinTransaction.upsert).not.toHaveBeenCalled();
    expect(paymentNotifications.createForTransaction).not.toHaveBeenCalled();
  });

  it('reuses a legacy transaction key before running statement JSON lookup', async () => {
    const fallback = [
      '2026194045053',
      1390000,
      '2026-07-13T09:07:42.000Z',
      '26071336553080 CP75',
    ].join('|');
    const legacyTransactionKey = `CP75:${createHash('sha256')
      .update(`CP75|${fallback}`)
      .digest('hex')}`;
    const legacy = {
      id: 'existing-legacy-map',
      transactionKey: legacyTransactionKey,
      storeCode: 'CP75',
      orderSource: 'AUTO',
    };
    prisma.mapVietinTransaction.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(legacy);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({
      ...legacy,
      amount: 1390000,
    });

    await expect(
      (service as any).persistTransactions('CP75', [
        {
          transactionNumber: '2026194045053',
          txnReference: '904T2670LCEG5P9N',
          amount: 1390000,
          transactionDescription: '26071336553080 CP75',
          tranTime: '13/07/2026 16:07:42',
          status: 'SUCCESS',
        },
      ]),
    ).resolves.toBe(0);

    expect(prisma.mapVietinTransaction.findFirst).not.toHaveBeenCalled();
    expect(prisma.mapVietinTransaction.findUnique).toHaveBeenNthCalledWith(2, {
      where: { transactionKey: legacyTransactionKey },
    });
    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { transactionKey: legacyTransactionKey },
      }),
    );
    expect(paymentNotifications.createForTransaction).not.toHaveBeenCalled();
  });

  it('uses the bounded RAM fingerprint cache to skip repeated MAP DB reads', async () => {
    const row = globalTransaction('TXN-CACHE-001');
    const normalized = (service as any).normalizeTransaction('CP01', row);
    prisma.mapVietinTransaction.findUnique.mockResolvedValue({
      id: 'stored-cache-1',
      ...normalized,
      firstSeenAt: new Date('2026-05-21T03:00:00.000Z'),
    });
    const stats = { updated: 0, unchanged: 0, cacheHits: 0 };

    await expect(
      (service as any).persistTransactions('CP01', [row], stats),
    ).resolves.toBe(0);
    await expect(
      (service as any).persistTransactions('CP01', [row], stats),
    ).resolves.toBe(0);

    expect(stats).toEqual({ updated: 0, unchanged: 2, cacheHits: 1 });
    expect(prisma.mapVietinTransaction.findUnique).toHaveBeenCalledTimes(1);
    expect(prisma.mapVietinTransaction.upsert).not.toHaveBeenCalled();
  });

  it.each(['MANUAL', 'OFFSET'])(
    'preserves %s orders when a source sync refreshes the transaction',
    async (orderSource) => {
      const row = globalTransaction(`TXN-PROTECTED-${orderSource}`);
      const normalized = (service as any).normalizeTransaction('CP01', row);
      const existing = {
        id: `stored-${orderSource.toLowerCase()}`,
        ...normalized,
        content: 'Older transfer content',
        orders: ['26071712345678'],
        orderSource,
        firstSeenAt: new Date('2026-07-17T03:00:00.000Z'),
      };
      prisma.mapVietinTransaction.findUnique.mockResolvedValue(existing);
      prisma.mapVietinTransaction.upsert.mockResolvedValue({
        ...existing,
        content: normalized.content,
      });

      await expect(
        (service as any).persistTransactions('CP01', [row]),
      ).resolves.toBe(0);

      const update =
        prisma.mapVietinTransaction.upsert.mock.calls.at(-1)[0].update;
      expect(update).not.toHaveProperty('orders');
      expect(update).not.toHaveProperty('orderSource');
      expect(update.content).toBe(normalized.content);
    },
  );

  it('preserves a manually selected income type during source sync', async () => {
    const row = {
      ...globalTransaction('TXN-MANUAL-INCOME-TYPE'),
      transactionDescription: 'NHAT TIN THANH TOAN COD',
    };
    const normalized = (service as any).normalizeTransaction('CP01', row);
    const existing = {
      id: 'stored-manual-income-type',
      ...normalized,
      content: 'Older transfer content',
      incomeType: 'SALES',
      incomeTypeSource: 'MANUAL',
      firstSeenAt: new Date('2026-07-17T03:00:00.000Z'),
    };
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(existing);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({
      ...existing,
      content: normalized.content,
    });

    await expect(
      (service as any).persistTransactions('CP01', [row]),
    ).resolves.toBe(0);

    const update =
      prisma.mapVietinTransaction.upsert.mock.calls.at(-1)[0].update;
    expect(update).not.toHaveProperty('incomeType');
    expect(update).not.toHaveProperty('incomeTypeSource');
    expect(update.content).toBe(normalized.content);
  });

  it.each([
    {
      label: 'eFAST arrives after MAP',
      incomingSource: 'VIETIN_EFAST',
      candidateRawData: { transactionNumber: '2026198056714' },
    },
    {
      label: 'MAP arrives after eFAST',
      incomingSource: 'MAP',
      candidateRawData: { source: 'VIETIN_EFAST', trxId: '333985' },
    },
  ])(
    'skips a cross-source duplicate by exact bank fingerprint when $label',
    async ({ incomingSource, candidateRawData }) => {
      const row = {
        ...(incomingSource === 'VIETIN_EFAST'
          ? { source: 'VIETIN_EFAST' }
          : {}),
        transactionNumber:
          incomingSource === 'VIETIN_EFAST' ? '333985' : '2026198056714',
        trxId: incomingSource === 'VIETIN_EFAST' ? '333985' : undefined,
        amount: 9146000,
        transactionDescription: 'XNLD CAO THE TT TIEN CAMERA HD 2807',
        tranTime: '17/07/2026 17:25:40',
        status: 'SUCCESS',
      };
      prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
      prisma.mapVietinTransaction.findFirst.mockResolvedValue(null);
      prisma.mapVietinTransaction.findMany.mockResolvedValue([
        {
          id: 'stored-cross-source',
          transactionKey: 'CP61:existing-cross-source',
          storeCode: 'CP61',
          rawData: candidateRawData,
        },
      ]);

      await expect(
        (service as any).persistTransactions('CP61', [row]),
      ).resolves.toBe(0);

      expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            storeCode: 'CP61',
            amount: 9146000,
            content: 'XNLD CAO THE TT TIEN CAMERA HD 2807',
          }),
          take: 5,
        }),
      );
      expect(prisma.mapVietinTransaction.upsert).not.toHaveBeenCalled();
      expect(paymentNotifications.createForTransaction).not.toHaveBeenCalled();
    },
  );

  it('serializes MAP and eFAST persistence before checking the exact fingerprint', async () => {
    const baseRow = {
      amount: 9146000,
      transactionDescription: 'XNLD CAO THE TT TIEN CAMERA HD 2807',
      tranTime: '17/07/2026 17:25:40',
      status: 'SUCCESS',
    };
    const mapRow = {
      ...baseRow,
      transactionNumber: '2026198056714',
    };
    const efastRow = {
      ...baseRow,
      source: 'VIETIN_EFAST',
      transactionNumber: '333985',
      trxId: '333985',
    };
    let stored: any = null;
    prisma.mapVietinTransaction.findUnique.mockImplementation(
      async ({ where }: any) =>
        stored?.transactionKey === where.transactionKey ? stored : null,
    );
    prisma.mapVietinTransaction.findFirst.mockResolvedValue(null);
    prisma.mapVietinTransaction.findMany.mockImplementation(async () =>
      stored
        ? [
            {
              id: stored.id,
              transactionKey: stored.transactionKey,
              storeCode: stored.storeCode,
              rawData: stored.rawData,
            },
          ]
        : [],
    );
    prisma.mapVietinTransaction.upsert.mockImplementation(
      async ({ create }: any) => {
        await new Promise((resolve) => setTimeout(resolve, 10));
        stored = { id: 'stored-map-row', ...create };
        return stored;
      },
    );
    paymentNotifications.createForTransaction.mockResolvedValue({});

    const results = await Promise.all([
      (service as any).persistTransactions('CP61', [mapRow]),
      (service as any).persistTransactions('CP61', [efastRow]),
    ]);

    expect(results).toEqual([1, 0]);
    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledTimes(1);
    expect(paymentNotifications.createForTransaction).toHaveBeenCalledTimes(1);
  });

  it('maps eFAST rows by the receiving account when pmtId is missing', async () => {
    process.env.VIETIN_EFAST_USERNAME = 'efast-user';
    process.env.VIETIN_EFAST_PASSWORD = 'efast-pass';
    process.env.VIETIN_EFAST_BANK_ACCOUNTS = '123456789012';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '123456789012' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          status: { code: '1', message: 'LOGON_SUCCESS' },
          sessionId: 'efast-session-id',
          corpUser: { cifno: '1234561361' },
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          status: { code: '1', message: 'SUCCESS' },
          currentPage: 0,
          nextPage: 0,
          transactions: [
            {
              trxId: 'TRX-001',
              amount: 1250000,
              remark: 'Khach chuyen tien',
              tranDate: '21/05/2026 10:00:00',
              dorc: 'C',
            },
          ],
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({
      id: 'stored-efast-source-account',
      storeCode: 'CP01',
      amount: 1250000,
    });
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});
    paymentNotifications.createForTransaction.mockResolvedValue({});

    await expect(service.syncEfastTransactions()).resolves.toEqual({
      created: 1,
      quarantined: 0,
      fetched: 1,
      creditRows: 1,
    });

    expect(prisma.mapVietinTransaction.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ storeCode: null }),
        data: { storeCode: 'CP01' },
      }),
    );
    expect(prisma.mapVietinUnmappedTransaction.upsert).not.toHaveBeenCalled();
    expect(paymentNotifications.createForTransaction).toHaveBeenCalledWith(
      expect.objectContaining({
        id: 'stored-efast-source-account',
        storeCode: 'CP01',
      }),
    );
    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({
          storeCode: 'CP01',
          transactionNumber: 'TRX-001',
          transactionKey: expect.stringMatching(/^CP01:/),
          rawData: expect.objectContaining({
            virtualAccount: '',
            efastCreditAccountNo: '123456789012',
          }),
        }),
      }),
    );
  });

  it('keeps eFAST rows unassigned when neither pmtId nor source account maps', async () => {
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({
      id: 'stored-efast-null-store',
      storeCode: null,
      amount: 1250000,
    });

    await expect(
      (service as any).persistGlobalTransactions(
        [
          {
            source: 'VIETIN_EFAST',
            trxId: 'TRX-UNASSIGNED',
            transactionNumber: 'TRX-UNASSIGNED',
            amount: 1250000,
            transactionDescription: 'Khach chuyen tien',
            tranTime: '21/05/2026 10:00:00',
            transactionStatus: 'SUCCESS',
            virtualAccount: '',
            efastCreditAccountNo: '999999999999',
            efastBankAccountNo: '999999999999',
          },
        ],
        new Map(),
      ),
    ).resolves.toMatchObject({ created: 1, quarantined: 0 });

    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({
          storeCode: null,
          transactionKey: expect.stringMatching(/^__NO_STORE__:/),
        }),
      }),
    );
  });

  it('caps eFAST history sync to one page per configured account', async () => {
    process.env.VIETIN_EFAST_USERNAME = 'efast-user';
    process.env.VIETIN_EFAST_PASSWORD = 'efast-pass';
    process.env.VIETIN_EFAST_BANK_ACCOUNTS = '123456789012';
    process.env.VIETIN_EFAST_SYNC_MAX_PAGES = '2';
    prisma.store.findMany.mockResolvedValue([]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          status: { code: '1', message: 'LOGON_SUCCESS' },
          sessionId: 'efast-session-id',
          corpUser: { cifno: '1234561361' },
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          status: { code: '1', message: 'SUCCESS' },
          currentPage: 0,
          nextPage: 1,
          transactions: Array.from({ length: 150 }, (_, index) => ({
            trxId: `TRX-${index}`,
            amount: 1000 + index,
            remark: 'Khach chuyen tien',
            tranDate: '21/05/2026 10:00:00',
            dorc: 'C',
          })),
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({
      id: 'stored-efast-null-store',
      storeCode: null,
      amount: 1000,
    });
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(service.syncEfastTransactions()).resolves.toEqual({
      created: 150,
      quarantined: 0,
      fetched: 150,
      creditRows: 150,
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(String(fetchMock.mock.calls[1][0])).toContain('/account/history');
    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledTimes(150);
  });

  it('runs configured MAP sync before the Vietnam fast window', async () => {
    (Date.now as jest.Mock).mockReturnValue(
      new Date('2026-05-20T23:59:59.000Z').getTime(),
    );
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';

    await expect(service.syncConfiguredStores()).resolves.toBeUndefined();

    expect(fetchMock).toHaveBeenCalled();
  });

  it('runs configured MAP sync at 22:00 Vietnam time', async () => {
    (Date.now as jest.Mock).mockReturnValue(
      new Date('2026-05-21T15:00:00.000Z').getTime(),
    );
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';

    await expect(service.syncConfiguredStores()).resolves.toBeUndefined();

    expect(fetchMock).toHaveBeenCalled();
  });

  it('formats provider sync dates in Vietnam time', () => {
    expect(
      (service as any).formatMapDate(new Date('2026-07-10T18:07:00.000Z')),
    ).toBe('11/07/2026');
  });

  it('uses a 1000-2000ms random delay for scheduled MAP history sync', () => {
    jest
      .spyOn(Math, 'random')
      .mockReturnValueOnce(0)
      .mockReturnValueOnce(0.99999);

    expect((service as any).randomMapHistorySyncDelayMs()).toBe(1000);
    expect((service as any).randomMapHistorySyncDelayMs()).toBe(2000);
  });

  it('supports a bounded MAP sync delay override', () => {
    process.env.MAP_VIETIN_SYNC_DELAY_MIN_MS = '750';
    process.env.MAP_VIETIN_SYNC_DELAY_MAX_MS = '1250';
    jest
      .spyOn(Math, 'random')
      .mockReturnValueOnce(0)
      .mockReturnValueOnce(0.99999);

    expect((service as any).randomMapHistorySyncDelayMs()).toBe(750);
    expect((service as any).randomMapHistorySyncDelayMs()).toBe(1250);
  });

  it('clamps unsafe MAP sync delay overrides to 500ms', () => {
    process.env.MAP_VIETIN_SYNC_DELAY_MIN_MS = '1';
    process.env.MAP_VIETIN_SYNC_DELAY_MAX_MS = '2';
    jest.spyOn(Math, 'random').mockReturnValue(0);

    expect((service as any).randomMapHistorySyncDelayMs()).toBe(500);
  });

  it('uses a 30000-60000ms random delay for MAP page-2 deep sweeps', () => {
    jest
      .spyOn(Math, 'random')
      .mockReturnValueOnce(0)
      .mockReturnValueOnce(0.99999);

    expect((service as any).randomMapDeepSweepDelayMs()).toBe(30000);
    expect((service as any).randomMapDeepSweepDelayMs()).toBe(60000);
  });

  it('schedules an immediate MAP deep sweep on module startup', () => {
    const setTimeoutSpy = jest.spyOn(global, 'setTimeout');

    service.onModuleInit();

    expect(setTimeoutSpy).toHaveBeenCalledWith(expect.any(Function), 0);
    service.onModuleDestroy();
  });

  it('schedules the next MAP history sync at the 07:00 Vietnam fast-window start', () => {
    expect(
      (service as any).nextMapHistorySyncDelayMs(
        new Date('2026-05-20T23:50:00.000Z'),
      ),
    ).toBe(10 * 60 * 1000);
    expect(
      (service as any).nextMapHistorySyncDelayMs(
        new Date('2026-05-20T23:59:59.000Z'),
      ),
    ).toBe(1000);
  });

  it('keeps the night cadence when the next MAP fast window is more than 30 minutes away', () => {
    expect(
      (service as any).nextMapHistorySyncDelayMs(
        new Date('2026-05-21T15:01:00.000Z'),
      ),
    ).toBe(30 * 60 * 1000);
  });

  it('uses the fast MAP sync cadence at 07:00 Vietnam time', () => {
    jest.spyOn(Math, 'random').mockReturnValue(0);

    expect(
      (service as any).nextMapHistorySyncDelayMs(
        new Date('2026-05-21T00:00:00.000Z'),
      ),
    ).toBe(1000);
  });

  it('uses a 50000-60000ms random delay for fast eFAST sync', () => {
    jest
      .spyOn(Math, 'random')
      .mockReturnValueOnce(0)
      .mockReturnValueOnce(0.99999);

    expect((service as any).randomEfastFastSyncDelayMs()).toBe(50000);
    expect((service as any).randomEfastFastSyncDelayMs()).toBe(60000);
  });

  it('schedules eFAST at 08:00 Vietnam time when the fast window is about to open', () => {
    expect(
      (service as any).nextEfastSyncDelayMs(
        new Date('2026-05-21T00:59:30.000Z'),
      ),
    ).toBe(30 * 1000);
    expect(
      (service as any).nextEfastSyncDelayMs(
        new Date('2026-05-21T00:59:59.000Z'),
      ),
    ).toBe(1000);
  });

  it('uses the fast eFAST cadence from 08:00 through 22:00 Vietnam time', () => {
    jest.spyOn(Math, 'random').mockReturnValue(0);

    expect(
      (service as any).nextEfastSyncDelayMs(
        new Date('2026-05-21T01:00:00.000Z'),
      ),
    ).toBe(50000);
    expect(
      (service as any).nextEfastSyncDelayMs(
        new Date('2026-05-21T15:00:00.000Z'),
      ),
    ).toBe(50000);
  });

  it('uses the eFAST night cadence from 22:01 through 07:59 Vietnam time', () => {
    expect(
      (service as any).nextEfastSyncDelayMs(
        new Date('2026-05-21T15:01:00.000Z'),
      ),
    ).toBe(30 * 60 * 1000);
    expect(
      (service as any).nextEfastSyncDelayMs(
        new Date('2026-05-21T23:30:00.000Z'),
      ),
    ).toBe(30 * 60 * 1000);
  });

  it('does not start the MAP history scheduler when MAP sync is disabled', () => {
    process.env.MAP_VIETIN_SYNC_ENABLED = 'false';
    const setTimeoutSpy = jest.spyOn(global, 'setTimeout');
    const disabledService = new MapVietinService(
      prisma,
      policyService as any,
      featureService as any,
      paymentNotifications as any,
      redisService as any,
    );

    disabledService.onModuleInit();

    expect(setTimeoutSpy).not.toHaveBeenCalled();
  });

  it('starts the eFAST scheduler independently when MAP sync is disabled', () => {
    process.env.MAP_VIETIN_SYNC_ENABLED = 'false';
    process.env.VIETIN_EFAST_SYNC_ENABLED = 'true';
    jest.spyOn(Math, 'random').mockReturnValue(0);
    const setTimeoutSpy = jest.spyOn(global, 'setTimeout');
    const efastOnlyService = new MapVietinService(
      prisma,
      policyService as any,
      featureService as any,
      paymentNotifications as any,
      redisService as any,
    );

    efastOnlyService.onModuleInit();

    expect(setTimeoutSpy).toHaveBeenCalledWith(expect.any(Function), 50000);
    efastOnlyService.onModuleDestroy();
  });

  it('schedules the next MAP history sync only after the current run finishes', async () => {
    jest.spyOn(Math, 'random').mockReturnValue(0.5);
    const setTimeoutSpy = jest.spyOn(global, 'setTimeout');
    let resolveSync!: () => void;
    jest.spyOn(service, 'syncConfiguredStores').mockReturnValue(
      new Promise<void>((resolve) => {
        resolveSync = resolve;
      }),
    );

    const runPromise = (service as any).runScheduledMapHistorySync();
    await Promise.resolve();

    expect(service.syncConfiguredStores).toHaveBeenCalledTimes(1);
    expect(setTimeoutSpy).not.toHaveBeenCalled();

    resolveSync();
    await runPromise;

    expect(setTimeoutSpy).toHaveBeenCalledWith(expect.any(Function), 1500);
    service.onModuleDestroy();
  });

  it('uses page 1 for fast MAP loops between deep sweeps', async () => {
    jest.spyOn(Math, 'random').mockReturnValue(0);
    (service as any).mapHistoryDeepSweepDueAt = Date.now() + 60_000;
    jest.spyOn(service, 'syncConfiguredStores').mockResolvedValue(undefined);

    await (service as any).runScheduledMapHistorySync();

    expect(service.syncConfiguredStores).toHaveBeenCalledWith({
      mode: 'fast_page',
      maxPages: 1,
    });
    service.onModuleDestroy();
  });

  it('uses the configured page cap when a MAP deep sweep is due', async () => {
    jest.spyOn(Math, 'random').mockReturnValue(0);
    (service as any).mapHistoryDeepSweepDueAt = 0;
    jest.spyOn(service, 'syncConfiguredStores').mockResolvedValue(undefined);

    await (service as any).runScheduledMapHistorySync();

    expect(service.syncConfiguredStores).toHaveBeenCalledWith({
      mode: 'deep_sweep',
      maxPages: 2,
    });
    service.onModuleDestroy();
  });

  it('reuses cached global MAP session across sync loops', async () => {
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    process.env.MAP_VIETIN_GLOBAL_SESSION_TTL_SECONDS = '600';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: { list: [globalTransaction('TXN-001')], total: 1 },
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: { list: [globalTransaction('TXN-002')], total: 1 },
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({});
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(service.syncGlobalTransactions()).resolves.toEqual({
      created: 1,
      quarantined: 0,
    });
    await expect(service.syncGlobalTransactions()).resolves.toEqual({
      created: 1,
      quarantined: 0,
    });

    const loginCalls = fetchMock.mock.calls.filter((call) =>
      String(call[0]).endsWith('/login'),
    );
    expect(loginCalls).toHaveLength(1);
    expect(fetchMock.mock.calls[2][1].headers).toEqual(
      expect.objectContaining({ Authorization: 'Bearer access-token' }),
    );
  });

  it('refreshes cached global MAP session after an auth rejection', async () => {
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'old-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: { list: [globalTransaction('TXN-001')], total: 1 },
        }),
      )
      .mockResolvedValueOnce(httpResponse(401, { message: 'Unauthorized' }))
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'new-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: { list: [globalTransaction('TXN-002')], total: 1 },
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({});
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(service.syncGlobalTransactions()).resolves.toEqual({
      created: 1,
      quarantined: 0,
    });
    await expect(service.syncGlobalTransactions()).resolves.toEqual({
      created: 1,
      quarantined: 0,
    });

    const loginCalls = fetchMock.mock.calls.filter((call) =>
      String(call[0]).endsWith('/login'),
    );
    expect(loginCalls).toHaveLength(2);
    expect(fetchMock.mock.calls[2][1].headers).toEqual(
      expect.objectContaining({ Authorization: 'Bearer old-token' }),
    );
    expect(fetchMock.mock.calls[4][1].headers).toEqual(
      expect.objectContaining({ Authorization: 'Bearer new-token' }),
    );
  });

  it('keeps scheduled fast MAP sync on page 1', async () => {
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [globalTransaction('TXN-FAST-001')],
            pageIndex: 0,
            pageSize: 100,
            total: 301,
          },
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({});
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(
      service.syncGlobalTransactions({ mode: 'fast_page', maxPages: 1 }),
    ).resolves.toEqual({ created: 1, quarantined: 0 });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[1][0]).toContain('page=0&size=100');
  });

  it('runs a deep sweep after refreshing a rejected MAP session', async () => {
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'old-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(httpResponse(403, { message: 'Forbidden' }))
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'new-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [globalTransaction('TXN-RECOVERY-001')],
            pageIndex: 0,
            pageSize: 100,
            total: 301,
          },
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [globalTransaction('TXN-RECOVERY-002')],
            pageIndex: 1,
            pageSize: 100,
            total: 301,
          },
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({});
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(
      service.syncGlobalTransactions({ mode: 'fast_page', maxPages: 1 }),
    ).resolves.toEqual({ created: 2, quarantined: 0 });

    expect(fetchMock).toHaveBeenCalledTimes(5);
    expect(fetchMock.mock.calls[4][0]).toContain('page=1&size=100');
    expect((service as any).mapProviderBackoffAttempt).toBe(0);
  });

  it('backs scheduled MAP sync off for 30 seconds after HTTP 429', async () => {
    jest.spyOn(Math, 'random').mockReturnValue(0);
    const setTimeoutSpy = jest.spyOn(global, 'setTimeout');
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        httpResponse(429, { message: 'Too Many Requests' }),
      );
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(
      service.syncGlobalTransactions({ mode: 'fast_page', maxPages: 1 }),
    ).resolves.toEqual({ created: 0, quarantined: 0 });
    (service as any).scheduleNextMapHistorySync();

    expect((service as any).mapProviderBackoffAttempt).toBe(1);
    expect(setTimeoutSpy).toHaveBeenLastCalledWith(expect.any(Function), 30000);
    service.onModuleDestroy();
  });

  it('caps repeated MAP HTTP 429 backoff at 2 minutes before jitter', () => {
    jest.spyOn(Math, 'random').mockReturnValue(0);

    (service as any).registerMapProviderBackoff(429);
    expect((service as any).mapProviderBackoffUntil - Date.now()).toBe(30000);
    (service as any).registerMapProviderBackoff(429);
    expect((service as any).mapProviderBackoffUntil - Date.now()).toBe(60000);
    (service as any).registerMapProviderBackoff(429);
    expect((service as any).mapProviderBackoffUntil - Date.now()).toBe(120000);
    (service as any).registerMapProviderBackoff(429);
    expect((service as any).mapProviderBackoffUntil - Date.now()).toBe(120000);
  });

  it('honors provider Retry-After and suppresses direct MAP sync during cooldown', async () => {
    jest.spyOn(Math, 'random').mockReturnValue(0);
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        httpResponse(
          429,
          { message: 'Too Many Requests' },
          { 'retry-after': '90' },
        ),
      );
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(
      service.syncGlobalTransactions({ mode: 'fast_page', maxPages: 1 }),
    ).resolves.toEqual({ created: 0, quarantined: 0 });
    await expect(
      service.syncGlobalTransactions({ mode: 'fast_page', maxPages: 1 }),
    ).resolves.toEqual({ created: 0, quarantined: 0 });

    expect((service as any).mapProviderBackoffUntil - Date.now()).toBe(90_000);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('backs scheduled MAP sync off for 5 minutes after persistent HTTP 403', async () => {
    jest.spyOn(Math, 'random').mockReturnValue(0);
    const setTimeoutSpy = jest.spyOn(global, 'setTimeout');
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'old-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(httpResponse(403, { message: 'Forbidden' }))
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'new-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(httpResponse(403, { message: 'Forbidden' }));
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(
      service.syncGlobalTransactions({ mode: 'fast_page', maxPages: 1 }),
    ).resolves.toEqual({ created: 0, quarantined: 0 });
    (service as any).scheduleNextMapHistorySync();

    expect((service as any).mapProviderBackoffAttempt).toBe(1);
    expect(setTimeoutSpy).toHaveBeenLastCalledWith(
      expect.any(Function),
      5 * 60 * 1000,
    );
    service.onModuleDestroy();
  });

  it('uses 100-row pages and stops global MAP sync at the default page cap', async () => {
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [globalTransaction('TXN-001')],
            pageIndex: 0,
            pageSize: 100,
            total: 301,
          },
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [globalTransaction('TXN-002')],
            pageIndex: 1,
            pageSize: 100,
            total: 301,
          },
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({});
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(service.syncGlobalTransactions()).resolves.toEqual({
      created: 2,
      quarantined: 0,
    });

    expect(fetchMock.mock.calls[1][0]).toContain('page=0&size=100');
    expect(fetchMock.mock.calls[2][0]).toContain('page=1&size=100');
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledTimes(2);
  });

  it('lets MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES override the default page cap', async () => {
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    process.env.MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES = '3';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [globalTransaction('TXN-001')],
            pageIndex: 0,
            pageSize: 100,
            total: 201,
          },
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [globalTransaction('TXN-002')],
            pageIndex: 1,
            pageSize: 100,
            total: 201,
          },
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [globalTransaction('TXN-003')],
            pageIndex: 2,
            pageSize: 100,
            total: 201,
          },
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({});
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(service.syncGlobalTransactions()).resolves.toEqual({
      created: 3,
      quarantined: 0,
    });

    expect(fetchMock.mock.calls[1][0]).toContain('page=0&size=100');
    expect(fetchMock.mock.calls[2][0]).toContain('page=1&size=100');
    expect(fetchMock.mock.calls[3][0]).toContain('page=2&size=100');
    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledTimes(3);
  });

  it('quarantines global transactions when virtual account has no store match', async () => {
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '111' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [globalTransaction('TXN-001', '222')],
            pageIndex: 0,
            pageSize: 100,
            total: 1,
          },
        }),
      );
    prisma.mapVietinUnmappedTransaction.upsert.mockResolvedValue({});
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(service.syncGlobalTransactions()).resolves.toEqual({
      created: 0,
      quarantined: 1,
    });

    expect(prisma.mapVietinTransaction.upsert).not.toHaveBeenCalled();
    expect(paymentNotifications.createForTransaction).not.toHaveBeenCalled();
    expect(prisma.mapVietinUnmappedTransaction.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({
          virtualAccount: '222',
          reason: 'UNMAPPED_ACCOUNT',
          transactionNumber: 'TXN-001',
        }),
      }),
    );
  });

  it('quarantines global transactions when virtual account maps to multiple stores', async () => {
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', transferAccountNumber: '18PVICU' },
      { storeId: 'CP02', transferAccountNumber: '18-PV ICU' },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [globalTransaction('TXN-001')],
            pageIndex: 0,
            pageSize: 100,
            total: 1,
          },
        }),
      );
    prisma.mapVietinUnmappedTransaction.upsert.mockResolvedValue({});
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(service.syncGlobalTransactions()).resolves.toEqual({
      created: 0,
      quarantined: 1,
    });

    expect(prisma.mapVietinTransaction.upsert).not.toHaveBeenCalled();
    expect(prisma.mapVietinUnmappedTransaction.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ reason: 'AMBIGUOUS_ACCOUNT' }),
      }),
    );
  });

  it('falls back to per-store sync when global credentials are missing', async () => {
    prisma.store.findMany.mockResolvedValue([
      {
        storeId: 'CP01',
        mapVietinUsername: 'map-user',
        mapVietinPasswordCipher: encryptSecret('map-pass'),
      },
    ]);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: { list: [globalTransaction('TXN-001')], total: 1 },
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(null);
    prisma.mapVietinTransaction.upsert.mockResolvedValue({});
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(service.syncConfiguredStores()).resolves.toBeUndefined();

    expect(prisma.store.findMany).toHaveBeenCalledWith({
      where: {
        mapVietinUsername: { not: null },
        mapVietinPasswordCipher: { not: null },
      },
    });
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).username).toBe(
      'map-user',
    );
    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ storeCode: 'CP01' }),
      }),
    );
  });

  it('lists stored transactions for the signed-in user store', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([
      {
        id: 'stored-1',
        storeCode: 'CP01',
        transactionKey: 'CP01:key',
        transactionNumber: 'TXN-001',
        amount: 1250000,
        content: 'Khach chuyen tien',
        status: '00',
        paidAt: new Date('2026-05-21T03:00:00.000Z'),
        payerName: null,
        payerAccount: null,
        rawData: {
          reqCardName: 'NGUYEN VAN A',
          reqCardNo: '9704361234567890',
          txnReference: '00020300000000004567',
        },
        firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
      },
    ]);
    prisma.mapVietinTransaction.count.mockResolvedValue(1);

    await expect(
      service.listStoredTransactions(
        { role: 'STAFF', storeId: 'store-uuid-1' },
        { date: '2026-05-21', page: 0, limit: 10 },
      ),
    ).resolves.toMatchObject({
      storeId: 'CP01',
      page: 0,
      limit: 10,
      total: 1,
      list: [
        {
          id: 'stored-1',
          transactionNumber: 'TXN-001',
          transactionReference: '00020300000000004567',
          amount: 1250000,
          payerName: 'NGUYEN VAN A',
          payerAccount: '9704361234567890',
        },
      ],
    });

    expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ storeCode: 'CP01' }),
        skip: 0,
        take: 10,
      }),
    );
    expect(prisma.mapVietinTransaction.count).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ storeCode: 'CP01' }),
      }),
    );
  });

  it('exposes the eFAST trxId as the product-facing statement number', () => {
    const resolveStoredTransactionReference = (
      service as any
    ).resolveStoredTransactionReference.bind(service);

    expect(
      resolveStoredTransactionReference({
        transactionNumber: '904D60713M9LLR5M',
        rawData: {
          source: 'VIETIN_EFAST',
          trxId: '904D60713M9LLR5M',
          trxRefNo: '331225',
          txnReference: '331225',
        },
      }),
    ).toBe('904D60713M9LLR5M');
  });

  it('lists stored transactions across a Vietnam-local date range', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await expect(
      service.listStoredTransactions(
        { role: 'STAFF', storeId: 'store-uuid-1' },
        {
          startDate: '2026-05-23',
          endDate: '2026-05-27',
          page: 0,
          limit: 10,
        },
      ),
    ).resolves.toMatchObject({
      storeId: 'CP01',
      page: 0,
      limit: 10,
      total: 0,
      list: [],
    });

    const where = prisma.mapVietinTransaction.findMany.mock.calls[0][0].where;
    expect(where.OR[0].paidAt).toEqual({
      gte: new Date('2026-05-22T17:00:00.000Z'),
      lt: new Date('2026-05-27T17:00:00.000Z'),
    });
    expect(where.OR[1].firstSeenAt).toEqual({
      gte: new Date('2026-05-22T17:00:00.000Z'),
      lt: new Date('2026-05-27T17:00:00.000Z'),
    });
  });

  it('skips total count for lightweight monitor refreshes', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);

    const result = await service.listStoredTransactions(
      { role: 'STAFF', storeId: 'store-uuid-1' },
      {
        date: '2026-05-21',
        page: 0,
        limit: 10,
        includeTotal: 'false',
      },
    );

    expect(result).toMatchObject({
      storeId: 'CP01',
      page: 0,
      limit: 10,
      list: [],
    });
    expect(result).not.toHaveProperty('total');
    expect(prisma.mapVietinTransaction.count).not.toHaveBeenCalled();
  });

  it('lists payment transactions but disables order actions without statement access', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([
      {
        id: 'stored-no-statement',
        storeCode: 'CP01',
        transactionKey: 'CP01:no-statement',
        transactionNumber: 'TXN-NO-STATEMENT',
        amount: 1250000,
        content: 'No statement permission',
        orders: [],
        orderSource: null,
        orderUpdatedAt: null,
        orderUpdatedByUserId: null,
        orderUpdatedByEmail: null,
        status: '00',
        paidAt: new Date('2026-05-21T03:00:00.000Z'),
        payerName: null,
        payerAccount: null,
        rawData: null,
        firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
        orderTransferRequests: [],
      },
    ]);
    prisma.mapVietinTransaction.count.mockResolvedValue(1);

    await expect(
      service.listStoredTransactions(
        {
          role: 'USER',
          storeId: 'store-uuid-1',
          featureBankStatements: false,
        },
        { date: '2026-05-21', page: 0, limit: 10 },
      ),
    ).resolves.toMatchObject({
      canReviewOrderTransfers: false,
      total: 1,
      list: [
        {
          id: 'stored-no-statement',
          canEditOrders: false,
          orderEditBlockedReason:
            'Bạn cần quyền Sao kê để cập nhật mã đơn hàng.',
          canRequestOrderTransfer: false,
          orderTransferRequestBlockedReason:
            'Bạn cần quyền Sao kê để cập nhật mã đơn hàng.',
        },
      ],
    });
  });

  it('includes pending order-transfer requests in payment transactions', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([
      {
        id: 'stored-pending',
        storeCode: 'CP01',
        transactionKey: 'CP01:pending',
        transactionNumber: 'TXN-PENDING',
        amount: 1250000,
        content: 'Pending order transfer',
        orders: ['26052112345678'],
        orderSource: 'AUTO',
        orderUpdatedAt: null,
        orderUpdatedByUserId: null,
        orderUpdatedByEmail: null,
        status: '00',
        paidAt: new Date('2026-05-21T03:00:00.000Z'),
        payerName: null,
        payerAccount: null,
        rawData: null,
        firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
        orderTransferRequests: [
          {
            id: 'request-1',
            requestedOrders: ['26052287654321'],
            status: 'PENDING',
            requestedByUserId: 'requester-1',
            requestedByEmail: 'requester@example.com',
            reviewNote: null,
            createdAt: new Date('2026-05-21T04:00:00.000Z'),
          },
        ],
      },
    ]);
    prisma.mapVietinTransaction.count.mockResolvedValue(1);

    await expect(
      service.listStoredTransactions(
        {
          role: 'MANAGER',
          storeId: 'store-uuid-1',
          departmentCode: 'ACC',
        },
        { date: '2026-05-21', page: 0, limit: 10 },
      ),
    ).resolves.toMatchObject({
      canReviewOrderTransfers: true,
      list: [
        {
          id: 'stored-pending',
          canEditOrders: false,
          orderEditBlockedReason: 'Giao dịch đang chờ Kế toán xác nhận.',
          canRequestOrderTransfer: false,
          orderTransferRequestBlockedReason:
            'Giao dịch đang chờ Kế toán xác nhận.',
          hasPendingOrderTransferRequest: true,
          orderTransferRequestId: 'request-1',
          orderTransferRequestedOrders: ['26052287654321'],
        },
      ],
    });
    expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        include: {
          orderTransferRequests: {
            where: { status: 'PENDING' },
            orderBy: { createdAt: 'desc' },
            take: 1,
          },
        },
      }),
    );
  });

  it('extracts all valid unique order codes from transfer content', () => {
    expect(
      service.extractOrderCodesFromContent(
        'DH 26052912345678, 26053087654321; invalid 26023011111111 repeat 26052912345678 long 1260529123456789',
      ),
    ).toEqual(['26052912345678', '26053087654321']);
  });

  it('does not overwrite manually edited orders during sync', async () => {
    const store = {
      storeId: 'CP01',
      mapVietinUsername: 'map-user',
      mapVietinPasswordCipher: encryptSecret('map-pass'),
    };
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({
          access_token: 'access-token',
          merchant_info: [{ merchant_id: 'merchant-default' }],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: {
            list: [
              {
                txnNo: 'TXN-001',
                txnAmount: '1,250,000',
                txnDate: '21/05/2026 10:00:00',
                txnDesc: 'Auto sees 26052112345678',
                status: '00',
              },
            ],
          },
        }),
      );
    prisma.mapVietinTransaction.findUnique.mockResolvedValue({
      id: 'stored-1',
      orderSource: 'MANUAL',
      orders: ['26052099999999'],
    });
    prisma.mapVietinTransaction.upsert.mockResolvedValue({});
    prisma.mapVietinSyncState.upsert.mockResolvedValue({});

    await expect(service.syncStoreTransactions(store)).resolves.toBe(0);

    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        update: expect.not.objectContaining({ orders: expect.anything() }),
      }),
    );
  });

  it('keeps status and date filters inside assigned store scope', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await expect(
      service.listStatements(
        { role: 'MANAGER', storeId: 'store-uuid-1' },
        {
          orderStatus: 'HAS_ORDER',
          startDate: '2026-05-29',
          endDate: '2026-05-29',
          page: 0,
          limit: 20,
        },
      ),
    ).resolves.toMatchObject({ total: 0, list: [] });

    const where = prisma.mapVietinTransaction.findMany.mock.calls[0][0].where;
    expect(JSON.stringify(where)).toContain('CP01');
    expect(JSON.stringify(where)).toContain('isEmpty');
  });

  it.each([
    ['amount', { amount: '1250000' }, '1250000'],
    ['order', { order: '26052912345678' }, '26052912345678'],
    [
      'statement number',
      { statementNumber: '00020300000000004567' },
      '00020300000000004567',
    ],
    ['transfer content', { content: 'khach chuyen tien' }, 'khach chuyen tien'],
  ])(
    'searches statements by %s across all accounts for scoped users',
    async (_name, input, expectedMarker) => {
      prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
      prisma.mapVietinTransaction.count.mockResolvedValue(0);

      await expect(
        service.listStatements(
          { role: 'MANAGER', storeId: 'store-uuid-1' },
          { ...input, page: 0, limit: 20 },
        ),
      ).resolves.toMatchObject({ total: 0, list: [] });

      const where =
        prisma.mapVietinTransaction.findMany.mock.calls.at(-1)[0].where;
      const serializedWhere = JSON.stringify(where);
      expect(serializedWhere).toContain(expectedMarker);
      expect(serializedWhere).not.toContain('storeCode');
      expect(serializedWhere).not.toContain('CP01');
    },
  );

  it('filters statements by displayed statement number', async () => {
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await expect(
      service.listStatements(
        { role: 'SUPER_ADMIN' },
        {
          statementNumber: '00020300000000004567',
          startDate: '2026-05-29',
          endDate: '2026-05-29',
          page: 0,
          limit: 20,
        },
      ),
    ).resolves.toMatchObject({ total: 0, list: [] });

    const where = prisma.mapVietinTransaction.findMany.mock.calls[0][0].where;
    expect(JSON.stringify(where)).toContain('transactionNumber');
    expect(JSON.stringify(where)).toContain('txnReference');
    expect(JSON.stringify(where)).toContain('00020300000000004567');
  });

  it('returns statement order edit flags for visible rows', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([
      {
        id: 'has-order',
        storeCode: 'CP01',
        transactionKey: 'CP01:has-order',
        transactionNumber: 'TXN-HAS',
        amount: 1250000,
        content: 'Auto order',
        orders: ['26052912345678'],
        orderSource: 'AUTO',
        orderUpdatedAt: null,
        orderUpdatedByUserId: null,
        orderUpdatedByEmail: null,
        status: '00',
        paidAt: null,
        payerName: null,
        payerAccount: null,
        firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
      },
      {
        id: 'null-order',
        storeCode: 'CP01',
        transactionKey: 'CP01:null-order',
        transactionNumber: 'TXN-NULL',
        amount: 1250000,
        content: 'No order',
        orders: [],
        orderSource: null,
        orderUpdatedAt: null,
        orderUpdatedByUserId: null,
        orderUpdatedByEmail: null,
        status: '00',
        paidAt: null,
        payerName: null,
        payerAccount: null,
        firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
      },
    ]);
    prisma.mapVietinTransaction.count.mockResolvedValue(2);

    await expect(
      service.listStatements(
        { role: 'MANAGER', storeId: 'store-uuid-1' },
        { orderStatus: 'ALL', startDate: '2026-05-29', endDate: '2026-05-29' },
      ),
    ).resolves.toMatchObject({
      total: 2,
      list: [
        {
          id: 'has-order',
          canEditOrders: false,
          orderEditBlockedReason: 'Bạn không có quyền sửa đơn hàng.',
        },
        { id: 'null-order', canEditOrders: true, orderEditBlockedReason: null },
      ],
    });
  });

  it('includes null-store statements for phongvu.vn users in their default statement scope', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([
      {
        id: 'null-store',
        storeCode: null,
        transactionKey: '__NO_STORE__:key',
        transactionNumber: 'TRX-NO-PMT',
        amount: 1250000,
        content: 'No pmtId',
        orders: [],
        orderSource: null,
        orderUpdatedAt: null,
        orderUpdatedByUserId: null,
        orderUpdatedByEmail: null,
        status: 'SUCCESS',
        paidAt: null,
        payerName: null,
        payerAccount: null,
        firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
      },
    ]);
    prisma.mapVietinTransaction.count.mockResolvedValue(1);

    await expect(
      service.listStatements(
        {
          role: 'STAFF',
          email: 'staff@phongvu.vn',
          storeId: 'store-uuid-1',
        },
        { orderStatus: 'MISSING_ORDER', page: 0, limit: 20 },
      ),
    ).resolves.toMatchObject({
      total: 1,
      list: [
        {
          id: 'null-store',
          storeId: null,
          canEditOrders: true,
          canRequestOrderTransfer: false,
        },
      ],
    });

    const where = prisma.mapVietinTransaction.findMany.mock.calls[0][0].where;
    expect(JSON.stringify(where)).toContain('"storeCode":null');
  });

  it('includes null-store statements for users under the finance node', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await expect(
      service.listStatements(
        {
          id: 'fin-node-user',
          role: 'STAFF',
          email: 'fin-node@example.com',
          storeId: 'store-uuid-1',
        },
        { orderStatus: 'MISSING_ORDER', page: 0, limit: 20 },
      ),
    ).resolves.toMatchObject({ total: 0, list: [] });

    const where = prisma.mapVietinTransaction.findMany.mock.calls[0][0].where;
    expect(JSON.stringify(where)).toContain('"storeCode":null');
  });

  it('filters statements by selected SR codes for super admin', async () => {
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await expect(
      service.listStatements(
        { role: 'SUPER_ADMIN' },
        { storeIds: 'cp01, CP02', page: 0, limit: 20 },
      ),
    ).resolves.toMatchObject({ total: 0, list: [] });

    expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          AND: expect.arrayContaining([
            { storeCode: { in: ['CP01', 'CP02'] } },
            { incomeType: 'SALES' },
          ]),
        },
      }),
    );
    expect(prisma.store.findUnique).not.toHaveBeenCalled();
  });

  it.each([
    ['statement number', { statementNumber: 'MAP-CROSS' }, 'MAP-CROSS'],
    ['order', { order: '26052912345678' }, '26052912345678'],
    ['amount', { amount: '1250000' }, '1250000'],
    [
      'transfer content',
      { content: 'Cross SR order fix' },
      'Cross SR order fix',
    ],
  ])(
    'allows exact %s lookup across SR and marks the row editable',
    async (_name, input, marker) => {
      prisma.store.findUnique.mockResolvedValue({
        id: 'store-uuid-1',
        storeId: 'CP01',
      });
      prisma.mapVietinTransaction.findMany.mockResolvedValue([
        {
          id: 'cross-sr',
          storeCode: 'CP02',
          transactionKey: 'CP02:key',
          transactionNumber: 'MAP-CROSS',
          amount: 1250000,
          content: 'Cross SR order fix',
          orders: ['26052912345678'],
          orderSource: 'AUTO',
          orderUpdatedAt: null,
          orderUpdatedByUserId: null,
          orderUpdatedByEmail: null,
          status: '00',
          paidAt: null,
          payerName: null,
          payerAccount: null,
          rawData: null,
          firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
        },
      ]);
      prisma.mapVietinTransaction.count.mockResolvedValue(1);

      await expect(
        service.listStatements(
          { role: 'MANAGER', storeId: 'store-uuid-1' },
          { ...input, page: 0, limit: 20 },
        ),
      ).resolves.toMatchObject({
        total: 1,
        list: [
          {
            id: 'cross-sr',
            storeId: 'CP02',
            canEditOrders: true,
            orderEditBlockedReason: null,
          },
        ],
      });

      const where =
        prisma.mapVietinTransaction.findMany.mock.calls.at(-1)[0].where;
      const serializedWhere = JSON.stringify(where);
      expect(serializedWhere).toContain(marker);
      expect(serializedWhere).not.toContain('storeCode');
    },
  );

  it('rejects combined primary statement filters', async () => {
    await expect(
      service.listStatements(
        { role: 'MANAGER', storeId: 'store-uuid-1' },
        { order: '26052912345678', amount: '1250000' },
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('filters statements by pending and confirmed offset statuses', async () => {
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);
    prisma.mapVietinTransaction.count.mockResolvedValue(0);

    await expect(
      service.listStatements(
        { role: 'SUPER_ADMIN' },
        { orderStatus: 'OFFSET_PENDING', page: 0, limit: 20 },
      ),
    ).resolves.toMatchObject({ total: 0, list: [] });

    expect(prisma.mapVietinTransaction.findMany).toHaveBeenLastCalledWith(
      expect.objectContaining({
        where: {
          AND: expect.arrayContaining([
            { orderTransferRequests: { some: { status: 'PENDING' } } },
            { incomeType: 'SALES' },
          ]),
        },
      }),
    );

    await expect(
      service.listStatements(
        { role: 'SUPER_ADMIN' },
        { orderStatus: 'OFFSET_CONFIRMED', page: 0, limit: 20 },
      ),
    ).resolves.toMatchObject({ total: 0, list: [] });

    expect(prisma.mapVietinTransaction.findMany).toHaveBeenLastCalledWith(
      expect.objectContaining({
        where: {
          AND: expect.arrayContaining([
            { orderSource: 'OFFSET' },
            { incomeType: 'SALES' },
          ]),
        },
      }),
    );
  });

  it('creates statement order transfer requests before the Vietnam day closes', async () => {
    const transaction = statementTransactionRow({
      id: 'stored-1',
      orders: ['26052112345678'],
      paidAt: new Date('2026-05-21T02:00:00.000Z'),
    });
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(transaction);
    prisma.mapVietinStatementOrderTransferRequest.findFirst.mockResolvedValue(
      null,
    );
    prisma.mapVietinStatementOrderTransferRequest.create.mockImplementation(
      async ({ data }: any) => ({
        id: 'request-1',
        ...data,
        status: 'PENDING',
        createdAt: new Date('2026-05-21T03:00:00.000Z'),
        updatedAt: new Date('2026-05-21T03:00:00.000Z'),
        reviewedAt: null,
        reviewedByEmail: null,
        transaction,
      }),
    );

    await expect(
      service.createStatementOrderTransferRequest(
        {
          id: 'user-1',
          email: 'staff@example.com',
          role: 'MANAGER',
          storeId: 'store-uuid-1',
        },
        'stored-1',
        { orders: ['26052187654321'] },
      ),
    ).resolves.toMatchObject({
      id: 'request-1',
      transactionId: 'stored-1',
      requestedOrders: ['26052187654321'],
      status: 'PENDING',
    });

    expect(redisService.publishMessage).toHaveBeenCalledWith(
      'STATEMENT_ORDER_TRANSFER_REQUESTED',
      expect.objectContaining({
        schemaVersion: 1,
        type: 'STATEMENT_ORDER_TRANSFER_REQUEST',
        audience: expect.objectContaining({
          storeCodes: ['CP01'],
          roles: ['SUPER_ADMIN'],
          policyCodes: ['BANK_STATEMENT_ALL_SCOPE'],
          featureCodes: ['BANK_STATEMENTS'],
        }),
        payload: expect.objectContaining({
          requestId: 'request-1',
          transactionId: 'stored-1',
          storeCode: 'CP01',
        }),
      }),
    );
  });

  it('blocks statement order transfer requests after the Vietnam day closes', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(
      statementTransactionRow({
        id: 'stored-old',
        paidAt: new Date('2026-05-19T02:00:00.000Z'),
      }),
    );

    await expect(
      service.createStatementOrderTransferRequest(
        { role: 'MANAGER', storeId: 'store-uuid-1' },
        'stored-old',
        { orders: ['26052187654321'] },
      ),
    ).rejects.toThrow(
      'Quá thời hạn cập nhật trong ngày. Vui lòng dùng chức năng Cấn trừ.',
    );
    expect(
      prisma.mapVietinStatementOrderTransferRequest.create,
    ).not.toHaveBeenCalled();
  });

  it('blocks previous-day statement order transfer requests even inside 24h', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(
      statementTransactionRow({
        id: 'stored-yesterday',
        paidAt: new Date('2026-05-20T16:30:00.000Z'),
      }),
    );

    await expect(
      service.createStatementOrderTransferRequest(
        { role: 'MANAGER', storeId: 'store-uuid-1' },
        'stored-yesterday',
        { orders: ['26052187654321'] },
      ),
    ).rejects.toThrow(
      'Quá thời hạn cập nhật trong ngày. Vui lòng dùng chức năng Cấn trừ.',
    );
    expect(
      prisma.mapVietinStatementOrderTransferRequest.create,
    ).not.toHaveBeenCalled();
  });

  it('blocks duplicate pending statement order transfer requests', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(
      statementTransactionRow({ id: 'stored-1', orders: ['26052112345678'] }),
    );
    prisma.mapVietinStatementOrderTransferRequest.findFirst.mockResolvedValue({
      id: 'request-existing',
    });

    await expect(
      service.createStatementOrderTransferRequest(
        { role: 'MANAGER', storeId: 'store-uuid-1' },
        'stored-1',
        { orders: ['26052187654321'] },
      ),
    ).rejects.toThrow('Giao dịch đang chờ Kế toán xác nhận');
    expect(
      prisma.mapVietinStatementOrderTransferRequest.create,
    ).not.toHaveBeenCalled();
  });

  it('lets ACC approve order transfer requests and writes order audit', async () => {
    const transaction = statementTransactionRow({
      id: 'stored-1',
      orders: ['26052112345678'],
    });
    const request = {
      id: 'request-1',
      transactionId: 'stored-1',
      storeCode: 'CP01',
      oldOrders: ['26052112345678'],
      requestedOrders: ['26052187654321'],
      status: 'PENDING',
      requestedByUserId: 'staff-1',
      requestedByEmail: 'staff@example.com',
      reviewedByUserId: null,
      reviewedByEmail: null,
      reviewedAt: null,
      createdAt: new Date('2026-05-21T03:00:00.000Z'),
      updatedAt: new Date('2026-05-21T03:00:00.000Z'),
      transaction,
    };
    const updatedTransaction = {
      ...transaction,
      orders: ['26052187654321'],
      orderSource: 'OFFSET',
      orderUpdatedAt: new Date('2026-05-21T03:00:00.000Z'),
      orderUpdatedByEmail: 'acc@example.com',
    };
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinStatementOrderTransferRequest.findUnique.mockResolvedValue(
      request,
    );
    prisma.mapVietinTransaction.update.mockResolvedValue(updatedTransaction);
    prisma.mapVietinTransactionOrderAudit.create.mockResolvedValue({});
    prisma.mapVietinStatementOrderTransferRequest.update.mockResolvedValue({
      ...request,
      status: 'APPROVED',
      reviewedByUserId: 'acc-1',
      reviewedByEmail: 'acc@example.com',
      reviewedAt: new Date('2026-05-21T03:00:00.000Z'),
      transaction: updatedTransaction,
    });

    await expect(
      service.approveStatementOrderTransferRequest(
        {
          id: 'acc-1',
          email: 'acc@example.com',
          role: 'USER',
          storeId: 'store-uuid-1',
          featureBankStatements: true,
          departmentCode: 'ACC',
        },
        'request-1',
      ),
    ).resolves.toMatchObject({
      request: { id: 'request-1', status: 'APPROVED' },
      transaction: {
        id: 'stored-1',
        orders: ['26052187654321'],
        orderSource: 'OFFSET',
        isOrderOffsetConfirmed: true,
      },
    });

    expect(prisma.mapVietinTransaction.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          orders: ['26052187654321'],
          orderSource: 'OFFSET',
          orderUpdatedByEmail: 'acc@example.com',
        }),
      }),
    );
    expect(prisma.mapVietinTransactionOrderAudit.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          oldOrders: ['26052112345678'],
          newOrders: ['26052187654321'],
          source: 'OFFSET',
        }),
      }),
    );
  });

  it('stores rejection notes and notifies the requester', async () => {
    const transaction = statementTransactionRow({ id: 'stored-1' });
    const request = {
      id: 'request-1',
      transactionId: 'stored-1',
      storeCode: 'CP01',
      oldOrders: ['26052112345678'],
      requestedOrders: ['26052187654321'],
      status: 'PENDING',
      requestedByUserId: 'staff-1',
      requestedByEmail: 'staff@example.com',
      reviewedByUserId: null,
      reviewedByEmail: null,
      reviewNote: null,
      reviewedAt: null,
      createdAt: new Date('2026-05-21T03:00:00.000Z'),
      updatedAt: new Date('2026-05-21T03:00:00.000Z'),
      transaction,
    };
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinStatementOrderTransferRequest.findUnique.mockResolvedValue(
      request,
    );
    prisma.mapVietinStatementOrderTransferRequest.update.mockResolvedValue({
      ...request,
      status: 'REJECTED',
      reviewedByUserId: 'acc-1',
      reviewedByEmail: 'acc@example.com',
      reviewNote: 'Mã đơn chưa đúng',
      reviewedAt: new Date('2026-05-21T03:00:00.000Z'),
    });

    await expect(
      service.rejectStatementOrderTransferRequest(
        {
          id: 'acc-1',
          email: 'acc@example.com',
          role: 'USER',
          storeId: 'store-uuid-1',
          featureBankStatements: true,
          departmentCode: 'ACC',
        },
        'request-1',
        { note: 'Mã đơn chưa đúng' },
      ),
    ).resolves.toMatchObject({
      request: {
        id: 'request-1',
        status: 'REJECTED',
        reviewNote: 'Mã đơn chưa đúng',
      },
      transaction: null,
    });

    expect(
      prisma.mapVietinStatementOrderTransferRequest.update,
    ).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          status: 'REJECTED',
          reviewNote: 'Mã đơn chưa đúng',
        }),
      }),
    );
    expect(redisService.publishMessage).toHaveBeenCalledWith(
      'STATEMENT_ORDER_TRANSFER_REQUESTED',
      expect.objectContaining({
        schemaVersion: 1,
        type: 'STATEMENT_ORDER_TRANSFER_REQUEST',
        audience: expect.objectContaining({
          recipientUserIds: ['staff-1'],
          policyCodes: ['BANK_STATEMENT_ALL_SCOPE'],
          featureCodes: ['BANK_STATEMENTS'],
        }),
        payload: expect.objectContaining({
          requestId: 'request-1',
          status: 'REJECTED',
          recipientUserId: 'staff-1',
        }),
      }),
    );
  });

  it('blocks non-ACC users from reviewing order transfer requests', async () => {
    await expect(
      service.approveStatementOrderTransferRequest(
        {
          id: 'user-1',
          role: 'USER',
          storeId: 'store-uuid-1',
          featureBankStatements: true,
        },
        'request-1',
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(
      prisma.mapVietinStatementOrderTransferRequest.findUnique,
    ).not.toHaveBeenCalled();
  });

  it('lets ACC org-node users list pending order transfer requests', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinStatementOrderTransferRequest.findMany.mockResolvedValue(
      [],
    );
    prisma.mapVietinStatementOrderTransferRequest.count.mockResolvedValue(0);

    await expect(
      service.listStatementOrderTransferRequests(
        {
          id: 'acc-node-user',
          role: 'USER',
          storeId: 'store-uuid-1',
          featureBankStatements: true,
        },
        { page: 0, limit: 50 },
      ),
    ).resolves.toMatchObject({ total: 0, list: [] });

    expect(
      prisma.mapVietinStatementOrderTransferRequest.findMany,
    ).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { status: 'PENDING', storeCode: 'CP01' },
      }),
    );
  });

  it('includes a reviewer requester own rejected order-transfer notifications', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinStatementOrderTransferRequest.findMany.mockResolvedValue(
      [],
    );
    prisma.mapVietinStatementOrderTransferRequest.count.mockResolvedValue(0);

    await expect(
      service.listStatementOrderTransferRequests(
        {
          id: 'acc-1',
          role: 'USER',
          storeId: 'store-uuid-1',
          featureBankStatements: true,
          departmentCode: 'ACC',
        },
        { status: 'NOTIFICATION', page: 0, limit: 20 },
      ),
    ).resolves.toMatchObject({ total: 0, list: [] });

    expect(
      prisma.mapVietinStatementOrderTransferRequest.findMany,
    ).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          OR: [
            { status: 'PENDING', storeCode: 'CP01' },
            { status: 'REJECTED', requestedByUserId: 'acc-1' },
          ],
        },
      }),
    );
  });

  it('returns statement notification read timestamps for the signed-in user', async () => {
    const readAt = new Date('2026-06-26T03:00:00.000Z');
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinStatementOrderTransferRequest.findMany.mockResolvedValue([
      {
        id: 'request-read',
        transactionId: 'tx-1',
        storeCode: 'CP01',
        oldOrders: ['26062600000001'],
        requestedOrders: ['26062600000002'],
        status: 'PENDING',
        requestedByUserId: 'staff-1',
        requestedByEmail: 'staff@phongvu.vn',
        reviewedByUserId: null,
        reviewedByEmail: null,
        reviewNote: null,
        reviewedAt: null,
        createdAt: new Date('2026-06-26T02:00:00.000Z'),
        updatedAt: new Date('2026-06-26T02:00:00.000Z'),
        transaction: null,
      },
    ]);
    prisma.mapVietinStatementOrderTransferRequest.count.mockResolvedValue(1);
    notificationsService.readAtByNotificationId.mockResolvedValue(
      new Map([['request-read', readAt]]),
    );

    const result = await service.listStatementOrderTransferRequests(
      {
        id: 'acc-1',
        role: 'USER',
        storeId: 'store-uuid-1',
        featureBankStatements: true,
        departmentCode: 'ACC',
      },
      { status: 'NOTIFICATION', page: 0, limit: 20 },
    );

    expect(result.list).toHaveLength(1);
    expect(result.list[0].notificationReadAt).toBe(readAt);
    expect(notificationsService.readAtByNotificationId).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'acc-1' }),
      'statement_order_transfer',
      ['request-read'],
    );
  });

  it('updates statement orders and records audit history', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue({
      id: 'stored-1',
      storeCode: 'CP01',
      orders: ['26052112345678'],
    });
    prisma.mapVietinTransaction.update.mockResolvedValue({
      id: 'stored-1',
      storeCode: 'CP01',
      transactionKey: 'CP01:key',
      transactionNumber: 'TXN-001',
      amount: 1250000,
      content: 'Manual fix',
      orders: ['26052287654321'],
      orderSource: 'MANUAL',
      orderUpdatedAt: new Date('2026-05-21T03:00:00.000Z'),
      orderUpdatedByUserId: 'user-1',
      orderUpdatedByEmail: 'manager@example.com',
      status: '00',
      paidAt: null,
      payerName: null,
      payerAccount: null,
      firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
    });
    prisma.mapVietinTransactionOrderAudit.create.mockResolvedValue({});

    await expect(
      service.updateStatementOrders(
        {
          id: 'user-1',
          email: 'finance@example.com',
          role: 'MANAGER',
          storeId: 'store-uuid-1',
          departmentCode: 'FIN_ACC',
        },
        'stored-1',
        { orders: ['26052287654321'] },
      ),
    ).resolves.toMatchObject({
      orders: ['26052287654321'],
      canEditOrders: true,
    });

    expect(prisma.mapVietinTransactionOrderAudit.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          oldOrders: ['26052112345678'],
          newOrders: ['26052287654321'],
          changedByEmail: 'finance@example.com',
        }),
      }),
    );
  });

  it('updates statement orders for null-store eFAST rows for phongvu.vn users', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue({
      id: 'stored-null-store',
      storeCode: null,
      transactionKey: '__NO_STORE__:key',
      transactionNumber: 'TRX-NO-PMT',
      amount: 1250000,
      content: 'No pmtId',
      orders: [],
      orderSource: null,
      rawData: { source: 'VIETIN_EFAST' },
      firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
    });
    prisma.mapVietinTransaction.update.mockResolvedValue({
      id: 'stored-null-store',
      storeCode: 'CP01',
      transactionKey: '__NO_STORE__:key',
      transactionNumber: 'TRX-NO-PMT',
      amount: 1250000,
      content: 'No pmtId',
      orders: ['26052287654321'],
      orderSource: 'MANUAL',
      orderUpdatedAt: new Date('2026-05-21T03:00:00.000Z'),
      orderUpdatedByUserId: 'user-1',
      orderUpdatedByEmail: 'staff@phongvu.vn',
      status: 'SUCCESS',
      paidAt: null,
      payerName: null,
      payerAccount: null,
      rawData: { source: 'VIETIN_EFAST' },
      firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
    });
    prisma.mapVietinTransactionOrderAudit.create.mockResolvedValue({});

    await expect(
      service.updateStatementOrders(
        {
          id: 'user-1',
          email: 'staff@phongvu.vn',
          role: 'STAFF',
          storeId: 'store-uuid-1',
        },
        'stored-null-store',
        { orders: ['26052287654321'] },
      ),
    ).resolves.toMatchObject({
      storeId: 'CP01',
      orders: ['26052287654321'],
      canEditOrders: false,
    });

    expect(prisma.mapVietinTransactionOrderAudit.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          transactionId: 'stored-null-store',
          storeCode: 'CP01',
          newOrders: ['26052287654321'],
          changedByEmail: 'staff@phongvu.vn',
        }),
      }),
    );
    expect(prisma.mapVietinTransaction.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ storeCode: 'CP01' }),
      }),
    );
  });

  it('assigns null-store statements to the updater store after an exact statement lookup', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-2',
      storeId: 'CP02',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue({
      id: 'stored-null-store',
      storeCode: null,
      transactionKey: '__NO_STORE__:key',
      transactionNumber: 'TRX-NO-PMT',
      amount: 1250000,
      content: 'No pmtId',
      orders: [],
      orderSource: null,
      rawData: { source: 'VIETIN_EFAST' },
      firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
    });
    prisma.mapVietinTransaction.update.mockResolvedValue({
      id: 'stored-null-store',
      storeCode: 'CP02',
      transactionKey: '__NO_STORE__:key',
      transactionNumber: 'TRX-NO-PMT',
      amount: 1250000,
      content: 'No pmtId',
      orders: ['26052287654321'],
      orderSource: 'MANUAL',
      orderUpdatedAt: new Date('2026-05-21T03:00:00.000Z'),
      orderUpdatedByUserId: 'user-2',
      orderUpdatedByEmail: 'staff@example.com',
      status: 'SUCCESS',
      paidAt: null,
      payerName: null,
      payerAccount: null,
      rawData: { source: 'VIETIN_EFAST' },
      firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
    });
    prisma.mapVietinTransactionOrderAudit.create.mockResolvedValue({});

    await expect(
      service.updateStatementOrders(
        {
          id: 'user-2',
          email: 'staff@example.com',
          role: 'STAFF',
          storeId: 'store-uuid-2',
        },
        'stored-null-store',
        {
          statementNumber: 'TRX-NO-PMT',
          orders: ['26052287654321'],
        },
      ),
    ).resolves.toMatchObject({
      storeId: 'CP02',
      orders: ['26052287654321'],
    });

    expect(prisma.mapVietinTransaction.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ storeCode: 'CP02' }),
      }),
    );
  });

  it('resolves stale statement order updates by transaction key', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({
        id: 'stored-fresh',
        storeCode: 'CP01',
        transactionKey: 'CP01:key',
        orders: [],
      });
    prisma.mapVietinTransaction.update.mockResolvedValue({
      id: 'stored-fresh',
      storeCode: 'CP01',
      transactionKey: 'CP01:key',
      transactionNumber: 'TXN-001',
      amount: 1250000,
      content: 'Manual fix after stale id',
      orders: ['26052287654321'],
      orderSource: 'MANUAL',
      orderUpdatedAt: new Date('2026-05-21T03:00:00.000Z'),
      orderUpdatedByUserId: 'user-1',
      orderUpdatedByEmail: 'manager@example.com',
      status: '00',
      paidAt: null,
      payerName: null,
      payerAccount: null,
      firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
    });
    prisma.mapVietinTransactionOrderAudit.create.mockResolvedValue({});

    await expect(
      service.updateStatementOrders(
        {
          id: 'user-1',
          email: 'manager@example.com',
          role: 'MANAGER',
          storeId: 'store-uuid-1',
        },
        'stored-stale',
        { orders: ['26052287654321'], transactionKey: 'CP01:key' },
      ),
    ).resolves.toMatchObject({
      id: 'stored-fresh',
      orders: ['26052287654321'],
    });

    expect(prisma.mapVietinTransaction.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'stored-fresh' } }),
    );
    expect(prisma.mapVietinTransactionOrderAudit.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ transactionId: 'stored-fresh' }),
      }),
    );
  });

  it('allows users to update cross-SR protected orders with exact transfer-content proof', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue({
      id: 'stored-cross-sr',
      storeCode: 'CP02',
      transactionKey: 'CP02:key',
      transactionNumber: 'MAP-CROSS',
      amount: 1250000,
      content: 'Cross SR manual fix',
      orders: ['26052912345678'],
      orderSource: 'AUTO',
      rawData: null,
    });
    prisma.mapVietinTransaction.update.mockResolvedValue({
      id: 'stored-cross-sr',
      storeCode: 'CP02',
      transactionKey: 'CP02:key',
      transactionNumber: 'MAP-CROSS',
      amount: 1250000,
      content: 'Cross SR manual fix',
      orders: ['26052987654321'],
      orderSource: 'MANUAL',
      orderUpdatedAt: new Date('2026-05-21T03:00:00.000Z'),
      orderUpdatedByUserId: 'user-1',
      orderUpdatedByEmail: 'manager@example.com',
      status: '00',
      paidAt: null,
      payerName: null,
      payerAccount: null,
      rawData: null,
      firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
    });
    prisma.mapVietinTransactionOrderAudit.create.mockResolvedValue({});

    await expect(
      service.updateStatementOrders(
        {
          id: 'user-1',
          email: 'manager@example.com',
          role: 'MANAGER',
          storeId: 'store-uuid-1',
        },
        'stored-cross-sr',
        {
          orders: ['26052987654321'],
          content: 'cross sr manual fix',
        },
      ),
    ).resolves.toMatchObject({
      id: 'stored-cross-sr',
      storeId: 'CP02',
      orders: ['26052987654321'],
      canEditOrders: true,
    });

    expect(prisma.mapVietinTransaction.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'stored-cross-sr' } }),
    );
    expect(prisma.mapVietinTransactionOrderAudit.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          transactionId: 'stored-cross-sr',
          storeCode: 'CP02',
          oldOrders: ['26052912345678'],
          newOrders: ['26052987654321'],
        }),
      }),
    );
  });

  it('blocks cross-SR order updates when exact lookup proof is missing', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue({
      id: 'stored-cross-sr',
      storeCode: 'CP02',
      transactionKey: 'CP02:key',
      transactionNumber: 'MAP-CROSS',
      amount: 1250000,
      content: 'Cross SR manual fix',
      orders: ['26052912345678'],
      orderSource: 'AUTO',
      rawData: null,
    });

    await expect(
      service.updateStatementOrders(
        {
          id: 'user-1',
          email: 'manager@example.com',
          role: 'MANAGER',
          storeId: 'store-uuid-1',
        },
        'stored-cross-sr',
        {
          orders: ['26052987654321'],
        },
      ),
    ).rejects.toThrow(
      'Chỉ được sửa giao dịch showroom khác khi tìm chính xác bằng mã sao kê, mã đơn, số tiền hoặc nội dung chuyển khoản.',
    );
    expect(prisma.mapVietinTransaction.update).not.toHaveBeenCalled();
  });

  it('lets non-FIN statement users fill NULL orders only', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue({
      id: 'stored-null',
      storeCode: 'CP01',
      orders: [],
      orderSource: null,
    });
    prisma.mapVietinTransaction.update.mockResolvedValue({
      id: 'stored-null',
      storeCode: 'CP01',
      transactionKey: 'CP01:null',
      transactionNumber: 'TXN-NULL',
      amount: 1250000,
      content: 'Manual fill',
      orders: ['26052287654321'],
      orderSource: 'MANUAL',
      orderUpdatedAt: new Date('2026-05-21T03:00:00.000Z'),
      orderUpdatedByUserId: 'user-1',
      orderUpdatedByEmail: 'manager@example.com',
      status: '00',
      paidAt: null,
      payerName: null,
      payerAccount: null,
      firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
    });
    prisma.mapVietinTransactionOrderAudit.create.mockResolvedValue({});

    await expect(
      service.updateStatementOrders(
        {
          id: 'user-1',
          email: 'manager@example.com',
          role: 'MANAGER',
          storeId: 'store-uuid-1',
        },
        'stored-null',
        { orders: ['26052287654321'] },
      ),
    ).resolves.toMatchObject({
      orders: ['26052287654321'],
      canEditOrders: false,
      orderEditBlockedReason: 'Bạn không có quyền sửa đơn hàng.',
    });
  });

  it('blocks non-FIN users from editing existing AUTO or MANUAL orders', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue({
      id: 'stored-protected',
      storeCode: 'CP01',
      orders: ['26052112345678'],
      orderSource: 'AUTO',
    });

    await expect(
      service.updateStatementOrders(
        {
          id: 'user-1',
          email: 'manager@example.com',
          role: 'MANAGER',
          storeId: 'store-uuid-1',
        },
        'stored-protected',
        { orders: ['26052287654321'] },
      ),
    ).rejects.toThrow('Bạn không có quyền sửa đơn hàng.');
    expect(prisma.mapVietinTransaction.update).not.toHaveBeenCalled();
  });

  it('lets SUPER_ADMIN and FIN_ACC node users edit protected statement orders', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue({
      id: 'stored-protected',
      storeCode: 'CP01',
      orders: ['26052112345678'],
      orderSource: 'MANUAL',
    });
    prisma.mapVietinTransaction.update.mockResolvedValue({
      id: 'stored-protected',
      storeCode: 'CP01',
      transactionKey: 'CP01:protected',
      transactionNumber: 'TXN-PROTECTED',
      amount: 1250000,
      content: 'Protected fix',
      orders: ['26052287654321'],
      orderSource: 'MANUAL',
      orderUpdatedAt: new Date('2026-05-21T03:00:00.000Z'),
      orderUpdatedByUserId: 'fin-node-user',
      orderUpdatedByEmail: 'fin-node@example.com',
      status: '00',
      paidAt: null,
      payerName: null,
      payerAccount: null,
      firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
    });
    prisma.mapVietinTransactionOrderAudit.create.mockResolvedValue({});

    await expect(
      service.updateStatementOrders(
        {
          id: 'fin-node-user',
          email: 'fin-node@example.com',
          role: 'MANAGER',
          storeId: 'store-uuid-1',
        },
        'stored-protected',
        { orders: ['26052287654321'] },
      ),
    ).resolves.toMatchObject({ canEditOrders: true });

    await expect(
      service.updateStatementOrders(
        {
          id: 'super-1',
          email: 'root@example.com',
          role: 'SUPER_ADMIN',
        },
        'stored-protected',
        { orders: ['26052287654321'] },
      ),
    ).resolves.toMatchObject({ canEditOrders: true });
  });

  it('lets FIN_ACC change statement income type and protects the manual choice', async () => {
    const existing = {
      id: 'stored-income-type',
      storeCode: 'CP01',
      transactionKey: 'CP01:income-type',
      transactionNumber: 'TXN-INCOME-TYPE',
      amount: 1250000,
      content: 'Customer transfer',
      orders: [],
      orderSource: 'AUTO',
      orderUpdatedAt: null,
      orderUpdatedByUserId: null,
      orderUpdatedByEmail: null,
      status: 'SUCCESS',
      paidAt: new Date('2026-07-19T03:00:00.000Z'),
      payerName: null,
      payerAccount: null,
      incomeType: 'SALES',
      incomeTypeSource: 'AUTO',
      rawData: {},
      firstSeenAt: new Date('2026-07-19T03:00:05.000Z'),
    };
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-uuid-1',
      storeId: 'CP01',
    });
    prisma.mapVietinTransaction.findUnique.mockResolvedValue(existing);
    prisma.mapVietinTransaction.update.mockResolvedValue({
      ...existing,
      incomeType: 'PARTNER_INTERNAL',
      incomeTypeSource: 'MANUAL',
      incomeTypeUpdatedAt: new Date('2026-07-19T03:01:00.000Z'),
      incomeTypeUpdatedByUserId: 'fin-node-user',
      incomeTypeUpdatedByEmail: 'fin-node@example.com',
    });

    await expect(
      service.updateStatementIncomeType(
        {
          id: 'fin-node-user',
          email: 'fin-node@example.com',
          role: 'USER',
          departmentCode: 'FIN_ACC',
          storeId: 'store-uuid-1',
          featureBankStatements: true,
        },
        existing.id,
        { incomeType: 'PARTNER_INTERNAL' },
      ),
    ).resolves.toMatchObject({
      incomeType: 'PARTNER_INTERNAL',
      incomeTypeLabel: 'Đối tác/Nội bộ',
      incomeTypeSource: 'MANUAL',
      canEditIncomeType: true,
    });
    expect(prisma.mapVietinTransaction.update).toHaveBeenCalledWith({
      where: { id: existing.id },
      data: expect.objectContaining({
        incomeType: 'PARTNER_INTERNAL',
        incomeTypeSource: 'MANUAL',
        incomeTypeUpdatedByUserId: 'fin-node-user',
        incomeTypeUpdatedByEmail: 'fin-node@example.com',
      }),
    });
  });

  it('blocks non-FIN users from changing statement income type', async () => {
    await expect(
      service.updateStatementIncomeType(
        {
          id: 'manager-1',
          email: 'manager@example.com',
          role: 'MANAGER',
          storeId: 'store-uuid-1',
        },
        'stored-income-type',
        { incomeType: 'PARTNER_INTERNAL' },
      ),
    ).rejects.toThrow('Bạn không có quyền thay đổi loại giao dịch sao kê.');
    expect(prisma.mapVietinTransaction.update).not.toHaveBeenCalled();
  });

  it('blocks SUPER_ADMIN outside FIN_ACC from changing statement income type', async () => {
    await expect(
      service.updateStatementIncomeType(
        {
          id: 'super-1',
          email: 'root@example.com',
          role: 'SUPER_ADMIN',
        },
        'stored-income-type',
        { incomeType: 'PARTNER_INTERNAL' },
      ),
    ).rejects.toThrow('Bạn không có quyền thay đổi loại giao dịch sao kê.');
    expect(prisma.mapVietinTransaction.update).not.toHaveBeenCalled();
  });

  it('exports selected statement rows as XLSX', async () => {
    prisma.mapVietinTransaction.findMany.mockResolvedValue([
      {
        storeCode: 'CP01',
        transactionNumber: '2030000000000',
        amount: 5190000,
        content: 'Khách chuyển tiền, cần giữ tiếng Việt',
        orders: ['26052912345678', '26053087654321'],
        status: 'Thành công',
        paidAt: new Date('2026-06-03T09:39:41.000Z'),
        payerName: null,
        payerAccount: null,
        incomeType: 'PARTNER_INTERNAL',
        rawData: {
          reqCardName: 'Nguyễn Văn A',
          reqCardNo: '9704361234567890',
          txnReference: '00020300000000004567',
          efastCreditAccountNo: '118002647006',
        },
        firstSeenAt: new Date('2026-06-03T09:40:05.000Z'),
        orderSource: 'AUTO',
      },
    ]);

    const xlsx = await service.exportStatementsXlsx(
      {
        id: 'fin-node-user',
        role: 'USER',
        departmentCode: 'FIN_ACC',
        featureBankStatements: true,
        statementAllScope: true,
      },
      { transactionIds: ['stored-1'] },
    );

    const workbook = XLSX.read(xlsx, { type: 'buffer' });
    const rows = XLSX.utils.sheet_to_json(workbook.Sheets['Sao kê'], {
      header: 1,
      raw: false,
    }) as unknown[][];
    expect(rows[0]).toEqual(
      expect.arrayContaining(['Loại giao dịch', 'Tài khoản nhận']),
    );
    expect(rows[1]).toEqual(
      expect.arrayContaining([
        'Đối tác/Nội bộ',
        '118002647006',
        'Khách chuyển tiền, cần giữ tiếng Việt',
        '03/06/2026 16:39:41',
        'Nguyễn Văn A',
        '9704361234567890',
      ]),
    );
    expect(rows[1]).toContain('5190000');
    expect(rows[1]).toContain('00020300000000004567');
    expect(rows[1]).toContain('26052912345678\n26053087654321');
    expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ id: { in: ['stored-1'] } }),
      }),
    );
  });

  it('exports the eFAST trxId instead of its numeric trxRefNo', async () => {
    prisma.mapVietinTransaction.findMany.mockResolvedValue([
      {
        storeCode: 'CH1001',
        transactionNumber: '904D60713M9LLR5M',
        amount: 15000000,
        content: '26070839000000',
        orders: ['26070839000000'],
        status: 'SUCCESS',
        paidAt: new Date('2026-07-13T12:05:30.000Z'),
        payerName: null,
        payerAccount: null,
        rawData: {
          source: 'VIETIN_EFAST',
          trxId: '904D60713M9LLR5M',
          trxRefNo: '331225',
          txnReference: '331225',
        },
        firstSeenAt: new Date('2026-07-13T12:05:35.000Z'),
        orderSource: 'AUTO',
      },
    ]);

    const xlsx = await service.exportStatementsXlsx(
      { role: 'SUPER_ADMIN' },
      { transactionIds: ['stored-efast-1'] },
    );

    const workbook = XLSX.read(xlsx, { type: 'buffer' });
    const rows = XLSX.utils.sheet_to_json(workbook.Sheets['Sao kê'], {
      header: 1,
      raw: false,
    }) as unknown[][];
    expect(rows[1]).toContain('904D60713M9LLR5M');
    expect(rows[1]).not.toContain('331225');
  });

  it('exports selected global-lookup statement rows without assigned-store scope', async () => {
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);

    await service.exportStatementsXlsx(
      { role: 'MANAGER', storeId: 'store-uuid-1' },
      { transactionIds: ['stored-1'], amount: '1250000' },
    );

    const where = prisma.mapVietinTransaction.findMany.mock.calls[0][0].where;
    const serializedWhere = JSON.stringify(where);
    expect(serializedWhere).toContain('1250000');
    expect(serializedWhere).toContain('stored-1');
    expect(serializedWhere).toContain('incomeType');
    expect(serializedWhere).toContain('SALES');
    expect(serializedWhere).not.toContain('storeCode');
    expect(serializedWhere).not.toContain('CP01');
  });

  it('rejects statement XLSX exports over one month', async () => {
    await expect(
      service.exportStatementsXlsx(
        { role: 'SUPER_ADMIN' },
        {
          allStores: 'true',
          startDate: '2026-05-01',
          endDate: '2026-06-05',
        },
      ),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(prisma.mapVietinTransaction.findMany).not.toHaveBeenCalled();
  });
});

function jsonResponse(body: unknown) {
  return {
    ok: true,
    status: 200,
    text: jest.fn().mockResolvedValue(JSON.stringify(body)),
  };
}

function httpResponse(
  status: number,
  body: unknown,
  headers: Record<string, string> = {},
) {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: {
      get: (name: string) => headers[name.toLowerCase()] ?? null,
    },
    text: jest.fn().mockResolvedValue(JSON.stringify(body)),
  };
}

function globalTransaction(txnNo: string, virtualAccount = '18PVICU') {
  return {
    txnNo,
    txnAmount: '1,250,000',
    txnDate: '21/05/2026 10:00:00',
    txnDesc: 'Khach chuyen tien',
    status: '00',
    virtualAccount,
  };
}

function statementTransactionRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 'stored-1',
    storeCode: 'CP01',
    transactionKey: 'CP01:key',
    transactionNumber: 'TXN-001',
    amount: 1250000,
    content: 'Khach chuyen tien 26052112345678',
    orders: ['26052112345678'],
    orderSource: 'AUTO',
    orderUpdatedAt: null,
    orderUpdatedByUserId: null,
    orderUpdatedByEmail: null,
    status: '00',
    paidAt: new Date('2026-05-21T02:00:00.000Z'),
    payerName: null,
    payerAccount: null,
    rawData: {},
    firstSeenAt: new Date('2026-05-21T02:00:05.000Z'),
    orderTransferRequests: [],
    ...overrides,
  };
}
