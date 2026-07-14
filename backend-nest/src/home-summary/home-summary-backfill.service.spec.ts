import { HomeSummaryBackfillService } from './home-summary-backfill.service';

describe('HomeSummaryBackfillService', () => {
  function createHarness() {
    let checkpoint: any = {
      jobKey: 'HOME_SUMMARY_ERP_90D_V1',
      startDate: new Date('2026-07-14T00:00:00.000Z'),
      endDate: new Date('2026-07-14T00:00:00.000Z'),
      currentDate: new Date('2026-07-14T00:00:00.000Z'),
      nextOffset: 50,
      status: 'FAILED',
      pagesProcessed: 1,
      rowsProcessed: 50,
      lastError: 'interrupted',
    };
    const applyData = (data: Record<string, any>) => {
      for (const [key, value] of Object.entries(data)) {
        if (value && typeof value === 'object' && 'increment' in value) {
          checkpoint[key] += value.increment;
        } else {
          checkpoint[key] = value;
        }
      }
      return { ...checkpoint };
    };
    const prisma = {
      erpOrderCacheBackfillCheckpoint: {
        findUnique: jest.fn(async () => ({ ...checkpoint })),
        create: jest.fn(),
        update: jest.fn(async ({ data }: { data: Record<string, any> }) =>
          applyData(data),
        ),
        updateMany: jest.fn(async ({ data }: { data: Record<string, any> }) => {
          applyData(data);
          return { count: 1 };
        }),
      },
    };
    const salesReports = {
      syncErpOrderCachePage: jest.fn().mockResolvedValue({
        count: 10,
        orderCodes: ['ORDER-51'],
      }),
    };
    const service = new HomeSummaryBackfillService(
      prisma as any,
      salesReports as any,
    );
    jest.spyOn(service as any, 'delay').mockResolvedValue(undefined);
    return { service, prisma, salesReports, getCheckpoint: () => checkpoint };
  }

  it('resumes from the durable offset and completes idempotently', async () => {
    const { service, salesReports, getCheckpoint } = createHarness();

    const result = await service.runBackfill();

    expect(salesReports.syncErpOrderCachePage).toHaveBeenCalledWith({
      date: '2026-07-14',
      limit: 50,
      offset: 50,
      source: 'home_projection_backfill',
    });
    expect(result).toEqual({
      skipped: false,
      pagesProcessed: 2,
      rowsProcessed: 60,
    });
    expect(getCheckpoint()).toEqual(
      expect.objectContaining({
        status: 'COMPLETE',
        nextOffset: 0,
        pagesProcessed: 2,
        rowsProcessed: 60,
        lastError: null,
      }),
    );
  });

  it('uses the required bounded retry schedule for a page', async () => {
    const { service, salesReports } = createHarness();
    salesReports.syncErpOrderCachePage
      .mockRejectedValueOnce(new Error('temporary-1'))
      .mockRejectedValueOnce(new Error('temporary-2'))
      .mockResolvedValueOnce({ count: 1, orderCodes: ['ORDER-1'] });

    await expect(
      (service as any).fetchPageWithRetry('2026-07-14', 0),
    ).resolves.toEqual({ count: 1, orderCodes: ['ORDER-1'] });

    expect((service as any).delay).toHaveBeenNthCalledWith(1, 2_000);
    expect((service as any).delay).toHaveBeenNthCalledWith(2, 4_000);
  });
});
