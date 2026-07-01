import { BadRequestException, ForbiddenException } from '@nestjs/common';
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
        findMany: jest.fn(),
        count: jest.fn(),
        findUnique: jest.fn(),
        upsert: jest.fn(),
        update: jest.fn(),
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
          user?.featureBankStatements === true
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

  it('allows statement reads from all-scope policy without base statement policy', async () => {
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
      expect.objectContaining({ where: {} }),
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
      expect.objectContaining({ where: { storeCode: 'CP01' } }),
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
      expect.objectContaining({ where: { storeCode: 'CP75' } }),
    );
  });

  it('rejects statement reads without feature-tree access or statement policy', async () => {
    await expect(
      service.listStatements(
        { id: 'staff-1', role: 'USER', storeId: 'store-uuid-1' },
        { storeIds: 'CP01', page: 0, limit: 20 },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(prisma.store.findUnique).not.toHaveBeenCalled();
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

  it('uses a 3000-5000ms random delay for scheduled MAP history sync', () => {
    jest
      .spyOn(Math, 'random')
      .mockReturnValueOnce(0)
      .mockReturnValueOnce(0.9999);

    expect((service as any).randomMapHistorySyncDelayMs()).toBe(3000);
    expect((service as any).randomMapHistorySyncDelayMs()).toBe(5000);
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
    ).toBe(3000);
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

    expect(setTimeoutSpy).toHaveBeenCalledWith(expect.any(Function), 4000);
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
        { role: 'USER', storeId: 'store-uuid-1' },
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
        where: { storeCode: { in: ['CP01', 'CP02'] } },
      }),
    );
    expect(prisma.store.findUnique).not.toHaveBeenCalled();
  });

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
          orderTransferRequests: { some: { status: 'PENDING' } },
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
        where: { orderSource: 'OFFSET' },
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
        requestId: 'request-1',
        transactionId: 'stored-1',
        storeCode: 'CP01',
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
        requestId: 'request-1',
        status: 'REJECTED',
        recipientUserId: 'staff-1',
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

  it('exports selected statement rows as UTF-8 CSV', async () => {
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
        rawData: {
          reqCardName: 'Nguyễn Văn A',
          reqCardNo: '9704361234567890',
          txnReference: '00020300000000004567',
        },
        firstSeenAt: new Date('2026-06-03T09:40:05.000Z'),
        orderSource: 'AUTO',
      },
    ]);

    const csv = await service.exportStatementsCsv(
      { role: 'SUPER_ADMIN' },
      { transactionIds: ['stored-1'] },
    );

    expect(csv.charCodeAt(0)).toBe(0xfeff);
    expect(csv).toContain('Mã showroom');
    expect(csv).toContain('Mã showroom,Mã sao kê,Số tiền');
    expect(csv).toContain('Số tiền');
    expect(csv).toContain('Khách chuyển tiền, cần giữ tiếng Việt');
    expect(csv).toContain('5190000');
    expect(csv).toContain('03/06/2026 16:39:41');
    expect(csv).not.toContain('2026-06-03T09:39:41.000Z');
    expect(csv).toContain('"=""00020300000000004567"""');
    expect(csv).toContain('"=""26052912345678\n26053087654321"""');
    expect(csv).not.toContain('26052912345678 | 26053087654321');
    expect(csv).toContain('Nguyễn Văn A');
    expect(csv).toContain('"=""9704361234567890"""');
    expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ id: { in: ['stored-1'] } }),
      }),
    );
  });

  it('exports selected global-lookup statement rows without assigned-store scope', async () => {
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);

    await service.exportStatementsCsv(
      { role: 'MANAGER', storeId: 'store-uuid-1' },
      { transactionIds: ['stored-1'], amount: '1250000' },
    );

    const where = prisma.mapVietinTransaction.findMany.mock.calls[0][0].where;
    const serializedWhere = JSON.stringify(where);
    expect(serializedWhere).toContain('1250000');
    expect(serializedWhere).toContain('stored-1');
    expect(serializedWhere).not.toContain('storeCode');
    expect(serializedWhere).not.toContain('CP01');
  });

  it('rejects statement CSV exports over one month', async () => {
    await expect(
      service.exportStatementsCsv(
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

function httpResponse(status: number, body: unknown) {
  return {
    ok: status >= 200 && status < 300,
    status,
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
