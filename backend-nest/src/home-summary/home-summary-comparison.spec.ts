import { HomeSummaryService } from './home-summary.service';

describe('HomeSummaryService period comparison contract', () => {
  const service = new HomeSummaryService({} as any, {} as any, {} as any);

  it('shifts each endpoint independently and clamps calendar month ends', () => {
    expect((service as any).shiftDateOnly('2024-03-31', -1, 0)).toBe(
      '2024-02-29',
    );
    expect((service as any).shiftDateOnly('2025-03-31', -1, 0)).toBe(
      '2025-02-28',
    );
    expect((service as any).shiftDateOnly('2024-02-29', 0, -1)).toBe(
      '2023-02-28',
    );

    expect(
      (service as any).shiftSummaryRange(
        { startDate: '2025-03-30', endDate: '2025-03-31' },
        -1,
        0,
      ),
    ).toMatchObject({ startDate: '2025-02-28', endDate: '2025-02-28' });
  });

  it('uses relative delta, including new and both-zero states', () => {
    expect((service as any).comparisonMetric(120, 100)).toEqual({
      value: 100,
      deltaPercent: 20,
      status: 'AVAILABLE',
    });
    expect((service as any).comparisonMetric(1, 0)).toEqual({
      value: 0,
      deltaPercent: null,
      status: 'NEW',
    });
    expect((service as any).comparisonMetric(0, 0)).toEqual({
      value: 0,
      deltaPercent: 0,
      status: 'AVAILABLE',
    });
  });

  it('keeps comparison opt-in in response cache identity and separate coverage', () => {
    const user = { id: 'user-1' };
    const legacy = (service as any).summaryResponseCacheKey(user, {
      startDate: '2026-08-01',
      endDate: '2026-08-10',
    });
    const compared = (service as any).summaryResponseCacheKey(user, {
      startDate: '2026-08-01',
      endDate: '2026-08-10',
      includeComparisons: 'true',
    });
    expect(compared).not.toBe(legacy);
    expect(
      (service as any).summaryCacheCoverageRanges(
        { startDate: '2026-08-01', endDate: '2026-08-10' },
        { includeComparisons: 'true' },
      ),
    ).toEqual([
      { startDate: '2026-08-01', endDate: '2026-08-10' },
      { startDate: '2025-08-01', endDate: '2025-08-10' },
    ]);
  });

  it.each([
    ['a normal-year short range', '2026-08-10', '2026-08-13'],
    ['a leap-year boundary range', '2024-02-27', '2024-03-01'],
  ])(
    'keeps %s within the strict date guard for every cache period',
    (_label, startDate, endDate) => {
      const ranges = (service as any).summaryCacheCoverageRanges(
        { startDate, endDate },
        { includeComparisons: 'true' },
      );

      expect(ranges).toHaveLength(2);
      expect(() =>
        ranges.forEach((range: { startDate: string; endDate: string }) =>
          (service as any).rangeDateKeys(range.startDate, range.endDate),
        ),
      ).not.toThrow();
      expect(
        ranges.flatMap((range: { startDate: string; endDate: string }) =>
          (service as any).rangeDateKeys(range.startDate, range.endDate),
        ),
      ).toHaveLength(startDate === '2024-02-27' ? 7 : 8);
    },
  );

  it.each([
    ['365 days', '2025-01-01', '2025-12-31'],
    ['366 days', '2024-01-01', '2024-12-31'],
  ])('accepts the %s primary input range', (_label, startDate, endDate) => {
    expect(() =>
      (service as any).rangeDateKeys(startDate, endDate),
    ).not.toThrow();
  });

  it('rejects a 367-day primary input range with the existing contract', () => {
    expect(() =>
      (service as any).rangeDateKeys('2025-01-01', '2026-01-02'),
    ).toThrow('Khoảng ngày chỉ được tối đa 366 ngày.');
  });

  it('stores and invalidates both current and previous-year cache periods', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const user = { id: 'user-1' };
      const response = { freshness: { projectionVersion: 10 } } as any;
      jest.spyOn(service as any, 'computeSummary').mockResolvedValue(response);

      await service.getSummary(user, {
        startDate: '2026-08-10',
        endDate: '2026-08-13',
        includeComparisons: 'true',
      });

      const entry = Array.from(
        (service as any).summaryResponseCache.values(),
      )[0] as {
        coverageRanges: Array<{ startDate: string; endDate: string }>;
      };
      expect(entry.coverageRanges).toEqual([
        { startDate: '2026-08-10', endDate: '2026-08-13' },
        { startDate: '2025-08-10', endDate: '2025-08-13' },
      ]);
      expect(entry.coverageRanges).toHaveLength(2);

      const invalidation = service.invalidateSummaryResponseCache([
        { affectedDates: ['2025-08-12'], projectionVersion: 11 },
      ]);
      expect(invalidation.invalidatedCacheEntries).toBe(1);
      expect((service as any).summaryResponseCache.size).toBe(0);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('uses fully covered active CSV without requiring OpsHub projections', async () => {
    const summaryDate = new Date('2025-08-10T00:00:00.000Z');
    const prisma = {
      salesHistoryActiveGrain: {
        findMany: jest.fn().mockResolvedValue([
          {
            summaryDate,
            storeCode: 'CP01',
            currentVersionId: 'version-1',
          },
        ]),
      },
      salesHistoryAggregate: {
        findMany: jest.fn().mockResolvedValue([
          {
            versionId: 'version-1',
            summaryDate,
            storeCode: 'CP01',
            totalRevenue: 600n,
            totalOrders: 3,
            extendedInsuranceQuantity: 0,
            laptopQuantity: 2,
            pcQuantity: 0,
            assembledPcQuantity: 0,
            appleQuantity: 0,
            monitorQuantity: 0,
            printerQuantity: 0,
            accessoriesQuantity: 0,
          },
        ]),
      },
      homeSummaryDailyAggregate: {
        findMany: jest.fn().mockResolvedValue([
          {
            summaryDate,
            storeCode: 'CP01',
            totalOrders: 4,
            metrics: { totalRevenue: 400, laptopQuantity: 1 },
          },
        ]),
      },
    };
    const comparisonService = new HomeSummaryService(
      prisma as any,
      {} as any,
      {} as any,
    );
    const result = await (comparisonService as any).overlayActiveCsvHistory(
      { startDate: '2025-08-10', endDate: '2025-08-10' },
      {
        scope: 'MANAGED_SCOPE',
        allowedStoreCodes: ['CP01'],
        ownUserId: 'manager-1',
      },
    );

    expect(result.source).toBe('HYBRID_CSV');
    expect(result.values.totalRevenue).toBe(600);
    expect(result.values.totalOrders).toBe(3);
    expect(result.values.laptopQuantity).toBe(2);
    expect(result.values.averageOrderValue).toBe(200);
    expect(prisma.homeSummaryDailyAggregate.findMany).not.toHaveBeenCalled();
    expect(result.unavailable).toContain('conversionRate');
  });

  it('requires complete OpsHub projections only for uncovered mixed grains', async () => {
    const csvDate = new Date('2025-08-10T00:00:00.000Z');
    const projectionDate = new Date('2025-08-11T00:00:00.000Z');
    const prisma = {
      salesHistoryActiveGrain: {
        findMany: jest
          .fn()
          .mockResolvedValue([
            { summaryDate: csvDate, storeCode: 'CP01', currentVersionId: 'v1' },
          ]),
      },
      salesHistoryAggregate: {
        findMany: jest.fn().mockResolvedValue([
          {
            versionId: 'v1',
            summaryDate: csvDate,
            storeCode: 'CP01',
            totalRevenue: 600n,
            totalOrders: 3,
            extendedInsuranceQuantity: 0,
            laptopQuantity: 2,
            pcQuantity: 0,
            assembledPcQuantity: 0,
            appleQuantity: 0,
            monitorQuantity: 0,
            printerQuantity: 0,
            accessoriesQuantity: 0,
          },
        ]),
      },
      homeSummaryDailyAggregate: {
        findMany: jest.fn().mockResolvedValue([
          {
            summaryDate: projectionDate,
            storeCode: 'CP01',
            totalOrders: 4,
            metrics: {
              totalRevenue: 400,
              extendedInsuranceQuantity: 0,
              laptopQuantity: 1,
              pcQuantity: 0,
              assembledPcQuantity: 0,
              appleQuantity: 0,
              monitorQuantity: 0,
              printerQuantity: 0,
              accessoriesQuantity: 0,
            },
          },
        ]),
      },
    };
    const comparisonService = new HomeSummaryService(
      prisma as any,
      {} as any,
      {} as any,
    );

    const result = await (comparisonService as any).overlayActiveCsvHistory(
      { startDate: '2025-08-10', endDate: '2025-08-11' },
      { scope: 'MANAGED_SCOPE', allowedStoreCodes: ['CP01'] },
    );

    expect(result.values.totalRevenue).toBe(1000);
    expect(result.values.totalOrders).toBe(7);
    expect(result.values.laptopQuantity).toBe(3);
    expect(result.unavailable).not.toContain('totalRevenue');
    expect(result.unavailable).not.toContain('totalOrders');
  });

  it('marks only an incomplete projection metric unavailable instead of zero', async () => {
    const csvDate = new Date('2025-08-10T00:00:00.000Z');
    const projectionDate = new Date('2025-08-11T00:00:00.000Z');
    const prisma = {
      salesHistoryActiveGrain: {
        findMany: jest
          .fn()
          .mockResolvedValue([
            { summaryDate: csvDate, storeCode: 'CP01', currentVersionId: 'v1' },
          ]),
      },
      salesHistoryAggregate: {
        findMany: jest.fn().mockResolvedValue([
          {
            versionId: 'v1',
            summaryDate: csvDate,
            storeCode: 'CP01',
            totalRevenue: 600n,
            totalOrders: 3,
            extendedInsuranceQuantity: 0,
            laptopQuantity: 2,
            pcQuantity: 0,
            assembledPcQuantity: 0,
            appleQuantity: 0,
            monitorQuantity: 0,
            printerQuantity: 5,
            accessoriesQuantity: 0,
          },
        ]),
      },
      homeSummaryDailyAggregate: {
        findMany: jest.fn().mockResolvedValue([
          {
            summaryDate: projectionDate,
            storeCode: 'CP01',
            totalOrders: 4,
            metrics: {
              totalRevenue: 400,
              extendedInsuranceQuantity: 0,
              laptopQuantity: 1,
              pcQuantity: 0,
              assembledPcQuantity: 0,
              appleQuantity: 0,
              monitorQuantity: 0,
              // printerQuantity is intentionally absent for this grain.
              accessoriesQuantity: 0,
            },
          },
        ]),
      },
    };
    const comparisonService = new HomeSummaryService(
      prisma as any,
      {} as any,
      {} as any,
    );

    const result = await (comparisonService as any).buildComparisonPeriod(
      {},
      {},
      { totalRevenue: 1200, totalOrders: 8, laptopQuantity: 4 },
      { startDate: '2025-08-10', endDate: '2025-08-11' },
      { scope: 'MANAGED_SCOPE', allowedStoreCodes: ['CP01'] },
    );

    expect(result.metrics.printerQuantity).toEqual({
      value: null,
      deltaPercent: null,
      status: 'UNAVAILABLE',
    });
    expect(result.metrics.totalRevenue).toMatchObject({
      value: 1000,
      status: 'AVAILABLE',
    });
    expect(result.metrics.totalOrders).toMatchObject({
      value: 7,
      status: 'AVAILABLE',
    });
    expect(result.metrics.averageOrderValue).toMatchObject({
      value: 143,
      status: 'AVAILABLE',
    });
    expect(result.metrics.laptopQuantity).toMatchObject({
      value: 3,
      status: 'AVAILABLE',
    });

    prisma.homeSummaryDailyAggregate.findMany.mockResolvedValue([
      {
        summaryDate: projectionDate,
        storeCode: 'CP01',
        totalOrders: 4,
        metrics: {
          extendedInsuranceQuantity: 0,
          laptopQuantity: 1,
          pcQuantity: 0,
          assembledPcQuantity: 0,
          appleQuantity: 0,
          monitorQuantity: 0,
          printerQuantity: 1,
          accessoriesQuantity: 0,
        },
      },
    ] as any);

    const missingRevenue = await (
      comparisonService as any
    ).buildComparisonPeriod(
      {},
      {},
      { totalRevenue: 1200, totalOrders: 8, laptopQuantity: 4 },
      { startDate: '2025-08-10', endDate: '2025-08-11' },
      { scope: 'MANAGED_SCOPE', allowedStoreCodes: ['CP01'] },
    );

    expect(missingRevenue.metrics.totalRevenue.status).toBe('UNAVAILABLE');
    expect(missingRevenue.metrics.averageOrderValue.status).toBe('UNAVAILABLE');
    expect(missingRevenue.metrics.totalOrders.status).toBe('AVAILABLE');
    expect(missingRevenue.metrics.laptopQuantity.status).toBe('AVAILABLE');
  });
});
