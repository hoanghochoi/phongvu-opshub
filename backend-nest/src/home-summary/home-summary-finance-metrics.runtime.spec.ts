import {
  HomeSummaryFinanceMetricsCallbacks,
  HomeSummaryFinanceMetricsRuntime,
} from './home-summary-finance-metrics.runtime';

describe('HomeSummaryFinanceMetricsRuntime', () => {
  const range = {
    start: new Date('2026-07-01T00:00:00.000Z'),
    end: new Date('2026-08-01T00:00:00.000Z'),
  };
  const scopes = {
    all: {
      available: true,
      scope: 'ALL' as const,
      scopeLabel: 'Tất cả',
      scopeDetail: null,
      unavailableMessage: null,
      ownUserId: null,
      ownEmail: null,
      ownPersonnelCode: null,
      allowedStoreCodes: [],
    },
    managed: {
      available: true,
      scope: 'MANAGED_SCOPE' as const,
      scopeLabel: 'Khu vực quản lý',
      scopeDetail: 'node-1',
      unavailableMessage: null,
      ownUserId: null,
      ownEmail: null,
      ownPersonnelCode: null,
      allowedStoreCodes: ['CP01', 'CP02'],
    },
    own: {
      available: true,
      scope: 'OWN' as const,
      scopeLabel: 'Cá nhân',
      scopeDetail: 'CP01',
      unavailableMessage: null,
      ownUserId: 'user-1',
      ownEmail: 'staff@phongvu.vn',
      ownPersonnelCode: 'PV001',
      allowedStoreCodes: ['CP01'],
    },
  };

  function createRuntime() {
    const prisma: any = {
      homeSummaryOrderFact: {
        findMany: jest.fn().mockResolvedValue([]),
      },
      mapVietinTransaction: {
        count: jest
          .fn()
          .mockResolvedValueOnce(5)
          .mockResolvedValueOnce(3)
          .mockResolvedValueOnce(2)
          .mockResolvedValueOnce(2)
          .mockResolvedValueOnce(1),
        aggregate: jest.fn().mockResolvedValue({ _sum: { amount: 42000000 } }),
      },
      $transaction: jest
        .fn()
        .mockImplementation((operations: Promise<unknown>[]) =>
          Promise.all(operations),
        ),
    };
    const callbacks: HomeSummaryFinanceMetricsCallbacks = {
      financeScopeWhere: jest.fn().mockReturnValue({
        id: { not: '__NO_FINANCE__' },
      }),
      orderScopeWhere: jest.fn().mockReturnValue({
        id: { not: '__NO_ORDER_FACT__' },
      }),
      normalizeOrderCode: jest.fn((value: unknown) =>
        typeof value === 'string' ? value.trim() || null : null,
      ),
    };
    return {
      prisma,
      callbacks,
      runtime: new HomeSummaryFinanceMetricsRuntime(prisma, callbacks),
    };
  }

  it('calculates all six metrics and preserves each tracking predicate', async () => {
    const { runtime, prisma, callbacks } = createRuntime();

    await expect(runtime.calculate(scopes.all, range)).resolves.toEqual({
      totalStatements: 5,
      totalStatementsTracked: 3,
      totalStatementsUnfollowed: 2,
      totalTransferredAmount: 42000000,
      totalStatementsWithOrder: 2,
      totalStatementsWithoutOrder: 1,
    });
    expect(callbacks.financeScopeWhere).toHaveBeenCalledWith(
      scopes.all,
      range,
      [],
    );
    expect(prisma.homeSummaryOrderFact.findMany).not.toHaveBeenCalled();
    expect(prisma.mapVietinTransaction.aggregate).toHaveBeenCalledWith({
      where: { id: { not: '__NO_FINANCE__' } },
      _sum: { amount: true },
    });
    const countWheres = prisma.mapVietinTransaction.count.mock.calls.map(
      ([args]: any[]) => JSON.stringify(args.where),
    );
    expect(countWheres[0]).not.toContain('orderTrackingStatus');
    expect(countWheres.slice(1, 3)).toEqual(
      expect.arrayContaining([
        expect.stringContaining('"orderTrackingStatus":"FOLLOWING"'),
        expect.stringContaining('"orderTrackingStatus":"UNFOLLOWED"'),
      ]),
    );
    expect(countWheres.slice(3)).toEqual(
      expect.arrayContaining([
        expect.stringContaining('"isEmpty":false'),
        expect.stringContaining('"isEmpty":true'),
      ]),
    );
  });

  it('loads only normalized personal order codes for OWN scope', async () => {
    const { runtime, prisma, callbacks } = createRuntime();
    prisma.homeSummaryOrderFact.findMany.mockResolvedValue([
      { orderCode: ' ORDER-1 ' },
      { orderCode: null },
      { orderCode: '   ' },
      { orderCode: 'ORDER-2' },
    ]);

    await runtime.calculate(scopes.own, range);

    expect(callbacks.orderScopeWhere).toHaveBeenCalledWith(scopes.own, range);
    expect(callbacks.normalizeOrderCode).toHaveBeenCalledTimes(4);
    expect(callbacks.financeScopeWhere).toHaveBeenCalledWith(
      scopes.own,
      range,
      ['ORDER-1', 'ORDER-2'],
    );
    expect(prisma.homeSummaryOrderFact.findMany).toHaveBeenCalledWith({
      where: { id: { not: '__NO_ORDER_FACT__' } },
      select: { orderCode: true },
    });
  });

  it('does not load order facts for managed scope', async () => {
    const { runtime, prisma, callbacks } = createRuntime();

    await runtime.calculate(scopes.managed, range);

    expect(prisma.homeSummaryOrderFact.findMany).not.toHaveBeenCalled();
    expect(callbacks.financeScopeWhere).toHaveBeenCalledWith(
      scopes.managed,
      range,
      [],
    );
  });

  it('returns stable zero metrics for finance-disabled callers', () => {
    const { runtime } = createRuntime();

    expect(runtime.empty()).toEqual({
      totalStatements: 0,
      totalStatementsTracked: 0,
      totalStatementsUnfollowed: 0,
      totalTransferredAmount: 0,
      totalStatementsWithOrder: 0,
      totalStatementsWithoutOrder: 0,
    });
  });
});
