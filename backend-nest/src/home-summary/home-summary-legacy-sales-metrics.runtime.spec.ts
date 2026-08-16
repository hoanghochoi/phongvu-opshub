import {
  HomeSummaryLegacySalesMetricsCallbacks,
  HomeSummaryLegacySalesMetricsRuntime,
} from './home-summary-legacy-sales-metrics.runtime';

describe('HomeSummaryLegacySalesMetricsRuntime', () => {
  const scope = {
    available: true,
    scope: 'OWN' as const,
    scopeLabel: 'Cá nhân',
    scopeDetail: 'CP01',
    unavailableMessage: null,
    ownUserId: 'user-1',
    ownEmail: 'staff@phongvu.vn',
    ownPersonnelCode: 'PV001',
    allowedStoreCodes: ['CP01'],
  };
  const range = {
    start: new Date('2026-07-01T00:00:00.000Z'),
    end: new Date('2026-08-01T00:00:00.000Z'),
  };

  function createRuntime() {
    const prisma: any = {
      salesReport: {
        findMany: jest.fn().mockResolvedValue([]),
        count: jest.fn(),
      },
      salesReportErpOrderCache: {
        findMany: jest.fn().mockResolvedValue([]),
      },
      $transaction: jest
        .fn()
        .mockImplementation((operations: Promise<unknown>[]) =>
          Promise.all(operations),
        ),
    };
    const callbacks: HomeSummaryLegacySalesMetricsCallbacks = {
      salesProgressReportWhere: jest
        .fn()
        .mockReturnValue({ id: { not: '__NO_SALES_PROGRESS__' } }),
      orderCacheRevenueWhere: jest
        .fn()
        .mockReturnValue({ id: { not: '__NO_ORDER_CACHE__' } }),
      salesReportBehaviorWhere: jest
        .fn()
        .mockReturnValue({ id: { not: '__NO_BEHAVIOR__' } }),
      loadCanonicalRevenueForRows: jest.fn().mockResolvedValue({
        values: new Map([
          ['ORDER-1', 12500000],
          ['ORDER-2', 2500000],
        ]),
        presentCodes: new Set(['ORDER-1', 'ORDER-2']),
        invalidCodes: new Set(),
      }),
      logger: { log: jest.fn() },
    };
    return {
      prisma,
      callbacks,
      runtime: new HomeSummaryLegacySalesMetricsRuntime(prisma, callbacks),
    };
  }

  it('uses canonical revenue for completed sales rows', async () => {
    const { runtime, prisma, callbacks } = createRuntime();
    const rows = [{ orderCode: 'ORDER-1' }, { orderCode: 'ORDER-2' }];
    prisma.salesReport.findMany.mockResolvedValue(rows);

    await expect(runtime.completedRevenue(scope, range)).resolves.toBe(
      15000000,
    );
    expect(callbacks.salesProgressReportWhere).toHaveBeenCalledWith(
      scope,
      range,
    );
    expect(prisma.salesReport.findMany).toHaveBeenCalledWith({
      where: { id: { not: '__NO_SALES_PROGRESS__' } },
      select: { orderCode: true },
    });
    expect(callbacks.loadCanonicalRevenueForRows).toHaveBeenCalledWith(
      rows,
      'completed_revenue',
    );
  });

  it('excludes pending, cancelled and fully returned cache rows', async () => {
    const { runtime, prisma, callbacks } = createRuntime();
    prisma.salesReportErpOrderCache.findMany.mockResolvedValue([
      {
        grandTotal: 100000,
        paymentStatus: 'PAID',
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: false,
      },
      {
        grandTotal: 200000,
        paymentStatus: 'PENDING',
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: false,
      },
      {
        grandTotal: 300000,
        paymentStatus: 'PAID',
        lifecycleStatus: 'CANCELLED',
        hasReturnedFullItems: false,
      },
      {
        grandTotal: 400000,
        paymentStatus: 'PAID',
        lifecycleStatus: 'RETURNED_FULL',
        hasReturnedFullItems: false,
      },
      {
        grandTotal: 500000,
        paymentStatus: 'PAID',
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: true,
      },
      {
        grandTotal: null,
        paymentStatus: 'PAID',
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: false,
      },
    ]);

    await expect(runtime.totalCacheRevenue(scope, range)).resolves.toBe(100000);
    expect(callbacks.orderCacheRevenueWhere).toHaveBeenCalledWith(scope, range);
    expect(callbacks.logger.log).toHaveBeenCalledWith(
      expect.stringContaining(
        'skippedPendingPayment=1 invalidCanonicalTotals=1 revenue=100000',
      ),
    );
  });

  it('counts all behavior YES predicates in one transaction', async () => {
    const { runtime, prisma, callbacks } = createRuntime();
    prisma.salesReport.count
      .mockResolvedValueOnce(3)
      .mockResolvedValueOnce(2)
      .mockResolvedValueOnce(1)
      .mockResolvedValueOnce(4);

    await expect(
      runtime.countBehaviorYesReports(scope, range),
    ).resolves.toEqual({
      consultedSolution: 3,
      experienced: 2,
      zalo: 1,
      appDownload: 4,
    });
    expect(callbacks.salesReportBehaviorWhere).toHaveBeenCalledWith(
      scope,
      range,
    );
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(prisma.salesReport.count).toHaveBeenNthCalledWith(1, {
      where: {
        id: { not: '__NO_BEHAVIOR__' },
        consultedSolutionAnswer: 'YES',
      },
    });
    expect(prisma.salesReport.count).toHaveBeenNthCalledWith(4, {
      where: {
        id: { not: '__NO_BEHAVIOR__' },
        appDownloadAnswer: 'YES',
      },
    });
  });

  it('returns stable zero behavior counts for unavailable sales', () => {
    const { runtime } = createRuntime();

    expect(runtime.empty()).toEqual({
      consultedSolution: 0,
      experienced: 0,
      zalo: 0,
      appDownload: 0,
    });
  });
});
