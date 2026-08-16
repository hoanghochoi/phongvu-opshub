import {
  HomeSummarySalesProgressRuntime,
  HomeSummarySalesProgressCallbacks,
} from './home-summary-sales-progress.runtime';

describe('HomeSummarySalesProgressRuntime', () => {
  const dateRangeFor = (summaryDate: Date) => ({
    start: summaryDate,
    end: new Date(summaryDate.getTime() + 86_400_000),
  });

  function createRuntime(overrides: Partial<any> = {}) {
    const prisma: any = {
      salesReport: {
        findMany: jest.fn().mockResolvedValue([]),
      },
      salesTarget: {
        findMany: jest.fn().mockResolvedValue([]),
      },
      store: {
        findMany: jest.fn().mockResolvedValue([]),
      },
      user: {
        findUnique: jest.fn().mockResolvedValue({ jobRoleCode: 'SA' }),
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    Object.assign(prisma, overrides);
    const callbacks: HomeSummarySalesProgressCallbacks = {
      normalizeEmail: (value) => {
        const normalized = String(value ?? '')
          .trim()
          .toLowerCase();
        return normalized || null;
      },
      personalStoreGuard: (scope) =>
        scope.allowedStoreCodes.length > 0
          ? { storeCode: { in: scope.allowedStoreCodes } }
          : null,
      dateRangeFor,
      loadCanonicalRevenueForRows: jest.fn().mockResolvedValue({
        values: new Map([['ORDER-1', 12500000]]),
        presentCodes: new Set(['ORDER-1']),
        invalidCodes: new Set(),
      }),
    };
    return {
      prisma,
      callbacks,
      runtime: new HomeSummarySalesProgressRuntime(prisma, callbacks),
    };
  }

  const ownScope = {
    available: true,
    scope: 'OWN' as const,
    scopeLabel: 'Cá nhân',
    scopeDetail: null,
    unavailableMessage: null,
    ownUserId: 'user-1',
    ownEmail: 'staff@phongvu.vn',
    ownPersonnelCode: null,
    allowedStoreCodes: ['CP01'],
  };

  it('keeps Vietnam month and month-clamped week boundaries', () => {
    const { runtime } = createRuntime();
    const ranges = runtime.salesProgressRanges(
      new Date('2026-07-04T00:00:00.000Z'),
    );

    expect(ranges.month.start.toISOString()).toBe('2026-06-30T17:00:00.000Z');
    expect(ranges.month.end.toISOString()).toBe('2026-07-31T17:00:00.000Z');
    expect(ranges.week.start).toEqual(ranges.month.start);
    expect(ranges.week.end.toISOString()).toBe('2026-07-06T00:00:00.000Z');
    expect(ranges.daysInMonth).toBe(31);
    expect(ranges.weekDaysInMonth).toBe(5);
  });

  it('builds sales actuals and allocates a personal monthly target', async () => {
    const { runtime, prisma, callbacks } = createRuntime();
    prisma.salesReport.findMany.mockResolvedValue([
      {
        orderCode: 'ORDER-1',
        erpOrderCreatedAt: new Date('2026-07-04T02:00:00.000Z'),
        submittedAt: new Date('2026-07-04T02:10:00.000Z'),
      },
    ]);
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', organizationNodeId: 'node-1' },
    ]);
    prisma.salesTarget.findMany.mockResolvedValue([
      { organizationNodeId: 'node-1', targetBeforeTax: BigInt(300000000) },
    ]);
    prisma.user.findMany.mockResolvedValue([
      {
        store: { storeId: 'CP01' },
        organizationNode: null,
        organizationAssignments: [],
      },
    ]);

    const result = await runtime.build(
      { id: 'user-1', jobRoleCode: 'SA' },
      ownScope,
      new Date('2026-07-04T00:00:00.000Z'),
      dateRangeFor(new Date('2026-07-04T00:00:00.000Z')),
    );

    expect(result).toMatchObject({
      status: 'AVAILABLE',
      scope: 'PERSONAL_SA',
      missingStoreCodes: [],
      day: { actual: 12500000, target: 10451613 },
      month: { actual: 12500000, target: 324000000 },
    });
    expect(callbacks.loadCanonicalRevenueForRows).toHaveBeenCalledWith(
      expect.any(Array),
      'sales_progress',
    );
  });

  it('retains actuals while marking missing targets', async () => {
    const { runtime, prisma } = createRuntime();
    prisma.salesReport.findMany.mockResolvedValue([
      {
        orderCode: 'ORDER-1',
        erpOrderCreatedAt: new Date('2026-07-04T02:00:00.000Z'),
        submittedAt: new Date('2026-07-04T02:10:00.000Z'),
      },
    ]);
    prisma.store.findMany.mockResolvedValue([
      { storeId: 'CP01', organizationNodeId: 'node-1' },
    ]);
    prisma.salesTarget.findMany.mockResolvedValue([]);

    const result = await runtime.build(
      { id: 'manager-1' },
      { ...ownScope, scope: 'MANAGED_SCOPE', ownEmail: null },
      new Date('2026-07-04T00:00:00.000Z'),
      dateRangeFor(new Date('2026-07-04T00:00:00.000Z')),
    );

    expect(result).toMatchObject({
      status: 'MISSING',
      scope: 'MANAGED',
      missingStoreCodes: ['CP01'],
      day: { actual: 12500000, target: null, percentage: null },
    });
  });

  it('returns not-applicable for a non-SA personal scope without dropping actuals', async () => {
    const { runtime, prisma } = createRuntime();
    prisma.salesReport.findMany.mockResolvedValue([
      {
        orderCode: 'ORDER-1',
        erpOrderCreatedAt: new Date('2026-07-04T02:00:00.000Z'),
        submittedAt: new Date('2026-07-04T02:10:00.000Z'),
      },
    ]);

    const result = await runtime.build(
      { id: 'user-1', jobRoleCode: 'STORE_MANAGER' },
      ownScope,
      new Date('2026-07-04T00:00:00.000Z'),
      dateRangeFor(new Date('2026-07-04T00:00:00.000Z')),
    );

    expect(result).toMatchObject({
      status: 'NOT_APPLICABLE',
      scope: null,
      day: { actual: 12500000, target: null, percentage: null },
    });
    expect(prisma.store.findMany).not.toHaveBeenCalled();
  });
});
