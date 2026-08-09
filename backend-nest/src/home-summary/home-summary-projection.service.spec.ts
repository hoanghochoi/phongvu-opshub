import { HomeSummaryProjectionService } from './home-summary-projection.service';

describe('HomeSummaryProjectionService', () => {
  afterEach(() => jest.restoreAllMocks());

  function createHarness() {
    const prisma = {
      domainOutboxEvent: {
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
      $queryRaw: jest.fn().mockResolvedValue([]),
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const homeSummary = {
      rebuildProjectionDate: jest.fn().mockResolvedValue(new Date()),
      populateSalesProjectionMetrics: jest.fn().mockResolvedValue(undefined),
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

  it('re-enqueues pending-payment, raw completed-only, and stale sales-contract dates across every grain before the startup cycle', async () => {
    const { service, prisma } = createHarness();
    prisma.$queryRaw
      .mockResolvedValueOnce([
        { dateKey: '2026-07-14' },
        { dateKey: '2026-07-16' },
        { dateKey: '2026-07-17' },
      ])
      .mockResolvedValueOnce([{ dateKey: '2026-07-18' }]);
    jest.spyOn(service as any, 'runCycle').mockResolvedValue(undefined);
    const logSpy = jest
      .spyOn((service as any).logger, 'log')
      .mockImplementation(() => undefined);

    await (service as any).runStartupCycle();

    expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      '"isPaymentPending"',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      '"HomeSummaryDailyAggregate"',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'FROM "HomeSummaryReportFact"',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'FROM "SalesReportErpOrderCache"',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'COALESCE("orderCreatedAt", "fetchedAt")',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'WHERE "excludedAt" IS NULL',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'FROM "SalesReport"',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'COALESCE("erpOrderCreatedAt", "submittedAt")',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'WHERE "erpExcludedAt" IS NULL',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'LEFT JOIN "HomeSummaryOrderFact"',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'salesPriceContractVersion',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'salesKpiContractVersion',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'aggregate_contract_state',
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain('BOOL_OR');
    expect(prisma.$queryRaw.mock.calls[0][0].values).toContain('2');
    expect(prisma.$queryRaw.mock.calls[0][0].values).toContain('1');
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      "INTERVAL '7 hours'",
    );
    expect(prisma.$queryRaw.mock.calls[1][0].sql).toContain(
      'aggregate."metrics" ? \'totalStatementsTracked\'',
    );
    expect(prisma.$queryRaw.mock.calls[1][0].sql).toContain(
      'aggregate."metrics" ? \'totalStatementsUnfollowed\'',
    );
    expect(prisma.$executeRaw).toHaveBeenCalledTimes(4);
    expect(
      prisma.$executeRaw.mock.calls.map(([statement]: any[]) =>
        statement.values.at(0),
      ),
    ).toEqual(['2026-07-14', '2026-07-16', '2026-07-17', '2026-07-18']);
    expect(prisma.$executeRaw.mock.calls[2][0].sql).toContain(
      "'RECONCILIATION', 'SALES'",
    );
    expect(prisma.$executeRaw.mock.calls[3][0].sql).toContain(
      'opshub_enqueue_home_summary_projection_kind',
    );
    expect(prisma.$executeRaw.mock.calls[3][0].sql).toContain(
      "'TRACKING_STATUS_BACKFILL', 'FINANCE'",
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        'Home projection startup reconciliation started: reason=sales_contract_versions salesPriceContractVersion=2 salesKpiContractVersion=1',
      ),
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        'Home projection startup reconciliation succeeded: reason=sales_contract_versions salesPriceContractVersion=2 salesKpiContractVersion=1 dates=3 trackingDates=1',
      ),
    );
    expect((service as any).runCycle).toHaveBeenCalledWith('startup');
  });

  it('keeps statement totals inclusive while limiting order KPIs to followed rows', async () => {
    const { service } = createHarness();
    const tx = { $executeRaw: jest.fn().mockResolvedValue(1) };

    await (service as any).insertFinanceAggregates(
      tx,
      '2026-07-14',
      42n,
      new Date('2026-07-14T10:30:00.000Z'),
      new Date('2026-07-14T10:30:01.000Z'),
    );

    const sql = tx.$executeRaw.mock.calls[0][0].sql as string;
    expect(sql).toContain('COUNT(*)::int AS statement_count');
    expect(sql).toContain('SUM(GREATEST(COALESCE("amount", 0), 0))');
    expect(sql).toContain(
      "COUNT(*) FILTER (WHERE tracking_status = 'FOLLOWING')::int AS tracked_count",
    );
    expect(sql).toContain(
      "COUNT(*) FILTER (WHERE tracking_status = 'UNFOLLOWED')::int AS unfollowed_count",
    );
    expect(sql).toContain(
      'WHERE tracking_status = \'FOLLOWING\' AND cardinality("orders") > 0',
    );
    expect(sql).toContain(
      'WHERE tracking_status = \'FOLLOWING\' AND cardinality("orders") = 0',
    );
    expect(sql).toContain("'totalStatementsTracked', tracked_count");
    expect(sql).toContain("'totalStatementsUnfollowed', unfollowed_count");
  });

  it('keeps the normal startup cycle when targeted reconciliation fails', async () => {
    const { service, prisma } = createHarness();
    prisma.$queryRaw.mockRejectedValue(new Error('column unavailable'));
    jest.spyOn(service as any, 'runCycle').mockResolvedValue(undefined);
    jest.spyOn((service as any).logger, 'error').mockImplementation(() => {});

    await (service as any).runStartupCycle();

    expect((service as any).logger.error).toHaveBeenCalledWith(
      expect.stringContaining(
        'Home projection startup reconciliation failed: reason=sales_contract_versions salesPriceContractVersion=2 salesKpiContractVersion=1',
      ),
    );
    expect((service as any).runCycle).toHaveBeenCalledWith('startup');
  });

  it('publishes only the versioned Home signal and marks durable outbox complete', async () => {
    const { service, prisma, homeSummary, redis } = createHarness();
    prisma.$queryRaw.mockResolvedValue([
      {
        id: 'event-42',
        payload: {
          affectedDates: ['2026-07-14'],
          projectionVersion: 42,
        },
        occurredAt: new Date('2026-07-14T10:30:05.000Z'),
        attempts: 0,
        claimToken: 'claim-event-42',
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
        where: {
          id: 'event-42',
          publishedAt: null,
          claimToken: 'claim-event-42',
        },
        data: expect.objectContaining({
          publishedAt: expect.any(Date),
          attempts: { increment: 1 },
          claimToken: null,
          leaseExpiresAt: null,
        }),
      }),
    );
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain(
      'FOR UPDATE SKIP LOCKED',
    );
  });

  it('keeps a failed grain durable and applies capped retry backoff', async () => {
    const { service, prisma, homeSummary } = createHarness();
    const finalizeProjection = jest.spyOn(service as any, 'finalizeProjection');
    homeSummary.rebuildProjectionDate.mockRejectedValue(
      new Error('source temporarily unavailable'),
    );
    const now = Date.now();

    await (service as any).processJob({
      id: 'job-1',
      summaryDate: new Date('2026-07-14T00:00:00.000Z'),
      projectionKind: 'SALES',
      dimensionType: 'GLOBAL',
      dimensionKey: '',
      storeCode: '',
      sourceUpdatedAt: new Date('2026-07-14T10:30:00.000Z'),
      claimedAt: new Date(),
      claimToken: 'claim-job-1',
      leaseExpiresAt: new Date(Date.now() + 120_000),
      dirtyGeneration: 1n,
      claimedGeneration: 1n,
      attempts: 1,
      firstEnqueuedAt: new Date(),
    });

    expect(prisma.homeSummaryProjectionQueue.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          id: 'job-1',
          claimToken: 'claim-job-1',
        },
        data: expect.objectContaining({
          claimedAt: null,
          claimToken: null,
          leaseExpiresAt: null,
          claimedGeneration: null,
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
    expect(finalizeProjection).not.toHaveBeenCalled();
  });

  it('retries a 40P01 finalizer and rebuilds SALES facts only once', async () => {
    const { service, homeSummary, prisma } = createHarness();
    jest
      .spyOn(service as any, 'finalizeProjection')
      .mockRejectedValueOnce({ cause: { originalCode: '40P01' } })
      .mockRejectedValueOnce({ code: '40P01' })
      .mockResolvedValue(42n);
    jest.spyOn(Math, 'random').mockReturnValue(0);

    await (service as any).processJob({
      id: 'job-deadlock',
      summaryDate: new Date('2026-07-14T00:00:00.000Z'),
      projectionKind: 'SALES',
      dimensionType: 'GLOBAL',
      dimensionKey: '',
      storeCode: '',
      sourceUpdatedAt: new Date('2026-07-14T10:30:00.000Z'),
      claimedAt: new Date(),
      claimToken: 'claim-deadlock',
      leaseExpiresAt: new Date(Date.now() + 120_000),
      dirtyGeneration: 1n,
      claimedGeneration: 1n,
      attempts: 1,
      firstEnqueuedAt: new Date(),
    });

    expect(homeSummary.rebuildProjectionDate).toHaveBeenCalledTimes(1);
    expect((service as any).finalizeProjection).toHaveBeenCalledTimes(3);
    expect(prisma.homeSummaryProjectionQueue.updateMany).not.toHaveBeenCalled();
  });

  it('keeps the job retryable after three deadlocked finalizer attempts', async () => {
    const { service, prisma } = createHarness();
    jest
      .spyOn(service as any, 'finalizeProjection')
      .mockRejectedValue({ code: '40P01' });
    jest.spyOn(Math, 'random').mockReturnValue(0);

    await (service as any).processJob({
      id: 'job-deadlock-exhausted',
      summaryDate: new Date('2026-07-14T00:00:00.000Z'),
      projectionKind: 'FINANCE',
      dimensionType: 'GLOBAL',
      dimensionKey: '',
      storeCode: '',
      sourceUpdatedAt: new Date('2026-07-14T10:30:00.000Z'),
      claimedAt: new Date(),
      claimToken: 'claim-deadlock-exhausted',
      leaseExpiresAt: new Date(Date.now() + 120_000),
      dirtyGeneration: 1n,
      claimedGeneration: 1n,
      attempts: 1,
      firstEnqueuedAt: new Date(),
    });

    expect((service as any).finalizeProjection).toHaveBeenCalledTimes(3);
    expect(prisma.homeSummaryProjectionQueue.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          id: 'job-deadlock-exhausted',
          claimToken: 'claim-deadlock-exhausted',
        },
        data: expect.objectContaining({
          claimToken: null,
          claimedGeneration: null,
          availableAt: expect.any(Date),
        }),
      }),
    );
    expect(prisma.homeSummaryProjectionState.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ financeStatus: 'ERROR' }),
      }),
    );
  });

  it('locks the claimed queue row before commit so a concurrent source update cannot be deleted', async () => {
    const { service, prisma, homeSummary } = createHarness();
    const sourceUpdatedAt = new Date('2026-07-14T10:30:00.000Z');
    const tx = {
      $queryRaw: jest
        .fn()
        .mockResolvedValueOnce([
          {
            sourceUpdatedAt,
            claimToken: 'claim-job-locked',
            dirtyGeneration: 1n,
            claimedGeneration: 1n,
          },
        ])
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
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
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
          projectionKind: 'SALES',
          dimensionType: 'GLOBAL',
          dimensionKey: '',
          storeCode: '',
          sourceUpdatedAt,
          claimedAt: new Date(),
          claimToken: 'claim-job-locked',
          leaseExpiresAt: new Date(Date.now() + 120_000),
          dirtyGeneration: 1n,
          claimedGeneration: 1n,
          attempts: 1,
          firstEnqueuedAt: new Date(),
        },
        '2026-07-14',
      ),
    ).resolves.toBe(42n);

    expect(tx.$queryRaw.mock.calls[0][0].sql).toContain('FOR UPDATE');
    expect(tx.$executeRaw).toHaveBeenCalledTimes(4);
    for (const [statement] of tx.$executeRaw.mock.calls.slice(0, 3)) {
      expect(statement.sql).toContain('NOT "isPaymentPending"');
    }
    expect(tx.$executeRaw.mock.calls[3][0].sql).toContain(
      '"salesStatus" = \'COMPLETE\'',
    );
    expect(tx.homeSummaryProjectionQueue.deleteMany).toHaveBeenCalledWith({
      where: {
        id: 'job-locked',
        claimToken: 'claim-job-locked',
        dirtyGeneration: 1n,
      },
    });
    expect(homeSummary.populateSalesProjectionMetrics).toHaveBeenCalledWith(
      tx,
      '2026-07-14',
    );
    expect(tx.domainOutboxEvent.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          payload: {
            affectedDates: ['2026-07-14'],
            projectionVersion: 42,
          },
        }),
      }),
    );
  });

  it('rebuilds a FINANCE job without synchronizing SALES facts', async () => {
    const { service, homeSummary } = createHarness();
    jest.spyOn(service as any, 'finalizeProjection').mockResolvedValue(42n);

    await (service as any).processJob({
      id: 'job-finance',
      summaryDate: new Date('2026-07-14T00:00:00.000Z'),
      projectionKind: 'FINANCE',
      dimensionType: 'GLOBAL',
      dimensionKey: '',
      storeCode: '',
      sourceUpdatedAt: new Date('2026-07-14T10:30:00.000Z'),
      claimedAt: new Date(),
      claimToken: 'claim-finance',
      leaseExpiresAt: new Date(Date.now() + 120_000),
      dirtyGeneration: 1n,
      claimedGeneration: 1n,
      attempts: 1,
      firstEnqueuedAt: new Date(),
    });

    expect(homeSummary.rebuildProjectionDate).not.toHaveBeenCalled();
    expect((service as any).finalizeProjection).toHaveBeenCalledWith(
      expect.objectContaining({ projectionKind: 'FINANCE' }),
      '2026-07-14',
    );
  });

  it('keeps one follow-up job when the same date changes during a claimed rebuild', async () => {
    const { service, prisma } = createHarness();
    const sourceUpdatedAt = new Date('2026-07-14T10:30:00.000Z');
    jest.spyOn(service as any, 'insertGlobalAggregate').mockResolvedValue(1);
    jest.spyOn(service as any, 'insertStoreAggregates').mockResolvedValue(1);
    jest
      .spyOn(service as any, 'insertUserStoreAggregates')
      .mockResolvedValue(1);
    const tx = {
      $queryRaw: jest
        .fn()
        .mockResolvedValueOnce([
          {
            sourceUpdatedAt: new Date('2026-07-14T10:30:01.000Z'),
            claimToken: 'claim-follow-up',
            dirtyGeneration: 2n,
            claimedGeneration: 1n,
          },
        ])
        .mockResolvedValueOnce([{ version: 43n }]),
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
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    prisma.$transaction.mockImplementationOnce(async (callback: any) =>
      callback(tx),
    );

    await expect(
      (service as any).finalizeProjection(
        {
          id: 'job-follow-up',
          summaryDate: new Date('2026-07-14T00:00:00.000Z'),
          projectionKind: 'SALES',
          dimensionType: 'GLOBAL',
          dimensionKey: '',
          storeCode: '',
          sourceUpdatedAt,
          claimedAt: new Date(),
          claimToken: 'claim-follow-up',
          leaseExpiresAt: new Date(Date.now() + 120_000),
          dirtyGeneration: 1n,
          claimedGeneration: 1n,
          attempts: 1,
          firstEnqueuedAt: new Date(),
        },
        '2026-07-14',
      ),
    ).resolves.toBe(43n);

    expect(tx.homeSummaryProjectionQueue.deleteMany).not.toHaveBeenCalled();
    expect(tx.homeSummaryProjectionQueue.updateMany).toHaveBeenCalledWith({
      where: {
        id: 'job-follow-up',
        claimToken: 'claim-follow-up',
      },
      data: expect.objectContaining({
        claimToken: null,
        claimedGeneration: null,
        attempts: 0,
      }),
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

  it('retries a deadlocked reconciliation enqueue without duplicating the date loop', async () => {
    const { service, prisma } = createHarness();
    prisma.$executeRaw
      .mockRejectedValueOnce({ cause: { originalCode: '40P01' } })
      .mockRejectedValueOnce({ code: '40P01' })
      .mockResolvedValue(1);
    jest.spyOn(Math, 'random').mockReturnValue(0);
    jest.spyOn(service as any, 'runCycle').mockResolvedValue(undefined);

    await (service as any).enqueueReconciliationDates(1, 'deadlock_test');

    expect(prisma.$executeRaw).toHaveBeenCalledTimes(3);
    expect((service as any).runCycle).toHaveBeenCalledTimes(1);
  });

  it('skips minute reconciliation when each projection kind is current for its own sources', async () => {
    const { service, prisma } = createHarness();
    jest.spyOn(service as any, 'runCycle').mockResolvedValue(undefined);
    const salesGeneratedAt = new Date('2026-07-16T02:00:00.000Z');
    const financeGeneratedAt = new Date('2026-07-16T01:00:00.000Z');
    prisma.homeSummaryProjectionState.findMany.mockResolvedValue([
      {
        summaryDate: new Date('2026-07-16T00:00:00.000Z'),
        status: 'COMPLETE',
        salesStatus: 'COMPLETE',
        financeStatus: 'COMPLETE',
        sourceUpdatedAt: new Date('2026-07-16T01:59:59.000Z'),
        salesReportSourceUpdatedAt: new Date('2026-07-16T01:59:59.000Z'),
        erpOrderCacheSourceUpdatedAt: null,
        mapVietinSourceUpdatedAt: null,
        salesGeneratedAt,
        financeGeneratedAt,
        generatedAt: financeGeneratedAt,
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
        salesStatus: state.status,
        financeStatus: state.status,
        sourceUpdatedAt: state.sourceUpdatedAt,
        salesReportSourceUpdatedAt: null,
        erpOrderCacheSourceUpdatedAt: null,
        mapVietinSourceUpdatedAt: null,
        salesGeneratedAt: state.generatedAt,
        financeGeneratedAt: state.generatedAt,
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
        salesStatus: 'PENDING',
        financeStatus: 'COMPLETE',
        sourceUpdatedAt: new Date('2026-07-16T02:00:01.000Z'),
        generatedAt: new Date('2026-07-16T02:00:00.000Z'),
      },
    ]);
    prisma.homeSummaryProjectionQueue.findMany.mockResolvedValue([
      {
        summaryDate: new Date('2026-07-16T00:00:00.000Z'),
        projectionKind: 'SALES',
      },
      {
        summaryDate: new Date('2026-07-16T00:00:00.000Z'),
        projectionKind: 'FINANCE',
      },
    ]);

    jest.spyOn(service as any, 'vietnamDateKey').mockReturnValue('2026-07-16');
    await (service as any).enqueueReconciliationDates(1, 'today_1m', false);

    expect(prisma.$executeRaw).not.toHaveBeenCalled();
    expect((service as any).runCycle).not.toHaveBeenCalled();
  });

  it('repairs minute reconciliation when only one projection kind is queued', async () => {
    const { service, prisma } = createHarness();
    jest.spyOn(service as any, 'runCycle').mockResolvedValue(undefined);
    prisma.homeSummaryProjectionState.findMany.mockResolvedValue([
      {
        summaryDate: new Date('2026-07-16T00:00:00.000Z'),
        status: 'PENDING',
        salesStatus: 'PENDING',
        financeStatus: 'PENDING',
        sourceUpdatedAt: new Date('2026-07-16T02:00:01.000Z'),
        generatedAt: new Date('2026-07-16T02:00:00.000Z'),
      },
    ]);
    prisma.homeSummaryProjectionQueue.findMany.mockResolvedValue([
      {
        summaryDate: new Date('2026-07-16T00:00:00.000Z'),
        projectionKind: 'SALES',
      },
    ]);

    jest.spyOn(service as any, 'vietnamDateKey').mockReturnValue('2026-07-16');
    await (service as any).enqueueReconciliationDates(1, 'today_1m', false);

    expect(prisma.$executeRaw).toHaveBeenCalledTimes(1);
    expect((service as any).runCycle).toHaveBeenCalledWith(
      'reconciliation_today_1m',
    );
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
