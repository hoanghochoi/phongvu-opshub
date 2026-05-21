import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { encryptSecret } from '../common/secret-cipher';
import { MapVietinService } from './map-vietin.service';

describe('MapVietinService', () => {
  const originalEnv = process.env;
  const manager = { role: 'MANAGER', storeId: 'store-uuid-1' };
  let prisma: any;
  let fetchMock: jest.Mock;
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
      },
      mapVietinSyncState: {
        upsert: jest.fn(),
      },
    };
    fetchMock = jest.fn();
    global.fetch = fetchMock as any;
    service = new MapVietinService(prisma);
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
                txnDesc: 'Khach chuyen tien',
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
      content: 'Khach chuyen tien',
    });
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
});

function jsonResponse(body: unknown) {
  return {
    ok: true,
    text: jest.fn().mockResolvedValue(JSON.stringify(body)),
  };
}
