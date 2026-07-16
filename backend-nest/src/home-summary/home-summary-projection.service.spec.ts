import { HomeSummaryProjectionService } from './home-summary-projection.service';

describe('HomeSummaryProjectionService', () => {
  function createHarness() {
    const prisma = {
      domainOutboxEvent: {
        findMany: jest.fn().mockResolvedValue([]),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      homeSummaryProjectionQueue: {
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        findMany: jest.fn().mockResolvedValue([]),
      },
      homeSummaryProjectionState: {
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        findMany: jest.fn().mockResolvedValue([]),
      },
      $transaction: jest.fn(async (input: unknown) => {
        if (Array.isArray(input)) return Promise.all(input);
        throw new Error('Unexpected interactive transaction in unit harness');
      }),
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const homeSummary = {
      rebuildProjectionDate: jest.fn().mockResolvedValue(new Date()),
      invalidateSummaryResponseCache: jest.fn(),
    };
    const redis = {
      publishMessageOrThrow: jest.fn().mockResolvedValue(undefined),
    };
    const service = new HomeSummaryProjectionService(
      prisma as any,
      homeSummary as any,
      redis as any,
    );
    return { service, prisma, homeSummary, redis };
  }

  it('publishes only the versioned Home signal and marks durable outbox complete', async () => {
    const { service, prisma, homeSummary, redis } = createHarness();
    prisma.domainOutboxEvent.findMany.mockResolvedValue([
      {
        id: 'event-42',
        eventType: 'HOME_SUMMARY_UPDATED',
        payload: {
          affectedDates: ['2026-07-14'],
          projectionVersion: 42,
        },
        occurredAt: new Date('2026-07-14T10:30:05.000Z'),
        attempts: 0,
      },
    ]);

    const published = await (service as any).publishPendingEvents();

    expect(published).toBe(1);
    expect(homeSummary.invalidateSummaryResponseCache).toHaveBeenCalledWith(
      [
        {
          affectedDates: ['2026-07-14'],
          projectionVersion: 42,
        },
      ],
      'projection_event_batch',
    );
    expect(redis.publishMessageOrThrow).toHaveBeenCalledWith(
      'HOME_SUMMARY_UPDATED',
      {
        schemaVersion: 2,
        type: 'HOME_SUMMARY_UPDATED',
        eventId: 'event-42',
        occurredAt: '2026-07-14T10:30:05.000Z',
        audience: { kind: 'AUTHENTICATED' },
        payload: {
          affectedDates: ['2026-07-14'],
          projectionVersion: 42,
        },
      },
    );
    expect(prisma.domainOutboxEvent.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'event-42', publishedAt: null },
        data: expect.objectContaining({
          publishedAt: expect.any(Date),
          attempts: { increment: 1 },
        }),
      }),
    );
  });

  it('keeps a failed grain durable and applies capped retry backoff', async () => {
    const { service, prisma, homeSummary } = createHarness();
    homeSummary.rebuildProjectionDate.mockRejectedValue(
      new Error('source temporarily unavailable'),
    );
    const now = Date.now();

    await (service as any).processJob({
      id: 'job-1',
      summaryDate: new Date('2026-07-14T00:00:00.000Z'),
      dimensionType: 'GLOBAL',
      dimensionKey: '',
      storeCode: '',
      sourceUpdatedAt: new Date('2026-07-14T10:30:00.000Z'),
      claimedAt: new Date(),
      attempts: 1,
      firstEnqueuedAt: new Date(),
    });

    expect(prisma.homeSummaryProjectionQueue.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          id: 'job-1',
          sourceUpdatedAt: new Date('2026-07-14T10:30:00.000Z'),
        },
        data: expect.objectContaining({
          claimedAt: null,
          availableAt: expect.any(Date),
          lastError: 'source temporarily unavailable',
        }),
      }),
    );
    const retryAt =
      prisma.homeSummaryProjectionQueue.updateMany.mock.calls[0][0].data
        .availableAt;
    expect(retryAt.getTime()).toBeGreaterThanOrEqual(now + 1900);
    expect(retryAt.getTime()).toBeLessThanOrEqual(now + 2500);
    expect(prisma.homeSummaryProjectionState.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ status: 'ERROR' }),
      }),
    );
  });

  it('locks the claimed queue row before commit so a concurrent source update cannot be deleted', async () => {
    const { service, prisma } = createHarness();
    const sourceUpdatedAt = new Date('2026-07-14T10:30:00.000Z');
    const tx = {
      $queryRaw: jest
        .fn()
        .mockResolvedValueOnce([{ sourceUpdatedAt }])
        .mockResolvedValueOnce([{ version: 42n }]),
      $executeRaw: jest.fn().mockResolvedValue(1),
      homeSummaryDailyAggregate: {
        deleteMany: jest.fn().mockResolvedValue({ count: 3 }),
      },
      homeSummaryProjectionState: {
        upsert: jest.fn().mockResolvedValue({}),
      },
      domainOutboxEvent: {
        create: jest.fn().mockResolvedValue({}),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      homeSummaryProjectionQueue: {
        delete: jest.fn().mockResolvedValue({}),
      },
    };
    prisma.$transaction.mockImplementationOnce(async (callback: any) =>
      callback(tx),
    );

    await expect(
      (service as any).finalizeProjection(
        {
          id: 'job-locked',
          summaryDate: new Date('2026-07-14T00:00:00.000Z'),
          dimensionType: 'GLOBAL',
          dimensionKey: '',
          storeCode: '',
          sourceUpdatedAt,
          claimedAt: new Date(),
          attempts: 1,
          firstEnqueuedAt: new Date(),
        },
        '2026-07-14',
      ),
    ).resolves.toBe(42n);

    expect(tx.$queryRaw.mock.calls[0][0].sql).toContain('FOR UPDATE');
    expect(tx.$executeRaw).toHaveBeenCalledTimes(3);
    for (const [statement] of tx.$executeRaw.mock.calls) {
      expect(statement.sql).toContain('NOT "isPaymentPending"');
    }
    expect(tx.homeSummaryProjectionQueue.delete).toHaveBeenCalledWith({
      where: { id: 'job-locked' },
    });
  });

  it('enqueues the full reconciliation window without rebuilding inline', async () => {
    const { service, prisma } = createHarness();
    jest.spyOn(service as any, 'runCycle').mockResolvedValue(undefined);

    await (service as any).enqueueReconciliationDates(7, 'recent_7d_hourly');

    expect(prisma.$executeRaw).toHaveBeenCalledTimes(7);
    expect((service as any).runCycle).toHaveBeenCalledWith(
      'reconciliation_recent_7d_hourly',
    );
  });

  it('skips the minute reconciliation when today is already complete and unchanged', async () => {
    const { service, prisma } = createHarness();
    jest.spyOn(service as any, 'runCycle').mockResolvedValue(undefined);
    const generatedAt = new Date('2026-07-16T02:00:00.000Z');
    prisma.homeSummaryProjectionState.findMany.mockResolvedValue([
      {
        summaryDate: new Date('2026-07-16T00:00:00.000Z'),
        status: 'COMPLETE',
        sourceUpdatedAt: new Date('2026-07-16T01:59:59.000Z'),
        generatedAt,
      },
    ]);

    jest.spyOn(service as any, 'vietnamDateKey').mockReturnValue('2026-07-16');
    await (service as any).enqueueReconciliationDates(1, 'today_1m', false);

    expect(prisma.$executeRaw).not.toHaveBeenCalled();
    expect((service as any).runCycle).not.toHaveBeenCalled();
  });

  it.each([
    {
      label: 'the source watermark is missing',
      status: 'COMPLETE',
      sourceUpdatedAt: null,
      generatedAt: new Date('2026-07-16T02:00:00.000Z'),
    },
    {
      label: 'the source is newer than the projection',
      status: 'COMPLETE',
      sourceUpdatedAt: new Date('2026-07-16T02:00:01.000Z'),
      generatedAt: new Date('2026-07-16T02:00:00.000Z'),
    },
    {
      label: 'the projection is incomplete without a queue row',
      status: 'ERROR',
      sourceUpdatedAt: new Date('2026-07-16T01:59:59.000Z'),
      generatedAt: new Date('2026-07-16T02:00:00.000Z'),
    },
  ])('repairs minute reconciliation when $label', async (state) => {
    const { service, prisma } = createHarness();
    jest.spyOn(service as any, 'runCycle').mockResolvedValue(undefined);
    prisma.homeSummaryProjectionState.findMany.mockResolvedValue([
      {
        summaryDate: new Date('2026-07-16T00:00:00.000Z'),
        status: state.status,
        sourceUpdatedAt: state.sourceUpdatedAt,
        generatedAt: state.generatedAt,
      },
    ]);

    jest.spyOn(service as any, 'vietnamDateKey').mockReturnValue('2026-07-16');
    await (service as any).enqueueReconciliationDates(1, 'today_1m', false);

    expect(prisma.$executeRaw).toHaveBeenCalledTimes(1);
    expect((service as any).runCycle).toHaveBeenCalledWith(
      'reconciliation_today_1m',
    );
  });

  it('does not reset a minute reconciliation job that is already queued', async () => {
    const { service, prisma } = createHarness();
    jest.spyOn(service as any, 'runCycle').mockResolvedValue(undefined);
    prisma.homeSummaryProjectionState.findMany.mockResolvedValue([
      {
        summaryDate: new Date('2026-07-16T00:00:00.000Z'),
        status: 'PENDING',
        sourceUpdatedAt: new Date('2026-07-16T02:00:01.000Z'),
        generatedAt: new Date('2026-07-16T02:00:00.000Z'),
      },
    ]);
    prisma.homeSummaryProjectionQueue.findMany.mockResolvedValue([
      { summaryDate: new Date('2026-07-16T00:00:00.000Z') },
    ]);

    jest.spyOn(service as any, 'vietnamDateKey').mockReturnValue('2026-07-16');
    await (service as any).enqueueReconciliationDates(1, 'today_1m', false);

    expect(prisma.$executeRaw).not.toHaveBeenCalled();
    expect((service as any).runCycle).not.toHaveBeenCalled();
  });

  it('repairs a missing minute projection state', async () => {
    const { service, prisma } = createHarness();
    jest.spyOn(service as any, 'runCycle').mockResolvedValue(undefined);
    jest.spyOn(service as any, 'vietnamDateKey').mockReturnValue('2026-07-16');

    await (service as any).enqueueReconciliationDates(1, 'today_1m', false);

    expect(prisma.$executeRaw).toHaveBeenCalledTimes(1);
    expect((service as any).runCycle).toHaveBeenCalledWith(
      'reconciliation_today_1m',
    );
  });
});
