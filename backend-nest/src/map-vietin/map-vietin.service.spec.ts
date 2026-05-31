import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { encryptSecret } from '../common/secret-cipher';
import { MapVietinService } from './map-vietin.service';

describe('MapVietinService', () => {
  const originalEnv = process.env;
  const manager = { role: 'MANAGER', storeId: 'store-uuid-1' };
  let prisma: any;
  let fetchMock: jest.Mock;
  let paymentNotifications: { createForTransaction: jest.Mock };
  let service: MapVietinService;

  beforeEach(() => {
    process.env = {
      ...originalEnv,
      JWT_SECRET: 'test-jwt-secret',
      MAP_VIETIN_CREDENTIAL_SECRET: 'test-map-secret',
    };
    prisma = {
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
    paymentNotifications = { createForTransaction: jest.fn() };
    fetchMock = jest.fn();
    global.fetch = fetchMock as any;
    jest
      .spyOn(Date, 'now')
      .mockReturnValue(new Date('2026-05-21T03:00:00.000Z').getTime());
    service = new MapVietinService(prisma, paymentNotifications as any);
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
        }),
      }),
    );
    expect(paymentNotifications.createForTransaction).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'stored-1', storeCode: 'CP01' }),
    );
    expect(prisma.mapVietinUnmappedTransaction.upsert).not.toHaveBeenCalled();
  });

  it('skips configured MAP sync before the Vietnam active window', async () => {
    (Date.now as jest.Mock).mockReturnValue(
      new Date('2026-05-21T00:59:59.000Z').getTime(),
    );
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';

    await expect(service.syncConfiguredStores()).resolves.toBeUndefined();

    expect(prisma.store.findMany).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('skips configured MAP sync at 22:00 Vietnam time', async () => {
    (Date.now as jest.Mock).mockReturnValue(
      new Date('2026-05-21T15:00:00.000Z').getTime(),
    );
    process.env.MAP_VIETIN_GLOBAL_USERNAME = 'global-user';
    process.env.MAP_VIETIN_GLOBAL_PASSWORD = 'global-pass';

    await expect(service.syncConfiguredStores()).resolves.toBeUndefined();

    expect(prisma.store.findMany).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
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
          amount: 1250000,
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

  it('lists statements with exact order and status filters inside store scope', async () => {
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
          order: '26052912345678',
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
    expect(JSON.stringify(where)).toContain('26052912345678');
    expect(JSON.stringify(where)).toContain('isEmpty');
  });

  it('rejects combined primary statement filters', async () => {
    await expect(
      service.listStatements(
        { role: 'MANAGER', storeId: 'store-uuid-1' },
        { order: '26052912345678', amount: '1250000' },
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
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
          email: 'manager@example.com',
          role: 'MANAGER',
          storeId: 'store-uuid-1',
        },
        'stored-1',
        { orders: ['26052287654321'] },
      ),
    ).resolves.toMatchObject({ orders: ['26052287654321'] });

    expect(prisma.mapVietinTransactionOrderAudit.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          oldOrders: ['26052112345678'],
          newOrders: ['26052287654321'],
          changedByEmail: 'manager@example.com',
        }),
      }),
    );
  });

  it('exports selected statement rows as UTF-8 CSV', async () => {
    prisma.mapVietinTransaction.findMany.mockResolvedValue([
      {
        storeCode: 'CP01',
        transactionNumber: 'TXN-001',
        amount: 1250000,
        content: 'Khach chuyen tien',
        orders: ['26052912345678'],
        status: '00',
        paidAt: new Date('2026-05-21T03:00:00.000Z'),
        payerName: null,
        payerAccount: null,
        firstSeenAt: new Date('2026-05-21T03:00:05.000Z'),
        orderSource: 'AUTO',
      },
    ]);

    const csv = await service.exportStatementsCsv(
      { role: 'SUPER_ADMIN' },
      { transactionIds: ['stored-1'] },
    );

    expect(csv.charCodeAt(0)).toBe(0xfeff);
    expect(csv).toContain('Mã showroom');
    expect(csv).toContain('26052912345678');
    expect(prisma.mapVietinTransaction.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ id: { in: ['stored-1'] } }),
      }),
    );
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
