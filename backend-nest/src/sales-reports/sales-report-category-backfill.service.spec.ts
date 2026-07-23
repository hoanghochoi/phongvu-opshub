import { SalesReportCategoryBackfillService } from './sales-report-category-backfill.service';

function candidate(overrides: Record<string, unknown> = {}) {
  return {
    id: 'item-1',
    salesReportId: 'report-1',
    sellerSku: 'SKU-1',
    storeCode: 'CP64',
    reportDate: new Date('2026-07-20T17:00:00.000Z'),
    ...overrides,
  };
}

function createHarness() {
  const updateMany = jest.fn();
  const findMany = jest.fn();
  const prisma = {
    salesReportOrderItem: { findMany, updateMany },
    $transaction: jest.fn(async (operations: Promise<unknown>[]) =>
      Promise.all(operations),
    ),
    $executeRaw: jest.fn(),
  };
  const erp = { lookupListingCategories: jest.fn() };
  const categories = { matchTypeFromListingCategories: jest.fn() };
  const bigQuerySync = { syncAll: jest.fn() };
  const service = new SalesReportCategoryBackfillService(
    prisma as any,
    erp as any,
    categories as any,
    bigQuerySync as any,
  );
  return {
    service,
    prisma,
    updateMany,
    findMany,
    erp,
    categories,
    bigQuerySync,
  };
}

describe('SalesReportCategoryBackfillService', () => {
  it('builds a deterministic keyset plan over NULL categoryType rows', async () => {
    const { service, findMany } = createHarness();
    findMany
      .mockResolvedValueOnce([
        {
          id: 'item-a',
          salesReportId: 'report-a',
          sellerSku: null,
          salesReport: {
            storeCode: null,
            orderCode: 'ORDER-A',
            erpOrderCreatedAt: null,
            submittedAt: new Date('2026-07-20T00:00:00.000Z'),
          },
        },
      ])
      .mockResolvedValueOnce([]);

    const plan = await service.buildPlan(1);

    expect(findMany).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        where: expect.objectContaining({
          categoryType: null,
          createdAt: { lte: expect.any(Date) },
        }),
        orderBy: { id: 'asc' },
        take: 1,
      }),
    );
    expect(findMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        where: expect.objectContaining({ id: { gt: 'item-a' } }),
      }),
    );
    expect(plan.planHash).toMatch(/^[a-f0-9]{64}$/);
    expect(plan).toMatchObject({
      version: 2,
      candidateCount: 1,
      lastCandidateId: 'item-a',
      affectedDates: ['2026-07-20'],
    });
    expect((plan as { candidates?: unknown }).candidates).toBeUndefined();
    expect(
      service.hashCandidates([
        {
          id: 'item-a',
          salesReportId: 'report-a',
          sellerSku: null,
          storeCode: null,
          reportDate: new Date('2026-07-20T00:00:00.000Z'),
        },
      ]),
    ).toBe(plan.planHash);
  });

  it('applies mapped rows compare-and-set, skips missing context, and records dates', async () => {
    const { service, updateMany, findMany, erp, categories } = createHarness();
    const rows = [
      candidate(),
      candidate({ id: 'item-no-sku', sellerSku: null }),
      candidate({ id: 'item-no-store', storeCode: null }),
    ];
    erp.lookupListingCategories.mockResolvedValue(
      new Map([['SKU-1', [{ code: 'NH03-01-01-01', level: 4 }]]]),
    );
    categories.matchTypeFromListingCategories.mockResolvedValue('cpu');
    updateMany.mockResolvedValue({ count: 1 });
    findMany.mockResolvedValue([{ id: 'item-1', categoryType: 'cpu' }]);
    jest
      .spyOn(service, 'iterateCandidatePages')
      .mockImplementation(async function* () {
        yield rows;
      });

    const result = await service.applyDatabase({
      version: 2,
      createdAt: new Date().toISOString(),
      pageSize: 100,
      candidateCount: rows.length,
      lastCandidateId: rows.at(-1)?.id ?? null,
      affectedDates: ['2026-07-21'],
      planHash: service.hashCandidates(rows),
    });

    expect(erp.lookupListingCategories).toHaveBeenCalledWith(['SKU-1'], 'CP64');
    expect(updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ categoryType: null, id: 'item-1' }),
        data: { categoryType: 'cpu' },
      }),
    );
    expect(result).toMatchObject({
      updated: 1,
      skippedMissingSku: 1,
      skippedMissingStore: 1,
      affectedReportIds: ['report-1'],
      affectedDates: ['2026-07-21'],
    });
  });

  it('is idempotent when a candidate was filled before compare-and-set', async () => {
    const { service, updateMany, erp, categories } = createHarness();
    const row = candidate();
    erp.lookupListingCategories.mockResolvedValue(
      new Map([['SKU-1', [{ code: 'NH03-01-01-01', level: 4 }]]]),
    );
    categories.matchTypeFromListingCategories.mockResolvedValue('cpu');
    updateMany.mockResolvedValue({ count: 0 });
    jest
      .spyOn(service, 'iterateCandidatePages')
      .mockImplementation(async function* () {
        yield [row];
      });

    const result = await service.applyDatabase({
      version: 2,
      createdAt: new Date().toISOString(),
      pageSize: 100,
      candidateCount: 1,
      lastCandidateId: row.id,
      affectedDates: ['2026-07-21'],
      planHash: service.hashCandidates([row]),
    });

    expect(result).toMatchObject({ updated: 0, stale: 1, affectedDates: [] });
  });

  it('resumes after a crash without revalidating changed NULL rows and preserves plan dates', async () => {
    const { service, findMany } = createHarness();
    jest
      .spyOn(service, 'iterateCandidatePages')
      .mockImplementation(async function* () {
        return;
      });

    const result = await service.applyDatabase(
      {
        version: 2,
        createdAt: new Date().toISOString(),
        pageSize: 100,
        candidateCount: 2,
        lastCandidateId: 'item-2',
        affectedDates: ['2026-07-20', '2026-07-21'],
        planHash: 'a'.repeat(64),
      },
      50,
      { verifyPlan: false, resume: true },
    );

    expect(findMany).not.toHaveBeenCalled();
    expect(result).toMatchObject({
      updated: 0,
      affectedDates: ['2026-07-20', '2026-07-21'],
    });
  });

  it('enqueues each affected Vietnam date and runs the existing full BQ sync', async () => {
    const { service, prisma, bigQuerySync } = createHarness();
    bigQuerySync.syncAll.mockResolvedValue({
      reportRows: 1,
      itemRows: 2,
      durationMs: 12,
    });

    await expect(
      service.enqueueHomeProjection(['2026-07-21', '2026-07-21', '2026-07-22']),
    ).resolves.toEqual(['2026-07-21', '2026-07-22']);
    await expect(service.syncBigQuery()).resolves.toMatchObject({
      itemRows: 2,
    });

    expect(prisma.$executeRaw).toHaveBeenCalledTimes(2);
    expect(bigQuerySync.syncAll).toHaveBeenCalledWith(
      'sales_report_category_backfill',
      { force: true },
    );
  });
});
