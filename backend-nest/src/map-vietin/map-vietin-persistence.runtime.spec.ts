import { MapVietinPersistenceRuntime } from './map-vietin-persistence.runtime';

describe('MapVietinPersistenceRuntime', () => {
  let prisma: any;
  let paymentNotifications: { createForTransaction: jest.Mock };
  let logger: {
    log: jest.Mock;
    warn: jest.Mock;
    error: jest.Mock;
  };
  let runtime: MapVietinPersistenceRuntime;

  const paidAt = new Date('2026-08-17T03:00:00.000Z');

  const row = (overrides: Record<string, unknown> = {}) => ({
    amount: 125000,
    content: 'Thanh toan don hang ORD-100',
    transactionNumber: 'MAP-100',
    paidAt,
    status: 'SUCCESS',
    payerName: 'Nguyen Van A',
    payerAccount: '1234567890',
    ...overrides,
  });

  beforeEach(() => {
    paymentNotifications = {
      createForTransaction: jest.fn().mockResolvedValue(undefined),
    };
    logger = { log: jest.fn(), warn: jest.fn(), error: jest.fn() };
    prisma = {
      $transaction: jest.fn(async (callback: (tx: any) => unknown) =>
        callback(prisma),
      ),
      mapVietinTransaction: {
        findUnique: jest.fn().mockResolvedValue(null),
        findFirst: jest.fn().mockResolvedValue(null),
        findMany: jest.fn().mockResolvedValue([]),
        upsert: jest.fn().mockImplementation(async ({ create }: any) => ({
          id: 'transaction-1',
          ...create,
        })),
        update: jest.fn(),
      },
      vietQrPaymentIntent: { updateMany: jest.fn() },
    };
    runtime = new MapVietinPersistenceRuntime({
      prisma,
      paymentNotifications,
      logger,
      amountKeys: ['amount'],
      contentKeys: ['content'],
      statusKeys: ['status'],
      transactionNumberKeys: ['transactionNumber'],
      transactionReferenceKeys: ['transactionReference'],
      payerNameKeys: ['payerName'],
      payerAccountKeys: ['payerAccount'],
      readAmount: (value) => Number(value.amount) || null,
      isSuccessfulTransaction: (value) => value.status === 'SUCCESS',
      readFirstText: (value, keys) => {
        for (const key of keys) {
          const text = String(value[key] ?? '').trim();
          if (text) return text;
        }
        return '';
      },
      readTransactionTime: (value) =>
        value.paidAt instanceof Date ? value.paidAt : null,
      extractOrderCodesFromContent: (content) =>
        content.match(/ORD-\d+/g) ?? [],
      isEfastMapTransactionRow: (value) => value.source === 'VIETIN_EFAST',
      rawDataAsMapRow: (value) =>
        value && typeof value === 'object' && !Array.isArray(value)
          ? (value as Record<string, unknown>)
          : null,
      readPositiveInt: (_name, fallback) => fallback,
      safeError: (error) =>
        error instanceof Error ? error.message : String(error),
    } as any);
  });

  it('normalizes only successful positive transactions with canonical statement identity', () => {
    expect(runtime.normalizeTransaction('CP01', row())).toMatchObject({
      storeCode: 'CP01',
      transactionNumber: 'MAP-100',
      orders: ['ORD-100'],
      orderSource: 'AUTO',
      incomeType: 'SALES',
      incomeTypeSource: 'AUTO',
      rawData: {
        providerIdentifiers: { mapTransactionNumber: 'MAP-100' },
      },
    });
    expect(runtime.normalizeTransaction('CP01', row({ amount: 0 }))).toBeNull();
    expect(
      runtime.normalizeTransaction('CP01', row({ status: 'FAILED' })),
    ).toBeNull();
  });

  it('persists a new transaction, notifies asynchronously, then skips an identical replay from the fingerprint cache', async () => {
    const stats = { updated: 0, unchanged: 0, cacheHits: 0 };

    await expect(
      runtime.persistTransactions('CP01', [row()], stats),
    ).resolves.toBe(1);
    await expect(
      runtime.persistTransactions('CP01', [row()], stats),
    ).resolves.toBe(0);

    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledTimes(1);
    expect(paymentNotifications.createForTransaction).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'transaction-1', storeCode: 'CP01' }),
    );
    expect(stats).toEqual({ updated: 0, unchanged: 1, cacheHits: 1 });
  });

  it('preserves manual order and income-type choices while refreshing the provider fields', async () => {
    prisma.mapVietinTransaction.findUnique.mockResolvedValueOnce({
      id: 'existing-1',
      transactionKey: 'existing-key',
      orderSource: 'MANUAL',
      incomeTypeSource: 'MANUAL',
      transactionNumber: 'OLD-100',
      rawData: {},
    });

    await expect(runtime.persistTransactions('CP01', [row()])).resolves.toBe(0);

    expect(prisma.mapVietinTransaction.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { transactionKey: 'existing-key' },
        update: expect.not.objectContaining({
          orders: expect.anything(),
          orderSource: expect.anything(),
          incomeType: expect.anything(),
          incomeTypeSource: expect.anything(),
        }),
      }),
    );
  });

  it('enriches a duplicate statement identifier and updates matched VietQR statement numbers', async () => {
    prisma.mapVietinTransaction.findFirst.mockResolvedValueOnce({
      id: 'existing-1',
      transactionKey: 'existing-key',
      transactionNumber: null,
      rawData: {},
    });

    const stats = { updated: 0, unchanged: 0, cacheHits: 0 };
    await expect(
      runtime.persistTransactions('CP01', [row()], stats),
    ).resolves.toBe(0);

    expect(prisma.mapVietinTransaction.upsert).not.toHaveBeenCalled();
    expect(prisma.mapVietinTransaction.update).toHaveBeenCalledWith({
      where: { id: 'existing-1' },
      data: {
        rawData: {
          providerIdentifiers: { mapTransactionNumber: 'MAP-100' },
        },
      },
    });
    expect(prisma.vietQrPaymentIntent.updateMany).toHaveBeenCalledWith({
      where: { matchedTransactionId: 'existing-1' },
      data: { matchedTransactionNumber: 'MAP-100' },
    });
    expect(stats).toEqual({ updated: 1, unchanged: 0, cacheHits: 0 });
  });

  it('does not merge an eFAST record into ambiguous opposite-source fingerprint matches', async () => {
    prisma.mapVietinTransaction.findMany.mockResolvedValueOnce([
      {
        id: 'map-1',
        transactionKey: 'map-key-1',
        transactionNumber: 'MAP-1',
        storeCode: 'CP01',
        rawData: { source: 'MAP' },
      },
      {
        id: 'map-2',
        transactionKey: 'map-key-2',
        transactionNumber: 'MAP-2',
        storeCode: 'CP01',
        rawData: { source: 'MAP' },
      },
    ]);

    await expect(
      runtime.persistTransactions('CP01', [row({ source: 'VIETIN_EFAST' })]),
    ).resolves.toBe(0);

    expect(prisma.mapVietinTransaction.upsert).not.toHaveBeenCalled();
    expect(logger.warn).toHaveBeenCalledWith(
      expect.stringContaining('ambiguous bank fingerprint'),
    );
  });
});
