import { HomeSummaryService } from './home-summary.service';

describe('HomeSummaryService', () => {
  function createHarness(
    dependencies: { authContextService?: any; redis?: any } = {},
  ) {
    const syncOrderRows = [
      {
        orderCode: '2607040001',
        orderCreatedAt: new Date('2026-07-04T02:00:00Z'),
        fetchedAt: new Date('2026-07-04T02:05:00Z'),
        storeCode: 'CP75',
        storeName: 'CP75',
        organizationNodeId: 'node-cp75',
        sourceUserId: 'user-1',
        sourceUserEmail: 'staff@phongvu.vn',
        consultantCustomId: 'PV001',
        consultantName: 'Staff',
        consultantEmail: 'staff@phongvu.vn',
        sellerId: 'PV001',
        sellerName: 'Staff',
        sellerEmail: 'staff@phongvu.vn',
        grandTotal: 12500000,
      },
      {
        orderCode: '2607040002',
        grandTotal: 5000000,
        orderCreatedAt: new Date('2026-07-04T05:00:00Z'),
        fetchedAt: new Date('2026-07-04T05:10:00Z'),
        storeCode: 'CP75',
        storeName: 'CP75',
        organizationNodeId: 'node-cp75',
        sourceUserId: 'user-1',
        sourceUserEmail: 'staff@phongvu.vn',
        consultantCustomId: 'PV001',
        consultantName: 'Staff',
        consultantEmail: 'staff@phongvu.vn',
        sellerId: 'PV001',
        sellerName: 'Staff',
        sellerEmail: 'staff@phongvu.vn',
        grandTotal: 5000000,
      },
    ];
    const revenueOrderRows = [
      {
        orderCode: '2607040001',
        grandTotal: 12500000,
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
      },
      {
        orderCode: '2607040002',
        grandTotal: 5000000,
        lifecycleStatus: 'COMPLETED_PARTIAL_RETURN',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 1000000,
      },
      {
        orderCode: '2607040003',
        grandTotal: 7000000,
        lifecycleStatus: 'CANCELLED',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
      },
      {
        orderCode: '2607040004',
        grandTotal: 3000000,
        lifecycleStatus: 'RETURNED_FULL',
        hasReturnedFullItems: true,
        returnedAfterTaxAmount: 3000000,
      },
    ];
    const prisma = {
      salesReport: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'report-1',
            reportType: 'PURCHASED',
            orderCode: '2607040001',
            createdByUserId: 'user-1',
            createdByEmail: 'staff@phongvu.vn',
            createdByPersonnelCode: 'PV001',
            storeCode: 'CP75',
            storeName: 'CP75',
            organizationNodeId: 'node-cp75',
            erpGrandTotal: 12500000,
            erpConsultantCustomId: 'PV001',
            erpConsultantName: 'Staff',
            erpOrderCreatedAt: new Date('2026-07-04T02:00:00Z'),
            erpFetchedAt: new Date('2026-07-04T02:10:00Z'),
            submittedAt: new Date('2026-07-04T02:20:00Z'),
          },
          {
            id: 'report-2',
            reportType: 'NOT_PURCHASED',
            orderCode: null,
            createdByUserId: 'user-1',
            createdByEmail: 'staff@phongvu.vn',
            createdByPersonnelCode: 'PV001',
            storeCode: 'CP75',
            storeName: 'CP75',
            organizationNodeId: 'node-cp75',
            erpGrandTotal: null,
            erpConsultantCustomId: null,
            erpConsultantName: null,
            erpOrderCreatedAt: null,
            erpFetchedAt: null,
            submittedAt: new Date('2026-07-04T03:00:00Z'),
          },
        ]),
        count: jest
          .fn()
          .mockImplementation(({ where }: any) =>
            Promise.resolve(
              where?.consultedSolutionAnswer === 'YES' ||
                where?.experiencedAnswer === 'YES' ||
                where?.zaloAnswer === 'YES' ||
                where?.appDownloadAnswer === 'YES'
                ? 1
                : 0,
            ),
          ),
      },
      salesReportErpOrderCache: {
        findMany: jest
          .fn()
          .mockImplementation(({ select }: any) =>
            Promise.resolve(
              select?.lifecycleStatus ? revenueOrderRows : syncOrderRows,
            ),
          ),
      },
      user: {
        findUnique: jest.fn().mockResolvedValue({ jobRoleCode: 'SA' }),
        findMany: jest.fn().mockResolvedValue([]),
      },
      store: {
        findMany: jest.fn().mockResolvedValue([]),
      },
      salesTarget: {
        findMany: jest.fn().mockResolvedValue([]),
      },
      homeSummaryReportFact: {
        upsert: jest.fn().mockResolvedValue({}),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
        count: jest
          .fn()
          .mockImplementation(({ where }: any) =>
            Promise.resolve(where?.reportType === 'NOT_PURCHASED' ? 1 : 2),
          ),
        aggregate: jest.fn().mockResolvedValue({ _sum: { revenue: 12500000 } }),
        findMany: jest.fn().mockResolvedValue([{ orderCode: '2607040001' }]),
      },
      homeSummaryOrderFact: {
        upsert: jest.fn().mockResolvedValue({}),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
        count: jest.fn().mockResolvedValueOnce(2).mockResolvedValueOnce(1),
        findMany: jest
          .fn()
          .mockResolvedValue([
            { orderCode: '2607040001' },
            { orderCode: '2607040002' },
          ]),
      },
      homeSummaryProjectionState: {
        findMany: jest.fn().mockResolvedValue([]),
      },
      homeSummaryDailyAggregate: {
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
        aggregate: jest.fn().mockResolvedValue({
          _sum: { amount: 42000000 },
        }),
      },
      $transaction: jest.fn(async (input: any) => {
        if (Array.isArray(input)) {
          return Promise.all(input);
        }
        return input(prisma);
      }),
    };
    const salesReports = {
      describeHomeSummaryScope: jest.fn().mockResolvedValue({
        available: true,
        scope: 'OWN',
        scopeLabel: 'Phạm vi cá nhân',
        scopeDetail: 'CP75',
        unavailableMessage: null,
        ownUserId: 'user-1',
        ownEmail: 'staff@phongvu.vn',
        ownPersonnelCode: 'PV001',
        allowedStoreCodes: ['CP75'],
      }),
      summarizeSalesRevenueRows: jest.fn().mockReturnValue({
        orderCountUnique: 2,
        businessRevenue: 12500000,
        personalRevenue: 4000000,
        noInstallmentReasons: new Map(),
        installmentNeedTotalCount: 2,
        examScorePromotionCount: 1,
        studentPromotionCount: 1,
        successfulInstallmentOrderCount: 1,
        laptopQuantity: 2,
        pcQuantity: 1,
        assembledPcQuantity: 1,
        appleQuantity: 1,
        monitorQuantity: 3,
        printerQuantity: 1,
        accessoriesQuantity: 4,
        extendedInsuranceQuantity: 1,
      }),
      listHomeSummaryScopeOptions: jest.fn().mockResolvedValue([
        {
          label: 'Cửa hàng được phân quyền',
          scope: 'MANAGED_SCOPE',
          organizationNodeId: 'node-1',
        },
      ]),
    };
    const featureService = {
      canAccessFeature: jest.fn().mockResolvedValue(true),
    };
    const service = new HomeSummaryService(
      prisma as any,
      salesReports as any,
      featureService as any,
      dependencies.authContextService,
      dependencies.redis,
    );
    return {
      service,
      prisma,
      salesReports,
      featureService,
      ...dependencies,
    };
  }

  function completeProjectionStates(dates: string[]) {
    const generatedAt = new Date('2026-07-07T03:00:04.000Z');
    const sourceUpdatedAt = new Date('2026-07-07T03:00:00.000Z');
    return dates.map((date, index) => ({
      summaryDate: new Date(`${date}T00:00:00.000Z`),
      status: 'COMPLETE',
      projectionVersion: BigInt(40 + index),
      salesStatus: 'COMPLETE',
      salesProjectionVersion: BigInt(40 + index),
      salesGeneratedAt: generatedAt,
      financeStatus: 'COMPLETE',
      financeProjectionVersion: BigInt(30 + index),
      financeGeneratedAt: generatedAt,
      sourceUpdatedAt,
      salesReportSourceUpdatedAt: sourceUpdatedAt,
      erpOrderCacheSourceUpdatedAt: sourceUpdatedAt,
      mapVietinSourceUpdatedAt: sourceUpdatedAt,
      generatedAt,
    }));
  }

  function salesAssignee(id: string, email: string, storeCode: string) {
    return {
      id,
      email,
      firstName: 'SA',
      lastName: id,
      jobRoleCode: 'SA',
      areaCode: 'HCM',
      regionCode: 'SOUTH',
      store: {
        storeId: storeCode,
        storeName: storeCode,
        area: {
          code: 'HCM',
          region: { code: 'SOUTH' },
        },
        organizationNode: null,
      },
      area: {
        code: 'HCM',
        region: { code: 'SOUTH' },
      },
      region: { code: 'SOUTH' },
      organizationNode: null,
      organizationAssignments: [],
    };
  }

  it('hydrates one auth context and reuses it across Home authorization and scope work', async () => {
    const rawUser = {
      id: 'user-1',
      email: 'staff@phongvu.vn',
      jobRoleCode: 'STAFF',
    };
    const contextUser = {
      ...rawUser,
      __authContext: {
        featureAccess: {
          HOME_DASHBOARD_SALES: true,
          HOME_DASHBOARD_FINANCE: false,
          ADMIN_SALES_REPORTS: false,
        },
        scopeSnapshot: { ...rawUser, organizationAssignments: [] },
      },
    };
    const authContextService = {
      withFeatureScopeContext: jest.fn().mockResolvedValue(contextUser),
    };
    const { service, salesReports } = createHarness({ authContextService });
    const sectionAccess = jest
      .spyOn(service as any, 'resolveSectionAccess')
      .mockResolvedValue({ salesAvailable: true, financeAvailable: false });
    jest.spyOn(service as any, 'projectionEnabled').mockReturnValue(true);
    jest
      .spyOn(service as any, 'loadProjectionFreshnessCached')
      .mockResolvedValue({
        freshness: {
          projectionGeneratedAt: new Date('2026-07-04T03:00:00Z'),
          projectionLagSeconds: 0,
          projectionVersion: 40,
          sourceUpdatedAtBySource: {},
          isStale: false,
        },
        versionsByDate: new Map([['2026-07-04', 40]]),
      });
    const progressBundle = (service as any).emptySalesProgressBundle();
    const progressLoad = jest
      .spyOn(service as any, 'buildSalesProgressBundleCached')
      .mockResolvedValue(progressBundle);
    jest
      .spyOn(service as any, 'loadProjectionMetrics')
      .mockResolvedValue((service as any).emptyProjectionMetrics());

    await (service as any).computeSummary(rawUser, {
      startDate: '2026-07-04',
      endDate: '2026-07-04',
    });

    expect(authContextService.withFeatureScopeContext).toHaveBeenCalledTimes(1);
    expect(authContextService.withFeatureScopeContext).toHaveBeenCalledWith(
      rawUser,
      ['HOME_DASHBOARD_SALES', 'HOME_DASHBOARD_FINANCE', 'ADMIN_SALES_REPORTS'],
    );
    expect(sectionAccess).toHaveBeenCalledWith(contextUser);
    expect(salesReports.describeHomeSummaryScope).toHaveBeenCalledWith(
      contextUser,
      'AUTO',
      null,
      { allowOwnScope: true },
    );
    expect(progressLoad).toHaveBeenCalledWith(
      contextUser,
      expect.objectContaining({ scope: 'OWN' }),
      expect.any(Date),
      expect.objectContaining({
        start: expect.any(Date),
        end: expect.any(Date),
      }),
      null,
    );
  });

  it('caches repeated summary loads for the same user and query for the Home TTL', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service, salesReports } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const query = { startDate: '2026-07-04', endDate: '2026-07-04' };

      const first = await service.getSummary(user, query);
      const second = await service.getSummary(user, query);

      expect(second).toBe(first);
      expect(salesReports.describeHomeSummaryScope).toHaveBeenCalledTimes(1);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('uses a full canonical SHA-256 cache key without retaining the raw principal', () => {
    const { service } = createHarness();
    const key = (service as any).summaryResponseCacheKey(
      { email: 'staff@phongvu.vn' },
      { startDate: '2026-07-04', endDate: '2026-07-04' },
    );

    expect(key).toMatch(/^v6:[a-f0-9]{64}$/);
    expect(key).not.toContain('staff@phongvu.vn');
  });

  it('invalidates the response cache identity after access reassignment', () => {
    const { service } = createHarness();
    const query = { startDate: '2026-07-04', endDate: '2026-07-04' };
    const before = (service as any).summaryResponseCacheKey(
      {
        id: 'user-1',
        tokenVersion: 3,
        accessVersion: 8,
        authSession: { sessionVersion: 5 },
      },
      query,
    );
    const afterReassignment = (service as any).summaryResponseCacheKey(
      {
        id: 'user-1',
        tokenVersion: 3,
        accessVersion: 9,
        authSession: { sessionVersion: 5 },
      },
      query,
    );
    const afterSessionRefresh = (service as any).summaryResponseCacheKey(
      {
        id: 'user-1',
        tokenVersion: 3,
        accessVersion: 9,
        authSession: { sessionVersion: 6 },
      },
      query,
    );

    expect(afterReassignment).not.toBe(before);
    expect(afterSessionRefresh).not.toBe(afterReassignment);
  });

  it('rate-limits repeated cache-hit diagnostics on the hot path', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const debug = jest.spyOn((service as any).logger, 'debug');
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const query = { startDate: '2026-07-04', endDate: '2026-07-04' };

      await service.getSummary(user, query);
      await service.getSummary(user, query);
      await service.getSummary(user, query);

      expect(
        debug.mock.calls.filter(([message]) =>
          String(message).includes('Home summary cache hit:'),
        ),
      ).toHaveLength(1);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('separates legacy and daily-series response cache generations', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const legacyResponse = { legacy: true } as any;
      const dailyResponse = { dailySeries: [] } as any;
      jest
        .spyOn(service as any, 'computeSummary')
        .mockResolvedValueOnce(legacyResponse)
        .mockResolvedValueOnce(dailyResponse);

      await expect(
        service.getSummary(user, {
          startDate: '2026-07-04',
          endDate: '2026-07-04',
        }),
      ).resolves.toBe(legacyResponse);
      await expect(
        service.getSummary(user, {
          startDate: '2026-07-04',
          endDate: '2026-07-04',
          includeDailySeries: 'false',
        }),
      ).resolves.toBe(legacyResponse);
      await expect(
        service.getSummary(user, {
          startDate: '2026-07-04',
          endDate: '2026-07-04',
          includeDailySeries: 'true',
        }),
      ).resolves.toBe(dailyResponse);

      expect((service as any).computeSummary).toHaveBeenCalledTimes(2);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('extends a fresh principal-specific legacy cache with one scoped daily projection read', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const legacyQuery = {
        startDate: '2026-07-04',
        endDate: '2026-07-04',
      };
      const dailyQuery = {
        ...legacyQuery,
        includeDailySeries: 'true' as const,
      };
      const legacyResponse = {
        totalRevenue: 10,
        totalOrders: 2,
        reportedOrders: 1,
        totalReports: 3,
        freshness: { projectionVersion: 40 },
      } as any;
      const compute = jest
        .spyOn(service as any, 'computeSummary')
        .mockResolvedValue(legacyResponse);
      const projection = jest
        .spyOn(service as any, 'loadProjectionMetrics')
        .mockResolvedValue({
          totalRevenue: 10,
          totalOrders: 2,
          reportedOrders: 1,
          totalReports: 3,
          dailySeries: [
            {
              date: '2026-07-04',
              totalRevenue: 10,
              totalOrders: 2,
              reportedOrders: 1,
              totalReports: 3,
            },
          ],
        });

      await expect(service.getSummary(user, legacyQuery)).resolves.toBe(
        legacyResponse,
      );
      (service as any).computationContextByResponse.set(legacyResponse, {
        useProjection: true,
        salesAvailable: true,
        salesMetricsScope: {
          available: true,
          scope: 'OWN',
          scopeLabel: 'Pháº¡m vi cÃ¡ nhÃ¢n',
          scopeDetail: 'CP75',
          unavailableMessage: null,
          ownUserId: 'user-1',
          ownEmail: 'staff@phongvu.vn',
          ownPersonnelCode: 'PV001',
          allowedStoreCodes: ['CP75'],
        },
      });

      const extended = await service.getSummary(user, dailyQuery);
      await expect(service.getSummary(user, dailyQuery)).resolves.toBe(
        extended,
      );

      expect(compute).toHaveBeenCalledTimes(1);
      expect(projection).toHaveBeenCalledTimes(1);
      expect(projection).toHaveBeenCalledWith(
        expect.objectContaining({
          startDate: '2026-07-04',
          endDate: '2026-07-04',
        }),
        expect.objectContaining({
          scope: 'OWN',
          ownEmail: 'staff@phongvu.vn',
          allowedStoreCodes: ['CP75'],
        }),
        'SALES',
        true,
      );
      expect(legacyResponse).not.toHaveProperty('dailySeries');
      expect(extended).not.toBe(legacyResponse);
      expect(extended.dailySeries).toHaveLength(1);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('falls back to a full opted-in computation when a cached legacy aggregate drifts', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const legacyQuery = {
        startDate: '2026-07-04',
        endDate: '2026-07-04',
      };
      const legacyResponse = {
        totalRevenue: 10,
        totalOrders: 2,
        reportedOrders: 1,
        totalReports: 3,
        freshness: { projectionVersion: 40 },
      } as any;
      const recomputed = {
        ...legacyResponse,
        totalRevenue: 11,
        dailySeries: [
          {
            date: '2026-07-04',
            totalRevenue: 11,
            totalOrders: 2,
            reportedOrders: 1,
            totalReports: 3,
          },
        ],
      } as any;
      const compute = jest
        .spyOn(service as any, 'computeSummary')
        .mockResolvedValueOnce(legacyResponse)
        .mockResolvedValueOnce(recomputed);
      jest.spyOn(service as any, 'loadProjectionMetrics').mockResolvedValue({
        totalRevenue: 11,
        totalOrders: 2,
        reportedOrders: 1,
        totalReports: 3,
        dailySeries: recomputed.dailySeries,
      });

      await service.getSummary(user, legacyQuery);
      (service as any).computationContextByResponse.set(legacyResponse, {
        useProjection: true,
        salesAvailable: true,
        salesMetricsScope: {
          available: true,
          scope: 'OWN',
          scopeLabel: 'Pháº¡m vi cÃ¡ nhÃ¢n',
          scopeDetail: 'CP75',
          unavailableMessage: null,
          ownUserId: 'user-1',
          ownEmail: 'staff@phongvu.vn',
          ownPersonnelCode: 'PV001',
          allowedStoreCodes: ['CP75'],
        },
      });

      await expect(
        service.getSummary(user, {
          ...legacyQuery,
          includeDailySeries: 'true',
        }),
      ).resolves.toBe(recomputed);
      expect(compute).toHaveBeenCalledTimes(2);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('does not store a daily extension invalidated while its projection read is in flight', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const legacyQuery = {
        startDate: '2026-07-04',
        endDate: '2026-07-04',
      };
      const dailyQuery = {
        ...legacyQuery,
        includeDailySeries: 'true' as const,
      };
      const legacyResponse = {
        totalRevenue: 10,
        totalOrders: 2,
        reportedOrders: 1,
        totalReports: 3,
      } as any;
      const recomputed = {
        ...legacyResponse,
        dailySeries: [],
      } as any;
      const compute = jest
        .spyOn(service as any, 'computeSummary')
        .mockResolvedValueOnce(legacyResponse)
        .mockResolvedValueOnce(recomputed);
      let resolveProjection!: (value: any) => void;
      jest
        .spyOn(service as any, 'loadProjectionMetrics')
        .mockImplementationOnce(
          () =>
            new Promise((resolve) => {
              resolveProjection = resolve;
            }),
        );

      await service.getSummary(user, legacyQuery);
      (service as any).computationContextByResponse.set(legacyResponse, {
        useProjection: true,
        salesAvailable: true,
        salesMetricsScope: {
          available: true,
          scope: 'OWN',
          scopeLabel: 'PhÃ¡ÂºÂ¡m vi cÃƒÂ¡ nhÃƒÂ¢n',
          scopeDetail: 'CP75',
          unavailableMessage: null,
          ownUserId: 'user-1',
          ownEmail: 'staff@phongvu.vn',
          ownPersonnelCode: 'PV001',
          allowedStoreCodes: ['CP75'],
        },
      });

      const pending = service.getSummary(user, dailyQuery);
      await Promise.resolve();
      const invalidation = service.invalidateSummaryResponseCache([
        { affectedDates: ['2026-07-04'], projectionVersion: 41 },
      ]);
      expect(invalidation.invalidatedInFlight).toBe(1);

      resolveProjection({
        totalRevenue: 10,
        totalOrders: 2,
        reportedOrders: 1,
        totalReports: 3,
        dailySeries: [],
      });
      await pending;
      const dailyKey = (service as any).summaryResponseCacheKey(
        user,
        dailyQuery,
      );
      expect((service as any).summaryResponseCache.has(dailyKey)).toBe(false);
      await expect(service.getSummary(user, dailyQuery)).resolves.toBe(
        recomputed,
      );
      expect(compute).toHaveBeenCalledTimes(2);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('deduplicates shared freshness and managed-scope progress while isolating principal progress', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const range = (service as any).parseSummaryRange({
        startDate: '2026-07-01',
        endDate: '2026-07-07',
      });
      const freshness = {
        freshness: {
          projectionGeneratedAt: new Date('2026-07-07T03:00:00Z'),
          projectionLagSeconds: 0,
          projectionVersion: 40,
          sourceUpdatedAtBySource: {},
          isStale: false,
        },
        versionsByDate: new Map([['2026-07-07', 40]]),
      };
      const freshnessLoad = jest
        .spyOn(service as any, 'loadProjectionFreshness')
        .mockResolvedValue(freshness);

      await Promise.all([
        (service as any).loadProjectionFreshnessCached(range, true, true),
        (service as any).loadProjectionFreshnessCached(range, true, true),
      ]);
      expect(freshnessLoad).toHaveBeenCalledTimes(1);

      const managedScope = {
        available: true,
        scope: 'MANAGED_SCOPE',
        scopeLabel: 'Cá»­a hÃ ng',
        scopeDetail: 'CP75',
        unavailableMessage: null,
        ownUserId: null,
        ownEmail: null,
        ownPersonnelCode: null,
        allowedStoreCodes: ['CP75'],
      };
      const progress = {
        status: 'AVAILABLE',
        scope: 'MANAGED',
        missingStoreCodes: [],
        range: { actual: 1, target: 2, percentage: 50 },
        day: { actual: 1, target: 2, percentage: 50 },
        week: { actual: 1, target: 2, percentage: 50 },
        month: { actual: 1, target: 2, percentage: 50 },
      };
      const progressLoad = jest
        .spyOn(service as any, 'buildSalesProgress')
        .mockResolvedValue(progress);
      const summaryDate = new Date('2026-07-07T00:00:00Z');
      await Promise.all([
        (service as any).buildSharedScopeSalesProgressCached(
          managedScope,
          summaryDate,
          range,
        ),
        (service as any).buildSharedScopeSalesProgressCached(
          { ...managedScope, allowedStoreCodes: ['cp75'] },
          summaryDate,
          range,
        ),
      ]);
      expect(progressLoad).toHaveBeenCalledTimes(1);
      expect(() =>
        (service as any).buildSharedScopeSalesProgressCached(
          { ...managedScope, scope: 'OWN' },
          summaryDate,
          range,
        ),
      ).toThrow('Shared sales progress requires a non-personal scope.');

      const bundle = {
        personal: progress,
        scope: progress,
        assignees: [],
        selectedUserId: null,
        selectedScope: null,
      };
      const bundleLoad = jest
        .spyOn(service as any, 'buildSalesProgressBundle')
        .mockResolvedValue(bundle);
      const ownScope = {
        ...managedScope,
        scope: 'OWN',
        ownUserId: 'user-1',
        ownEmail: 'staff@phongvu.vn',
      };
      await (service as any).buildSalesProgressBundleCached(
        { id: 'user-1', email: 'staff@phongvu.vn' },
        ownScope,
        summaryDate,
        range,
        null,
      );
      await (service as any).buildSalesProgressBundleCached(
        { id: 'user-1', email: 'staff@phongvu.vn' },
        ownScope,
        summaryDate,
        range,
        null,
      );
      await (service as any).buildSalesProgressBundleCached(
        { id: 'user-2', email: 'staff2@phongvu.vn' },
        {
          ...ownScope,
          ownUserId: 'user-2',
          ownEmail: 'staff2@phongvu.vn',
        },
        summaryDate,
        range,
        null,
      );
      expect(bundleLoad).toHaveBeenCalledTimes(2);

      const invalidation = service.invalidateSummaryResponseCache([
        { affectedDates: ['2026-07-07'], projectionVersion: 41 },
      ]);
      expect(invalidation.invalidatedSupportEntries).toBeGreaterThanOrEqual(4);
      await (service as any).loadProjectionFreshnessCached(range, true, true);
      expect(freshnessLoad).toHaveBeenCalledTimes(2);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('expires support data after five seconds so it cannot extend the response staleness window', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    const nowSpy = jest.spyOn(Date, 'now').mockReturnValue(1_000_000);
    try {
      const { service } = createHarness();
      const range = (service as any).parseSummaryRange({
        startDate: '2026-07-01',
        endDate: '2026-07-07',
      });
      const load = jest
        .spyOn(service as any, 'loadProjectionFreshness')
        .mockResolvedValue({
          freshness: {
            projectionGeneratedAt: new Date('2026-07-07T03:00:00Z'),
            projectionLagSeconds: 0,
            projectionVersion: 40,
            sourceUpdatedAtBySource: {},
            isStale: false,
          },
          versionsByDate: new Map([['2026-07-07', 40]]),
        });

      await (service as any).loadProjectionFreshnessCached(range, true, true);
      nowSpy.mockReturnValue(1_004_999);
      await (service as any).loadProjectionFreshnessCached(range, true, true);
      expect(load).toHaveBeenCalledTimes(1);

      nowSpy.mockReturnValue(1_005_001);
      await (service as any).loadProjectionFreshnessCached(range, true, true);
      expect(load).toHaveBeenCalledTimes(2);
    } finally {
      nowSpy.mockRestore();
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('prevents an invalidated support load from overwriting a newer cache generation', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const range = (service as any).parseSummaryRange({
        startDate: '2026-07-01',
        endDate: '2026-07-07',
      });
      const oldValue = {
        freshness: { projectionVersion: 40 },
        versionsByDate: new Map([['2026-07-07', 40]]),
      } as any;
      const newValue = {
        freshness: { projectionVersion: 41 },
        versionsByDate: new Map([['2026-07-07', 41]]),
      } as any;
      let resolveOld!: (value: any) => void;
      const oldPromise = new Promise((resolve) => {
        resolveOld = resolve;
      });
      const load = jest
        .spyOn(service as any, 'loadProjectionFreshness')
        .mockImplementationOnce(() => oldPromise)
        .mockResolvedValueOnce(newValue);

      const oldLoad = (service as any).loadProjectionFreshnessCached(
        range,
        true,
        true,
      );
      service.invalidateSummaryResponseCache([
        { affectedDates: ['2026-07-07'], projectionVersion: 41 },
      ]);
      await expect(
        (service as any).loadProjectionFreshnessCached(range, true, true),
      ).resolves.toBe(newValue);

      resolveOld(oldValue);
      await expect(oldLoad).resolves.toBe(oldValue);
      await expect(
        (service as any).loadProjectionFreshnessCached(range, true, true),
      ).resolves.toBe(newValue);
      expect(load).toHaveBeenCalledTimes(2);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('invalidates only overlapping summary ranges and ignores duplicate projection versions', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const query = { startDate: '2026-07-04', endDate: '2026-07-04' };
      const firstResponse = { freshness: { projectionVersion: 40 } } as any;
      const currentResponse = { freshness: { projectionVersion: 42 } } as any;
      jest
        .spyOn(service as any, 'computeSummary')
        .mockResolvedValueOnce(firstResponse)
        .mockResolvedValueOnce(currentResponse);

      await service.getSummary(user, query);
      service.invalidateSummaryResponseCache([
        { affectedDates: ['2026-07-05'], projectionVersion: 41 },
      ]);
      await service.getSummary(user, query);
      expect((service as any).computeSummary).toHaveBeenCalledTimes(1);

      service.invalidateSummaryResponseCache([
        { affectedDates: ['2026-07-04'], projectionVersion: 42 },
      ]);
      await service.getSummary(user, query);
      expect((service as any).computeSummary).toHaveBeenCalledTimes(2);

      const duplicate = service.invalidateSummaryResponseCache([
        { affectedDates: ['2026-07-04'], projectionVersion: 42 },
      ]);
      await service.getSummary(user, query);
      expect(duplicate.affectedDates).toBe(0);
      expect(duplicate.invalidatedCacheEntries).toBe(0);
      expect(duplicate.ignoredUpdates).toBe(1);
      expect((service as any).computeSummary).toHaveBeenCalledTimes(2);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('invalidates legacy and daily-series cache generations from the same projection event', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const legacyQuery = {
        startDate: '2026-07-04',
        endDate: '2026-07-04',
      };
      const dailyQuery = {
        ...legacyQuery,
        includeDailySeries: 'true' as const,
      };
      const legacyBefore = {
        freshness: { projectionVersion: 40 },
      } as any;
      const dailyBefore = {
        freshness: { projectionVersion: 40 },
        dailySeries: [],
      } as any;
      const legacyAfter = {
        freshness: { projectionVersion: 41 },
      } as any;
      const dailyAfter = {
        freshness: { projectionVersion: 41 },
        dailySeries: [],
      } as any;
      jest
        .spyOn(service as any, 'computeSummary')
        .mockResolvedValueOnce(legacyBefore)
        .mockResolvedValueOnce(dailyBefore)
        .mockResolvedValueOnce(legacyAfter)
        .mockResolvedValueOnce(dailyAfter);

      await service.getSummary(user, legacyQuery);
      await service.getSummary(user, dailyQuery);
      expect((service as any).summaryResponseCache.size).toBe(2);

      const invalidation = service.invalidateSummaryResponseCache([
        { affectedDates: ['2026-07-04'], projectionVersion: 41 },
      ]);
      expect(invalidation.invalidatedCacheEntries).toBe(2);

      await expect(service.getSummary(user, legacyQuery)).resolves.toBe(
        legacyAfter,
      );
      await expect(service.getSummary(user, dailyQuery)).resolves.toBe(
        dailyAfter,
      );
      expect((service as any).computeSummary).toHaveBeenCalledTimes(4);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('compares projection versions per date instead of using only the range maximum', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const query = { startDate: '2026-07-04', endDate: '2026-07-05' };
      const staleForFirstDate = {
        freshness: { projectionVersion: 100 },
      } as any;
      const current = { freshness: { projectionVersion: 101 } } as any;
      (service as any).projectionVersionsByResponse.set(
        staleForFirstDate,
        new Map([
          ['2026-07-04', 10],
          ['2026-07-05', 100],
        ]),
      );
      jest
        .spyOn(service as any, 'computeSummary')
        .mockResolvedValueOnce(staleForFirstDate)
        .mockResolvedValueOnce(current);

      await service.getSummary(user, query);
      const invalidation = service.invalidateSummaryResponseCache([
        { affectedDates: ['2026-07-04'], projectionVersion: 11 },
      ]);
      await expect(service.getSummary(user, query)).resolves.toBe(current);

      expect(invalidation.invalidatedCacheEntries).toBe(1);
      expect((service as any).computeSummary).toHaveBeenCalledTimes(2);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('keeps a cache computed from a newer projection when an older outbox event arrives', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const query = { startDate: '2026-07-04', endDate: '2026-07-04' };
      const current = { freshness: { projectionVersion: 50 } } as any;
      jest.spyOn(service as any, 'computeSummary').mockResolvedValue(current);

      await service.getSummary(user, query);
      const staleEvent = service.invalidateSummaryResponseCache([
        { affectedDates: ['2026-07-04'], projectionVersion: 49 },
      ]);
      await expect(service.getSummary(user, query)).resolves.toBe(current);

      expect(staleEvent.invalidatedCacheEntries).toBe(0);
      expect(staleEvent.coveredCacheEntries).toBe(1);
      expect((service as any).computeSummary).toHaveBeenCalledTimes(1);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('keeps a newer in-flight generation when an invalidated load completes late', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    try {
      const { service } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const query = { startDate: '2026-07-04', endDate: '2026-07-04' };
      const oldResponse = { freshness: { projectionVersion: 41 } } as any;
      const newResponse = { freshness: { projectionVersion: 42 } } as any;
      let resolveOld!: (value: any) => void;
      let resolveNew!: (value: any) => void;
      const oldLoad = new Promise<any>((resolve) => {
        resolveOld = resolve;
      });
      const newLoad = new Promise<any>((resolve) => {
        resolveNew = resolve;
      });
      jest
        .spyOn(service as any, 'computeSummary')
        .mockReturnValueOnce(oldLoad)
        .mockReturnValueOnce(newLoad);

      const first = service.getSummary(user, query);
      service.invalidateSummaryResponseCache([
        { affectedDates: ['2026-07-04'], projectionVersion: 42 },
      ]);
      const second = service.getSummary(user, query);

      resolveOld(oldResponse);
      await expect(first).resolves.toBe(oldResponse);
      expect((service as any).summaryInFlight.size).toBe(1);

      resolveNew(newResponse);
      await expect(second).resolves.toBe(newResponse);
      await expect(service.getSummary(user, query)).resolves.toBe(newResponse);
      expect((service as any).computeSummary).toHaveBeenCalledTimes(2);
    } finally {
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('refreshes hot summary keys ahead of the hard TTL without blocking the hit', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    const nowSpy = jest.spyOn(Date, 'now').mockReturnValue(1_000_000);
    try {
      const { service } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const query = { startDate: '2026-07-04', endDate: '2026-07-04' };
      const firstResponse = { freshness: { projectionVersion: 41 } } as any;
      const refreshedResponse = { freshness: { projectionVersion: 41 } } as any;
      let resolveRefresh!: (value: any) => void;
      const refreshLoad = new Promise<any>((resolve) => {
        resolveRefresh = resolve;
      });
      jest
        .spyOn(service as any, 'computeSummary')
        .mockResolvedValueOnce(firstResponse)
        .mockReturnValueOnce(refreshLoad);

      await service.getSummary(user, query);
      nowSpy.mockReturnValue(1_051_000);
      await expect(service.getSummary(user, query)).resolves.toBe(
        firstResponse,
      );
      expect((service as any).computeSummary).toHaveBeenCalledTimes(2);

      const refreshEntry = Array.from(
        (service as any).summaryInFlight.values(),
      )[0] as { promise: Promise<any> };
      resolveRefresh(refreshedResponse);
      await refreshEntry.promise;

      await expect(service.getSummary(user, query)).resolves.toBe(
        refreshedResponse,
      );
    } finally {
      nowSpy.mockRestore();
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('keeps the original hard expiry when refresh-ahead fails', async () => {
    const previousCacheFlag = process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
    process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = 'true';
    const nowSpy = jest.spyOn(Date, 'now').mockReturnValue(1_000_000);
    try {
      const { service } = createHarness();
      const user = { id: 'user-1', email: 'staff@phongvu.vn' };
      const query = { startDate: '2026-07-04', endDate: '2026-07-04' };
      const firstResponse = { freshness: { projectionVersion: 41 } } as any;
      const afterExpiryResponse = {
        freshness: { projectionVersion: 41 },
      } as any;
      jest
        .spyOn(service as any, 'computeSummary')
        .mockResolvedValueOnce(firstResponse)
        .mockRejectedValueOnce(new Error('refresh failed'))
        .mockResolvedValueOnce(afterExpiryResponse);

      await service.getSummary(user, query);
      nowSpy.mockReturnValue(1_051_000);
      await expect(service.getSummary(user, query)).resolves.toBe(
        firstResponse,
      );
      await new Promise((resolve) => setImmediate(resolve));
      const cached = Array.from(
        (service as any).summaryResponseCache.values(),
      )[0] as { expiresAt: number };
      expect(cached.expiresAt).toBe(1_060_000);

      nowSpy.mockReturnValue(1_061_000);
      await expect(service.getSummary(user, query)).resolves.toBe(
        afterExpiryResponse,
      );
      expect((service as any).computeSummary).toHaveBeenCalledTimes(3);
    } finally {
      nowSpy.mockRestore();
      if (previousCacheFlag === undefined) {
        delete process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED;
      } else {
        process.env.HOME_SUMMARY_RESPONSE_CACHE_ENABLED = previousCacheFlag;
      }
    }
  });

  it('caches repeated Home scope option loads for the same user for the Home TTL', async () => {
    const { service, salesReports, featureService } = createHarness();
    const user = { id: 'user-1', email: 'staff@phongvu.vn' };

    const first = await service.listScopeOptions(user);
    const second = await service.listScopeOptions(user);

    expect(second).toBe(first);
    expect(featureService.canAccessFeature).toHaveBeenCalledTimes(2);
    expect(salesReports.listHomeSummaryScopeOptions).toHaveBeenCalledTimes(1);
  });

  it('uses a 5 second L1 TTL and a 60 second shared TTL for Home scope options', async () => {
    const nowSpy = jest.spyOn(Date, 'now').mockReturnValue(1_000_000);
    const redis = {
      getJson: jest.fn().mockResolvedValue(null),
      setJsonWithTtl: jest.fn().mockResolvedValue(undefined),
    };
    try {
      const { service } = createHarness({ redis });
      const response = await service.listScopeOptions({
        id: 'user-1',
        email: 'staff@phongvu.vn',
      });

      const cacheEntry = Array.from(
        (service as any).scopeOptionsCache.values(),
      )[0] as { expiresAt: number };
      expect(cacheEntry.expiresAt).toBe(1_005_000);
      expect(redis.setJsonWithTtl).toHaveBeenCalledWith(
        expect.stringMatching(/^opshub:home:scope-options:/),
        response,
        60,
      );
    } finally {
      nowSpy.mockRestore();
    }
  });

  it('deduplicates concurrent Home scope option loads before shared cache lookup', async () => {
    const redis = {
      getJson: jest.fn().mockResolvedValue(null),
      setJsonWithTtl: jest.fn().mockResolvedValue(undefined),
    };
    const { service, salesReports } = createHarness({ redis });
    const user = { id: 'user-1', email: 'staff@phongvu.vn' };

    const [first, second] = await Promise.all([
      service.listScopeOptions(user),
      service.listScopeOptions(user),
    ]);

    expect(second).toBe(first);
    expect(redis.getJson).toHaveBeenCalledTimes(1);
    expect(salesReports.listHomeSummaryScopeOptions).toHaveBeenCalledTimes(1);
  });

  it('returns scoped summary metrics from dedicated home summary facts', async () => {
    const { service, prisma, salesReports } = createHarness();

    await expect(
      service.getSummary(
        { id: 'user-1', email: 'staff@phongvu.vn' },
        { date: '2026-07-04' },
      ),
    ).resolves.toMatchObject({
      available: true,
      scope: 'OWN',
      scopeLabel: 'Phạm vi cá nhân',
      coverageLabel: 'Tỉ lệ báo cáo',
      totalRevenue: 17500000,
      totalOrders: 2,
      totalReports: 2,
      reportedOrders: 1,
      notPurchasedReports: 1,
      unreportedOrders: 1,
      averageOrderValue: 8750000,
      completedRevenue: 12500000,
      pendingRevenue: 5000000,
      businessCustomerRevenue: 12500000,
      personalCustomerRevenue: 4000000,
      examScorePromotionCount: 1,
      studentPromotionCount: 1,
      installmentNeedCount: 2,
      successfulInstallmentCount: 1,
      extendedInsuranceQuantity: 1,
      laptopQuantity: 2,
      pcQuantity: 1,
      assembledPcQuantity: 1,
      appleQuantity: 1,
      monitorQuantity: 3,
      printerQuantity: 1,
      accessoriesQuantity: 4,
      coverageRate: 50,
      conversionRate: 100,
      consultedSolutionRate: 50,
      experiencedRate: 50,
      zaloRate: 50,
      appDownloadRate: 50,
      salesAvailable: true,
      financeAvailable: true,
      totalTransferredAmount: 42000000,
      totalStatements: 5,
      totalStatementsTracked: 3,
      totalStatementsUnfollowed: 2,
      totalStatementsWithOrder: 2,
      totalStatementsWithoutOrder: 1,
      statementOrderRate: 66.67,
    });

    expect(salesReports.describeHomeSummaryScope).toHaveBeenCalledWith(
      { id: 'user-1', email: 'staff@phongvu.vn' },
      'AUTO',
      null,
      { allowOwnScope: true },
    );
    expect(prisma.homeSummaryReportFact.upsert).toHaveBeenCalledTimes(2);
    expect(prisma.homeSummaryReportFact.count).toHaveBeenCalledWith({
      where: expect.objectContaining({ reportType: 'NOT_PURCHASED' }),
    });
    expect(prisma.homeSummaryOrderFact.upsert).toHaveBeenCalledTimes(2);
    const syncOrderCacheQuery =
      prisma.salesReportErpOrderCache.findMany.mock.calls.find(
        ([args]: any[]) => args.select?.orderCreatedAt,
      )?.[0];
    expect(syncOrderCacheQuery?.where).toEqual({
      excludedAt: null,
      orderCreatedAt: {
        gte: expect.any(Date),
        lt: expect.any(Date),
      },
    });
    expect(JSON.stringify(syncOrderCacheQuery?.where)).not.toContain(
      'fetchedAt',
    );
    expect(prisma.salesReportErpOrderCache.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        select: expect.objectContaining({
          lifecycleStatus: true,
          grandTotal: true,
        }),
      }),
    );
    expect(
      prisma.salesReportErpOrderCache.findMany.mock.calls.some(
        ([args]: any[]) => args.select?.returnedAfterTaxAmount === true,
      ),
    ).toBe(false);
    expect(prisma.salesReport.count).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ consultedSolutionAnswer: 'YES' }),
      }),
    );
    expect(salesReports.summarizeSalesRevenueRows).toHaveBeenCalled();
    expect(prisma.mapVietinTransaction.aggregate).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          AND: expect.arrayContaining([
            {
              orders: { hasSome: ['2607040001', '2607040002'] },
            },
          ]),
        }),
      }),
    );
    const financeCountWheres = prisma.mapVietinTransaction.count.mock.calls.map(
      ([args]: any[]) => JSON.stringify(args.where),
    );
    expect(financeCountWheres[0]).not.toContain('orderTrackingStatus');
    expect(financeCountWheres.slice(1)).toEqual(
      expect.arrayContaining([
        expect.stringContaining('"orderTrackingStatus":"FOLLOWING"'),
        expect.stringContaining('"orderTrackingStatus":"UNFOLLOWED"'),
      ]),
    );
    expect(financeCountWheres.slice(3)).toEqual(
      expect.arrayContaining([
        expect.stringContaining('"isEmpty":false'),
        expect.stringContaining('"isEmpty":true'),
      ]),
    );
    expect(
      financeCountWheres
        .slice(3)
        .every((where: string) =>
          where.includes('"orderTrackingStatus":"FOLLOWING"'),
        ),
    ).toBe(true);
  });

  it('keeps pending-payment cache rows for reporting but excludes them from sales KPIs', async () => {
    const { service, prisma } = createHarness();
    const pendingOrder = {
      orderCode: '2607040003',
      orderCreatedAt: new Date('2026-07-04T06:00:00Z'),
      fetchedAt: new Date('2026-07-04T06:05:00Z'),
      storeCode: 'CP75',
      storeName: 'CP75',
      organizationNodeId: 'node-cp75',
      sourceUserId: 'user-1',
      sourceUserEmail: 'staff@phongvu.vn',
      consultantCustomId: 'PV001',
      consultantName: 'Staff',
      consultantEmail: 'staff@phongvu.vn',
      sellerId: 'PV001',
      sellerName: 'Staff',
      sellerEmail: 'staff@phongvu.vn',
      paymentStatus: 'PENDING_PAYMENT',
      grandTotal: 5000000,
    };
    const completedRevenueRow = {
      grandTotal: 12500000,
      paymentStatus: 'fully_paid',
      lifecycleStatus: 'COMPLETED',
      hasReturnedFullItems: false,
      returnedAfterTaxAmount: 0,
    };
    prisma.salesReportErpOrderCache.findMany.mockImplementation(
      ({ select }: any) =>
        Promise.resolve(
          select?.lifecycleStatus
            ? [
                completedRevenueRow,
                {
                  ...completedRevenueRow,
                  grandTotal: pendingOrder.grandTotal,
                  paymentStatus: pendingOrder.paymentStatus,
                  lifecycleStatus: 'PENDING',
                },
              ]
            : [
                pendingOrder,
                {
                  ...pendingOrder,
                  orderCode: '2607040001',
                  paymentStatus: 'fully_paid',
                  grandTotal: completedRevenueRow.grandTotal,
                },
              ],
        ),
    );
    prisma.homeSummaryOrderFact.count.mockReset();
    prisma.homeSummaryOrderFact.count.mockImplementation(({ where }: any) =>
      Promise.resolve(
        JSON.stringify(where).includes('isPaymentPending') ? 1 : 2,
      ),
    );

    const result = await service.getSummary(
      { id: 'user-1', email: 'staff@phongvu.vn' },
      { date: '2026-07-04' },
    );

    expect(result.totalRevenue).toBe(12500000);
    expect(result.totalOrders).toBe(1);
    expect(prisma.homeSummaryOrderFact.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({
          orderCode: pendingOrder.orderCode,
          isPaymentPending: true,
        }),
      }),
    );
    expect(prisma.salesReportErpOrderCache.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ excludedAt: null }),
      }),
    );
  });

  it('reads complete projection freshness without rebuilding facts in GET', async () => {
    const previousProjectionFlag = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    const previousFallbackFlag =
      process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
    process.env.HOME_SUMMARY_PROJECTION_ENABLED = 'true';
    process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED = 'false';
    try {
      const { service, prisma } = createHarness();
      prisma.homeSummaryProjectionState.findMany.mockResolvedValue([
        {
          summaryDate: new Date('2026-07-04T00:00:00.000Z'),
          status: 'COMPLETE',
          projectionVersion: BigInt(42),
          salesStatus: 'COMPLETE',
          salesProjectionVersion: BigInt(42),
          salesGeneratedAt: new Date('2026-07-04T03:00:04.000Z'),
          financeStatus: 'COMPLETE',
          financeProjectionVersion: BigInt(41),
          financeGeneratedAt: new Date('2026-07-04T03:00:04.000Z'),
          sourceUpdatedAt: new Date('2026-07-04T03:00:00.000Z'),
          salesReportSourceUpdatedAt: new Date('2026-07-04T03:00:00.000Z'),
          erpOrderCacheSourceUpdatedAt: new Date('2026-07-04T02:59:59.000Z'),
          mapVietinSourceUpdatedAt: null,
          generatedAt: new Date('2026-07-04T03:00:04.000Z'),
        },
      ]);

      const response = await service.getSummary(
        { id: 'user-1', email: 'staff@phongvu.vn' },
        { date: '2026-07-04' },
      );

      expect(response.freshness).toMatchObject({
        projectionVersion: 42,
        projectionLagSeconds: 4,
        isStale: false,
      });
      expect(response.freshness?.sourceUpdatedAtBySource).toEqual(
        expect.objectContaining({
          SALES_REPORT: new Date('2026-07-04T03:00:00.000Z'),
          ERP_ORDER_CACHE: new Date('2026-07-04T02:59:59.000Z'),
        }),
      );
      expect(response).not.toHaveProperty('dailySeries');
      expect(prisma.homeSummaryReportFact.upsert).not.toHaveBeenCalled();
      expect(prisma.homeSummaryOrderFact.upsert).not.toHaveBeenCalled();
    } finally {
      if (previousProjectionFlag === undefined) {
        delete process.env.HOME_SUMMARY_PROJECTION_ENABLED;
      } else {
        process.env.HOME_SUMMARY_PROJECTION_ENABLED = previousProjectionFlag;
      }
      if (previousFallbackFlag === undefined) {
        delete process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
      } else {
        process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED =
          previousFallbackFlag;
      }
    }
  });

  it('returns an ascending zero-filled daily series from one scoped SALES projection query', async () => {
    const previousProjectionFlag = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    const previousFallbackFlag =
      process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
    process.env.HOME_SUMMARY_PROJECTION_ENABLED = 'true';
    process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED = 'false';
    try {
      const { service, prisma, salesReports, featureService } = createHarness();
      featureService.canAccessFeature.mockImplementation(
        (_user: any, featureCode: string) =>
          featureCode === 'HOME_DASHBOARD_SALES',
      );
      salesReports.describeHomeSummaryScope.mockResolvedValue({
        available: true,
        scope: 'MANAGED_SCOPE',
        scopeLabel: 'Phạm vi quản lý',
        scopeDetail: 'Hai cửa hàng',
        unavailableMessage: null,
        ownUserId: null,
        ownEmail: null,
        ownPersonnelCode: null,
        allowedStoreCodes: ['CP75', 'CP62'],
      });
      prisma.homeSummaryProjectionState.findMany.mockResolvedValue(
        completeProjectionStates(['2026-07-04', '2026-07-05', '2026-07-06']),
      );
      prisma.homeSummaryDailyAggregate.findMany.mockResolvedValue([
        {
          summaryDate: new Date('2026-07-04T00:00:00.000Z'),
          totalOrders: 2,
          reportedOrders: 1,
          totalReports: 3,
          notPurchasedReports: 1,
          metrics: { totalRevenue: 12_000_000 },
        },
        {
          summaryDate: new Date('2026-07-04T00:00:00.000Z'),
          totalOrders: 1,
          reportedOrders: 1,
          totalReports: 1,
          notPurchasedReports: 0,
          metrics: { totalRevenue: 4_000_000 },
        },
        {
          summaryDate: new Date('2026-07-06T00:00:00.000Z'),
          totalOrders: 3,
          reportedOrders: 2,
          totalReports: 4,
          notPurchasedReports: 1,
          metrics: { totalRevenue: 9_000_000 },
        },
      ]);

      const response = await service.getSummary(
        { id: 'manager-1', email: 'manager@phongvu.vn' },
        {
          startDate: '2026-07-04',
          endDate: '2026-07-06',
          includeDailySeries: 'true',
        },
      );

      expect(response.dailySeries).toEqual([
        {
          date: '2026-07-04',
          totalRevenue: 16_000_000,
          totalOrders: 3,
          reportedOrders: 2,
          totalReports: 4,
        },
        {
          date: '2026-07-05',
          totalRevenue: 0,
          totalOrders: 0,
          reportedOrders: 0,
          totalReports: 0,
        },
        {
          date: '2026-07-06',
          totalRevenue: 9_000_000,
          totalOrders: 3,
          reportedOrders: 2,
          totalReports: 4,
        },
      ]);
      expect(
        response.dailySeries!.reduce(
          (sum, point) => sum + point.totalRevenue,
          0,
        ),
      ).toBe(response.totalRevenue);
      expect(
        response.dailySeries!.reduce(
          (sum, point) => sum + point.totalOrders,
          0,
        ),
      ).toBe(response.totalOrders);
      expect(
        response.dailySeries!.reduce(
          (sum, point) => sum + point.reportedOrders,
          0,
        ),
      ).toBe(response.reportedOrders);
      expect(
        response.dailySeries!.reduce(
          (sum, point) => sum + point.totalReports,
          0,
        ),
      ).toBe(response.totalReports);
      expect(prisma.homeSummaryDailyAggregate.findMany).toHaveBeenCalledTimes(
        1,
      );
      expect(prisma.homeSummaryDailyAggregate.findMany).toHaveBeenCalledWith({
        where: expect.objectContaining({
          projectionKind: 'SALES',
          dimensionType: 'STORE',
          storeCode: { in: ['CP75', 'CP62'] },
        }),
        select: expect.objectContaining({ summaryDate: true }),
      });
    } finally {
      if (previousProjectionFlag === undefined) {
        delete process.env.HOME_SUMMARY_PROJECTION_ENABLED;
      } else {
        process.env.HOME_SUMMARY_PROJECTION_ENABLED = previousProjectionFlag;
      }
      if (previousFallbackFlag === undefined) {
        delete process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
      } else {
        process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED =
          previousFallbackFlag;
      }
    }
  });

  it('uses an authorized selected SA scope for the opted-in SALES series while FINANCE keeps the dashboard scope', async () => {
    const previousProjectionFlag = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    process.env.HOME_SUMMARY_PROJECTION_ENABLED = 'true';
    try {
      const { service, prisma, salesReports } = createHarness();
      salesReports.describeHomeSummaryScope.mockResolvedValue({
        available: true,
        scope: 'MANAGED_SCOPE',
        scopeLabel: 'Showroom: CP75',
        scopeDetail: 'CP75',
        unavailableMessage: null,
        ownUserId: null,
        ownEmail: null,
        ownPersonnelCode: null,
        allowedStoreCodes: ['CP75'],
      });
      prisma.homeSummaryProjectionState.findMany.mockResolvedValue(
        completeProjectionStates(['2026-07-04']),
      );
      prisma.user.findMany.mockResolvedValue([
        salesAssignee('sa-2', 'SA2@PhongVu.vn', 'CP75'),
        salesAssignee('sa-99', 'sa99@phongvu.vn', 'CP99'),
      ]);
      prisma.homeSummaryDailyAggregate.findMany.mockResolvedValue([]);

      const response = await service.getSummary(
        { id: 'manager-1', email: 'manager@phongvu.vn' },
        {
          date: '2026-07-04',
          scope: 'MANAGED_SCOPE',
          organizationNodeId: 'node-cp75',
          salesProgressUserId: 'sa-2',
          includeDailySeries: 'true',
        },
      );

      expect(response.selectedSalesProgressUserId).toBe('sa-2');
      expect(response.dailySeries).toEqual([
        {
          date: '2026-07-04',
          totalRevenue: 0,
          totalOrders: 0,
          reportedOrders: 0,
          totalReports: 0,
        },
      ]);
      expect(prisma.homeSummaryDailyAggregate.findMany).toHaveBeenCalledTimes(
        2,
      );
      expect(prisma.homeSummaryDailyAggregate.findMany).toHaveBeenNthCalledWith(
        1,
        expect.objectContaining({
          where: expect.objectContaining({
            projectionKind: 'SALES',
            dimensionType: 'USER_STORE',
            dimensionKey: 'sa2@phongvu.vn',
            storeCode: { in: ['CP75'] },
          }),
        }),
      );
      expect(prisma.homeSummaryDailyAggregate.findMany).toHaveBeenNthCalledWith(
        2,
        expect.objectContaining({
          where: expect.objectContaining({
            projectionKind: 'FINANCE',
            dimensionType: 'STORE',
            storeCode: { in: ['CP75'] },
          }),
        }),
      );
      expect(
        JSON.stringify(prisma.homeSummaryDailyAggregate.findMany.mock.calls),
      ).not.toContain('CP99');
    } finally {
      if (previousProjectionFlag === undefined) {
        delete process.env.HOME_SUMMARY_PROJECTION_ENABLED;
      } else {
        process.env.HOME_SUMMARY_PROJECTION_ENABLED = previousProjectionFlag;
      }
    }
  });

  it('falls back to the authorized dashboard scope when an opted-in selected SA is outside that scope', async () => {
    const previousProjectionFlag = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    process.env.HOME_SUMMARY_PROJECTION_ENABLED = 'true';
    try {
      const { service, prisma, salesReports } = createHarness();
      salesReports.describeHomeSummaryScope.mockResolvedValue({
        available: true,
        scope: 'MANAGED_SCOPE',
        scopeLabel: 'Showroom: CP75',
        scopeDetail: 'CP75',
        unavailableMessage: null,
        ownUserId: null,
        ownEmail: null,
        ownPersonnelCode: null,
        allowedStoreCodes: ['CP75'],
      });
      prisma.homeSummaryProjectionState.findMany.mockResolvedValue(
        completeProjectionStates(['2026-07-04']),
      );
      prisma.user.findMany.mockResolvedValue([
        salesAssignee('sa-2', 'sa2@phongvu.vn', 'CP75'),
        salesAssignee('sa-99', 'sa99@phongvu.vn', 'CP99'),
      ]);
      prisma.homeSummaryDailyAggregate.findMany.mockResolvedValue([]);

      const response = await service.getSummary(
        { id: 'manager-1', email: 'manager@phongvu.vn' },
        {
          date: '2026-07-04',
          scope: 'MANAGED_SCOPE',
          organizationNodeId: 'node-cp75',
          salesProgressUserId: 'sa-99',
          includeDailySeries: 'true',
        },
      );

      expect(response.selectedSalesProgressUserId).toBeNull();
      expect(prisma.homeSummaryDailyAggregate.findMany).toHaveBeenNthCalledWith(
        1,
        expect.objectContaining({
          where: expect.objectContaining({
            projectionKind: 'SALES',
            dimensionType: 'STORE',
            storeCode: { in: ['CP75'] },
          }),
        }),
      );
      expect(
        JSON.stringify(prisma.homeSummaryDailyAggregate.findMany.mock.calls),
      ).not.toContain('CP99');
    } finally {
      if (previousProjectionFlag === undefined) {
        delete process.env.HOME_SUMMARY_PROJECTION_ENABLED;
      } else {
        process.env.HOME_SUMMARY_PROJECTION_ENABLED = previousProjectionFlag;
      }
    }
  });

  it.each([
    {
      name: 'ALL',
      scope: {
        available: true,
        scope: 'ALL',
        scopeLabel: 'Toàn hệ thống',
        scopeDetail: null,
        unavailableMessage: null,
        ownUserId: null,
        ownEmail: null,
        ownPersonnelCode: null,
        allowedStoreCodes: [],
      },
      expectedWhere: {
        dimensionType: 'GLOBAL',
        dimensionKey: '',
        storeCode: '',
      },
    },
    {
      name: 'OWN or selected SA',
      scope: {
        available: true,
        scope: 'OWN',
        scopeLabel: 'Phạm vi cá nhân',
        scopeDetail: 'CP75',
        unavailableMessage: null,
        ownUserId: 'sa-2',
        ownEmail: 'sa2@phongvu.vn',
        ownPersonnelCode: null,
        allowedStoreCodes: ['CP75'],
      },
      expectedWhere: {
        dimensionType: 'USER_STORE',
        dimensionKey: 'sa2@phongvu.vn',
        storeCode: { in: ['CP75'] },
      },
    },
  ])('reuses the $name projection scope for daily points', async (testCase) => {
    const { service, prisma } = createHarness();
    const range = (service as any).parseSummaryRange({
      startDate: '2026-07-04',
      endDate: '2026-07-05',
    });

    await (service as any).loadProjectionMetrics(
      range,
      testCase.scope,
      'SALES',
      true,
    );

    expect(prisma.homeSummaryDailyAggregate.findMany).toHaveBeenCalledTimes(1);
    expect(prisma.homeSummaryDailyAggregate.findMany).toHaveBeenCalledWith({
      where: expect.objectContaining(testCase.expectedWhere),
      select: expect.objectContaining({ summaryDate: true }),
    });
  });

  it.each([1, 7, 30, 90])(
    'returns exactly %i ascending zero-filled daily points',
    async (days) => {
      const { service, prisma } = createHarness();
      const startDate = '2026-01-01';
      const endDate = new Date(Date.UTC(2026, 0, days))
        .toISOString()
        .slice(0, 10);
      const range = (service as any).parseSummaryRange({
        startDate,
        endDate,
      });
      const scope = {
        available: true,
        scope: 'ALL',
        scopeLabel: 'Toàn hệ thống',
        scopeDetail: null,
        unavailableMessage: null,
        ownUserId: null,
        ownEmail: null,
        ownPersonnelCode: null,
        allowedStoreCodes: [],
      };

      const result = await (service as any).loadProjectionMetrics(
        range,
        scope,
        'SALES',
        true,
      );

      expect(result.dailySeries).toHaveLength(days);
      expect(result.dailySeries[0]).toMatchObject({ date: startDate });
      expect(result.dailySeries.at(-1)).toMatchObject({ date: endDate });
      expect(
        result.dailySeries.every(
          (point: any) =>
            point.totalRevenue === 0 &&
            point.totalOrders === 0 &&
            point.reportedOrders === 0 &&
            point.totalReports === 0,
        ),
      ).toBe(true);
      expect(prisma.homeSummaryDailyAggregate.findMany).toHaveBeenCalledTimes(
        1,
      );
    },
  );

  it('rejects an opted-in daily range above 90 days before querying projection rows', async () => {
    const { service, prisma } = createHarness();

    await expect(
      service.getSummary(
        { id: 'user-1', email: 'staff@phongvu.vn' },
        {
          startDate: '2026-04-01',
          endDate: '2026-06-30',
          includeDailySeries: 'true',
        },
      ),
    ).rejects.toThrow(
      'Chuỗi dữ liệu theo ngày chỉ hỗ trợ tối đa 90 ngày. Vui lòng chọn khoảng ngắn hơn.',
    );
    expect(prisma.homeSummaryDailyAggregate.findMany).not.toHaveBeenCalled();
  });

  it('omits the daily series when the sales section is unavailable', async () => {
    const previousProjectionFlag = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    process.env.HOME_SUMMARY_PROJECTION_ENABLED = 'true';
    try {
      const { service, prisma, featureService } = createHarness();
      featureService.canAccessFeature.mockImplementation(
        (_user: any, featureCode: string) =>
          featureCode === 'HOME_DASHBOARD_FINANCE',
      );
      prisma.homeSummaryProjectionState.findMany.mockResolvedValue(
        completeProjectionStates(['2026-07-04']),
      );

      const response = await service.getSummary(
        { id: 'finance-1', email: 'finance@phongvu.vn' },
        { date: '2026-07-04', includeDailySeries: 'true' },
      );

      expect(response.salesAvailable).toBe(false);
      expect(response).not.toHaveProperty('dailySeries');
      expect(prisma.homeSummaryDailyAggregate.findMany).toHaveBeenCalledTimes(
        1,
      );
      expect(prisma.homeSummaryDailyAggregate.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ projectionKind: 'FINANCE' }),
        }),
      );
    } finally {
      if (previousProjectionFlag === undefined) {
        delete process.env.HOME_SUMMARY_PROJECTION_ENABLED;
      } else {
        process.env.HOME_SUMMARY_PROJECTION_ENABLED = previousProjectionFlag;
      }
    }
  });

  it('preserves finance-only legacy fallback when the daily flag is present', async () => {
    const previousProjectionFlag = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    process.env.HOME_SUMMARY_PROJECTION_ENABLED = 'false';
    try {
      const { service, prisma, featureService } = createHarness();
      featureService.canAccessFeature.mockImplementation(
        (_user: any, featureCode: string) =>
          featureCode === 'HOME_DASHBOARD_FINANCE',
      );

      const response = await service.getSummary(
        { id: 'finance-1', email: 'finance@phongvu.vn' },
        { date: '2026-07-04', includeDailySeries: 'true' },
      );

      expect(response.salesAvailable).toBe(false);
      expect(response.financeAvailable).toBe(true);
      expect(response).not.toHaveProperty('dailySeries');
      expect(prisma.homeSummaryDailyAggregate.findMany).not.toHaveBeenCalled();
    } finally {
      if (previousProjectionFlag === undefined) {
        delete process.env.HOME_SUMMARY_PROJECTION_ENABLED;
      } else {
        process.env.HOME_SUMMARY_PROJECTION_ENABLED = previousProjectionFlag;
      }
    }
  });

  it('uses the legacy read path after projection fallback is activated', async () => {
    const previousProjectionFlag = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    const previousFallbackFlag =
      process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
    process.env.HOME_SUMMARY_PROJECTION_ENABLED = 'true';
    process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED = 'true';
    try {
      const { service, prisma } = createHarness();

      const response = await service.getSummary(
        { id: 'user-1', email: 'staff@phongvu.vn' },
        { date: '2026-07-04' },
      );

      expect(response.freshness).toBeNull();
      expect(response.totalRevenue).toBe(17500000);
      expect(prisma.homeSummaryReportFact.upsert).toHaveBeenCalled();
      expect(prisma.homeSummaryOrderFact.upsert).toHaveBeenCalled();
      expect(prisma.homeSummaryDailyAggregate.findMany).not.toHaveBeenCalled();
    } finally {
      if (previousProjectionFlag === undefined) {
        delete process.env.HOME_SUMMARY_PROJECTION_ENABLED;
      } else {
        process.env.HOME_SUMMARY_PROJECTION_ENABLED = previousProjectionFlag;
      }
      if (previousFallbackFlag === undefined) {
        delete process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
      } else {
        process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED =
          previousFallbackFlag;
      }
    }
  });

  it('serves the last complete snapshot as stale when a pending source watermark is older than 15 seconds', async () => {
    const previousProjectionFlag = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    const previousFallbackFlag =
      process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
    process.env.HOME_SUMMARY_PROJECTION_ENABLED = 'true';
    process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED = 'false';
    try {
      const { service, prisma } = createHarness();
      const sourceUpdatedAt = new Date(Date.now() - 20_000);
      const generatedAt = new Date(sourceUpdatedAt.getTime() - 1_000);
      prisma.homeSummaryProjectionState.findMany.mockResolvedValue([
        {
          summaryDate: new Date('2026-07-04T00:00:00.000Z'),
          status: 'PENDING',
          projectionVersion: 42n,
          salesStatus: 'PENDING',
          salesProjectionVersion: 42n,
          salesGeneratedAt: generatedAt,
          financeStatus: 'COMPLETE',
          financeProjectionVersion: 41n,
          financeGeneratedAt: generatedAt,
          sourceUpdatedAt,
          salesReportSourceUpdatedAt: sourceUpdatedAt,
          erpOrderCacheSourceUpdatedAt: null,
          mapVietinSourceUpdatedAt: generatedAt,
          generatedAt,
        },
      ]);

      const response = await service.getSummary(
        { id: 'user-1', email: 'staff@phongvu.vn' },
        { date: '2026-07-04' },
      );

      expect(response.freshness).toMatchObject({
        projectionVersion: 42,
        isStale: true,
      });
      expect(response.freshness!.projectionLagSeconds).toBeGreaterThanOrEqual(
        20,
      );
      expect(prisma.homeSummaryReportFact.upsert).not.toHaveBeenCalled();
      expect(prisma.homeSummaryOrderFact.upsert).not.toHaveBeenCalled();
    } finally {
      if (previousProjectionFlag === undefined) {
        delete process.env.HOME_SUMMARY_PROJECTION_ENABLED;
      } else {
        process.env.HOME_SUMMARY_PROJECTION_ENABLED = previousProjectionFlag;
      }
      if (previousFallbackFlag === undefined) {
        delete process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
      } else {
        process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED =
          previousFallbackFlag;
      }
    }
  });

  it('does not mark SALES stale because an unchanged FINANCE snapshot is older', async () => {
    const previousProjectionFlag = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    const previousFallbackFlag =
      process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
    process.env.HOME_SUMMARY_PROJECTION_ENABLED = 'true';
    process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED = 'false';
    try {
      const { service, prisma } = createHarness();
      const salesSourceUpdatedAt = new Date(Date.now() - 20_000);
      const salesGeneratedAt = new Date(salesSourceUpdatedAt.getTime() + 1_000);
      const financeGeneratedAt = new Date(Date.now() - 60 * 60 * 1000);
      prisma.homeSummaryProjectionState.findMany.mockResolvedValue([
        {
          summaryDate: new Date('2026-07-04T00:00:00.000Z'),
          status: 'COMPLETE',
          projectionVersion: 42n,
          salesStatus: 'COMPLETE',
          salesProjectionVersion: 42n,
          salesGeneratedAt,
          financeStatus: 'COMPLETE',
          financeProjectionVersion: 41n,
          financeGeneratedAt,
          sourceUpdatedAt: salesSourceUpdatedAt,
          salesReportSourceUpdatedAt: salesSourceUpdatedAt,
          erpOrderCacheSourceUpdatedAt: null,
          mapVietinSourceUpdatedAt: new Date(
            financeGeneratedAt.getTime() - 1_000,
          ),
          generatedAt: financeGeneratedAt,
        },
      ]);

      const response = await service.getSummary(
        { id: 'user-1', email: 'staff@phongvu.vn' },
        { date: '2026-07-04' },
      );

      expect(response.freshness).toMatchObject({
        projectionVersion: 42,
        isStale: false,
      });
      expect(response.freshness!.projectionLagSeconds).toBeLessThan(15);
    } finally {
      if (previousProjectionFlag === undefined) {
        delete process.env.HOME_SUMMARY_PROJECTION_ENABLED;
      } else {
        process.env.HOME_SUMMARY_PROJECTION_ENABLED = previousProjectionFlag;
      }
      if (previousFallbackFlag === undefined) {
        delete process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
      } else {
        process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED =
          previousFallbackFlag;
      }
    }
  });

  it('returns Vietnamese 503 when no complete projection exists', async () => {
    const previousProjectionFlag = process.env.HOME_SUMMARY_PROJECTION_ENABLED;
    const previousFallbackFlag =
      process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
    process.env.HOME_SUMMARY_PROJECTION_ENABLED = 'true';
    process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED = 'false';
    try {
      const { service } = createHarness();
      await expect(
        service.getSummary(
          { id: 'user-1', email: 'staff@phongvu.vn' },
          { date: '2026-07-04' },
        ),
      ).rejects.toThrow(
        'Dữ liệu Trang chủ đang được chuẩn bị. Vui lòng thử lại sau ít phút.',
      );
    } finally {
      if (previousProjectionFlag === undefined) {
        delete process.env.HOME_SUMMARY_PROJECTION_ENABLED;
      } else {
        process.env.HOME_SUMMARY_PROJECTION_ENABLED = previousProjectionFlag;
      }
      if (previousFallbackFlag === undefined) {
        delete process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED;
      } else {
        process.env.HOME_SUMMARY_LEGACY_SYNC_FALLBACK_ENABLED =
          previousFallbackFlag;
      }
    }
  });

  it('returns behavior detail rows for home dashboard cards', async () => {
    const { service, prisma } = createHarness();
    prisma.homeSummaryReportFact.findMany
      .mockResolvedValueOnce([{ orderCode: '2607040001' }])
      .mockResolvedValueOnce([{ salesReportId: 'report-2' }]);
    prisma.homeSummaryOrderFact.count.mockReset();
    prisma.homeSummaryOrderFact.count.mockResolvedValue(1);
    prisma.homeSummaryOrderFact.findMany.mockResolvedValue([
      {
        orderCode: '2607040002',
        grandTotal: 5000000,
        orderCreatedAt: new Date('2026-07-04T05:00:00Z'),
        fetchedAt: new Date('2026-07-04T05:10:00Z'),
        storeCode: 'CP62',
        consultantName: 'SA Hai',
        consultantEmail: 'sa2@phongvu.vn',
        sellerName: null,
        sellerEmail: null,
        sourceUserEmail: 'sa2@phongvu.vn',
      },
    ]);
    prisma.user.findMany.mockResolvedValueOnce([
      {
        email: 'sa2@phongvu.vn',
        firstName: 'Nhân viên',
        lastName: 'Kho',
        jobRoleCode: 'WAREHOUSE_STAFF',
        jobRole: null,
        store: { storeId: 'CP62' },
        organizationNode: null,
        organizationAssignments: [],
      },
    ]);
    prisma.salesReport.count.mockResolvedValueOnce(2);
    prisma.salesReport.findMany
      .mockResolvedValueOnce([
        {
          id: 'report-3',
          submittedAt: new Date('2026-07-04T04:00:00Z'),
          storeCode: 'CP75',
          createdByName: 'SA Ba',
          createdByEmail: 'sa3@phongvu.vn',
          orderCode: '2607040003',
          erpOrderId: null,
          erpPaymentMethods: [],
          installmentStatus: 'SUCCESS',
          installmentFailureReason: null,
          installmentNoInstallmentReason: 'NORMAL_INSTALLMENT',
          installmentPartnerCodes: ['MIRAE_ASSET'],
        },
        {
          id: 'report-4',
          submittedAt: new Date('2026-07-04T04:30:00Z'),
          storeCode: 'CP62',
          createdByName: 'SA Bốn',
          createdByEmail: 'sa4@phongvu.vn',
          orderCode: null,
          erpOrderId: null,
          erpPaymentMethods: ['INSTALLMENT'],
          installmentStatus: 'FAILED',
          installmentFailureReason: null,
          installmentNoInstallmentReason: 'HIGH_INTEREST_OR_FEE',
          installmentPartnerCodes: ['MPOS'],
        },
      ])
      .mockResolvedValueOnce([
        {
          id: 'report-2',
          submittedAt: new Date('2026-07-04T03:00:00Z'),
          storeCode: 'CP75',
          createdByName: 'SA Một',
          createdByEmail: 'sa1@phongvu.vn',
          customerName: 'Nguyễn Văn A',
          customerType: 'BUSINESS',
          categoryGroupName: 'Computer components',
          categoryGroupNameVi: 'Linh kiện máy tính',
          notPurchasedReason: 'OTHER',
          notPurchasedOtherReason: 'Chờ chương trình khuyến mãi',
        },
      ]);

    const result = await service.getBehaviorDetails(
      { id: 'manager-1', email: 'manager@phongvu.vn' },
      { startDate: '2026-07-04', endDate: '2026-07-04', limit: 50 },
    );

    expect(result).toMatchObject({
      startDate: '2026-07-04',
      endDate: '2026-07-04',
      limit: 50,
      notPurchasedTotal: 1,
      unreportedTotal: 1,
      installmentNeedTotal: 2,
      notPurchasedReports: [
        {
          storeCode: 'CP75',
          salesName: 'SA Một',
          customerName: 'Nguyễn Văn A',
          customerTypeLabel: 'Doanh nghiệp',
          categoryName: 'Linh kiện máy tính',
          notPurchasedReasonLabel: 'Khác: Chờ chương trình khuyến mãi',
        },
      ],
      unreportedOrders: [
        {
          orderCode: '2607040002',
          grandTotal: 5000000,
          storeCode: 'CP62',
          salesName: 'Nhân viên Kho',
          soldAt: new Date('2026-07-04T05:00:00Z'),
        },
      ],
      installmentNeedReports: [
        {
          storeCode: 'CP75',
          salesName: 'SA Ba',
          orderCode: '2607040003',
          installmentPartnerLabels: ['Mirae Asset'],
          successful: true,
          note: '2607040003',
        },
        {
          storeCode: 'CP62',
          salesName: 'SA Bốn',
          orderCode: null,
          installmentPartnerLabels: ['MPOS'],
          successful: false,
          note: 'Khách từ chối: Lãi suất/Phí trả góp cao',
        },
      ],
    });
    expect(prisma.homeSummaryOrderFact.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          AND: expect.arrayContaining([
            expect.any(Object),
            { orderCode: { notIn: ['2607040001'] } },
          ]),
        }),
        take: 50,
        select: expect.objectContaining({ storeCode: true }),
      }),
    );
    expect(prisma.salesReport.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: { in: ['report-2'] } },
        select: expect.objectContaining({ storeCode: true }),
      }),
    );
  });

  it('returns a bounded opaque cursor page from details v2', async () => {
    const { service, prisma } = createHarness();
    prisma.homeSummaryReportFact.count.mockReset();
    prisma.homeSummaryReportFact.count.mockResolvedValue(2);
    prisma.homeSummaryReportFact.findMany.mockReset();
    prisma.homeSummaryReportFact.findMany.mockResolvedValue([
      { salesReportId: 'report-2' },
      { salesReportId: 'report-3' },
    ]);
    prisma.salesReport.findMany.mockReset();
    prisma.salesReport.findMany.mockResolvedValue([
      {
        id: 'report-2',
        submittedAt: new Date('2026-07-04T03:00:00.000Z'),
        storeCode: 'CP75',
        createdByName: 'Nhân viên Một',
        createdByEmail: 'staff@phongvu.vn',
        customerName: 'Khách hàng A',
        customerType: 'PERSONAL',
        categoryGroupName: 'Laptop',
        categoryGroupNameVi: 'Laptop',
        notPurchasedReason: 'PRICE_HESITATION',
        notPurchasedOtherReason: null,
      },
    ]);

    const page = await service.getBehaviorDetailsV2(
      { id: 'user-1', email: 'staff@phongvu.vn' },
      {
        date: '2026-07-04',
        kind: 'NOT_PURCHASED',
        limit: 1,
      },
    );

    expect(page).toMatchObject({
      kind: 'NOT_PURCHASED',
      limit: 1,
      total: 2,
      items: [expect.objectContaining({ id: 'report-2' })],
      nextCursor: expect.any(String),
    });
    const decodedCursor = JSON.parse(
      Buffer.from(page.nextCursor!, 'base64url').toString('utf8'),
    );
    expect(decodedCursor).toEqual({
      v: 1,
      kind: 'NOT_PURCHASED',
      id: 'report-2',
    });
    expect(prisma.homeSummaryReportFact.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ take: 2, orderBy: { salesReportId: 'asc' } }),
    );
  });

  it('uses the visible DATE key and Vietnam UTC window when populating SALES metrics', async () => {
    const { service } = createHarness();
    const tx = {
      homeSummaryDailyAggregate: {
        findMany: jest.fn().mockResolvedValue([]),
        update: jest.fn(),
      },
      salesReport: { findMany: jest.fn().mockResolvedValue([]) },
      salesReportErpOrderCache: { findMany: jest.fn().mockResolvedValue([]) },
    };

    await service.populateSalesProjectionMetrics(tx as any, '2026-07-04');

    expect(tx.homeSummaryDailyAggregate.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          summaryDate: new Date('2026-07-04T00:00:00.000Z'),
          projectionKind: 'SALES',
        },
      }),
    );
    expect(tx.salesReport.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          erpExcludedAt: null,
          OR: expect.arrayContaining([
            expect.objectContaining({
              erpOrderCreatedAt: {
                gte: new Date('2026-07-03T17:00:00.000Z'),
                lt: new Date('2026-07-04T17:00:00.000Z'),
              },
            }),
          ]),
        }),
      }),
    );
  });

  it('populates projection revenue from full VAT-inclusive cache totals and versions the derived metrics', async () => {
    const { service, salesReports } = createHarness();
    const tx = {
      homeSummaryDailyAggregate: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'aggregate-global',
            dimensionType: 'GLOBAL',
            dimensionKey: '',
            storeCode: '',
            totalOrders: 2,
            reportedOrders: 2,
            totalReports: 2,
            notPurchasedReports: 0,
          },
        ]),
      },
      salesReport: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'report-partial',
            reportType: 'PURCHASED',
            orderCode: 'ORDER-PARTIAL',
            erpOrderId: 'capture-id',
            createdByEmail: 'staff@phongvu.vn',
            storeCode: 'CP75',
            erpLifecycleStatus: 'COMPLETED_PARTIAL_RETURN',
            customerType: 'BUSINESS',
            items: [{ categoryType: 'laptop', quantity: 1, rowTotal: 123 }],
          },
          {
            id: 'report-missing',
            reportType: 'PURCHASED',
            orderCode: 'ORDER-MISSING',
            erpOrderId: 'capture-id-2',
            createdByEmail: 'staff@phongvu.vn',
            storeCode: 'CP75',
            erpLifecycleStatus: 'COMPLETED',
            customerType: 'PERSONAL',
            items: [{ categoryType: 'monitor', quantity: 2, rowTotal: 456 }],
          },
        ]),
      },
      salesReportErpOrderCache: {
        findMany: jest.fn().mockResolvedValue([
          {
            orderCode: 'ORDER-PARTIAL',
            storeCode: 'CP75',
            sourceUserEmail: 'staff@phongvu.vn',
            consultantEmail: null,
            sellerEmail: null,
            grandTotal: 1080000,
            paymentStatus: 'PAID',
            lifecycleStatus: 'COMPLETED_PARTIAL_RETURN',
            hasReturnedFullItems: false,
            returnedAfterTaxAmount: 108000,
          },
        ]),
      },
      $executeRaw: jest.fn().mockResolvedValue(1),
    };

    await service.populateSalesProjectionMetrics(tx as any, '2026-07-04');

    const lookup = salesReports.summarizeSalesRevenueRows.mock.calls[0][1];
    expect(lookup.values.get('ORDER-PARTIAL')).toBe(1080000);
    expect(lookup.values.has('ORDER-MISSING')).toBe(false);
    const metricPayload = tx.$executeRaw.mock.calls[0][0].values.find(
      (value: unknown) =>
        typeof value === 'string' &&
        value.includes('salesPriceContractVersion'),
    );
    const updates = JSON.parse(metricPayload as string);
    expect(updates[0].metrics).toMatchObject({
      salesPriceContractVersion: 2,
      salesKpiContractVersion: 1,
      totalRevenue: 1080000,
      completedRevenue: 1080000,
      examScorePromotionCount: 1,
      studentPromotionCount: 1,
      installmentNeedCount: 2,
    });
  });

  it('loads report revenue by order code when the canonical cache date is outside the projection day', async () => {
    const { service, salesReports } = createHarness();
    const tx = {
      homeSummaryDailyAggregate: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'aggregate-global',
            dimensionType: 'GLOBAL',
            dimensionKey: '',
            storeCode: '',
            totalOrders: 0,
            reportedOrders: 0,
            totalReports: 1,
            notPurchasedReports: 0,
          },
        ]),
      },
      salesReport: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'report-cross-date',
            reportType: 'PURCHASED',
            orderCode: 'ORDER-CROSS-DATE',
            erpOrderId: 'detail-snapshot',
            createdByEmail: 'staff@phongvu.vn',
            storeCode: 'CP75',
            erpLifecycleStatus: 'COMPLETED',
            customerType: 'BUSINESS',
            items: [],
          },
        ]),
      },
      salesReportErpOrderCache: {
        findMany: jest
          .fn()
          .mockResolvedValueOnce([])
          .mockResolvedValueOnce([
            { orderCode: 'ORDER-CROSS-DATE', grandTotal: 2160000 },
          ]),
      },
      $executeRaw: jest.fn().mockResolvedValue(1),
    };

    await service.populateSalesProjectionMetrics(tx as any, '2026-07-04');

    const lookup = salesReports.summarizeSalesRevenueRows.mock.calls[0][1];
    expect(lookup.values.get('ORDER-CROSS-DATE')).toBe(2160000);
    expect(tx.salesReportErpOrderCache.findMany.mock.calls[1][0]).toEqual({
      where: {
        orderCode: { in: ['ORDER-CROSS-DATE'] },
        excludedAt: null,
      },
      select: { orderCode: true, grandTotal: true },
    });
    const metricPayload = tx.$executeRaw.mock.calls[0][0].values.find(
      (value: unknown) =>
        typeof value === 'string' &&
        value.includes('salesPriceContractVersion'),
    );
    const updates = JSON.parse(metricPayload as string);
    expect(updates[0].metrics).toMatchObject({
      completedRevenue: 2160000,
    });
  });

  it('uses the full canonical total for partial returns and fails invalid totals closed', () => {
    const { service } = createHarness();

    expect(
      (service as any).netCacheRevenue({
        grandTotal: 1080000,
        paymentStatus: 'PAID',
        lifecycleStatus: 'COMPLETED_PARTIAL_RETURN',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 108000,
      }),
    ).toBe(1080000);
    expect(
      (service as any).netCacheRevenue({
        grandTotal: null,
        paymentStatus: 'PAID',
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
      }),
    ).toBe(0);
  });

  it('does not present fetchedAt as the sold time for unreported orders', async () => {
    const { service, prisma } = createHarness();
    prisma.homeSummaryReportFact.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    prisma.homeSummaryReportFact.count.mockResolvedValue(0);
    prisma.homeSummaryOrderFact.count.mockReset();
    prisma.homeSummaryOrderFact.count.mockResolvedValue(1);
    prisma.homeSummaryOrderFact.findMany.mockResolvedValue([
      {
        orderCode: '26070337539840',
        orderCreatedAt: null,
        fetchedAt: new Date('2026-07-11T12:55:08Z'),
        storeCode: 'CP75',
        consultantName: 'Việt Nguyễn Quang',
        consultantEmail: 'viet.nq01@phongvu.vn',
        sellerName: null,
        sellerEmail: null,
        sourceUserEmail: null,
      },
    ]);
    prisma.user.findMany.mockResolvedValueOnce([]);
    prisma.salesReport.count.mockResolvedValue(0);
    prisma.salesReport.findMany.mockResolvedValue([]);

    const result = await service.getBehaviorDetails(
      { id: 'manager-1', email: 'manager@phongvu.vn' },
      { startDate: '2026-07-11', endDate: '2026-07-11', limit: 50 },
    );

    expect(result.unreportedOrders).toEqual([
      expect.objectContaining({
        orderCode: '26070337539840',
        grandTotal: null,
        soldAt: null,
        salesName: 'Việt Nguyễn Quang',
      }),
    ]);
  });

  it('calculates SA progress from completed reports instead of order cache revenue', async () => {
    const { service, prisma } = createHarness();
    prisma.salesReport.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        {
          erpOrderCreatedAt: new Date('2026-07-04T02:00:00Z'),
          submittedAt: new Date('2026-07-04T02:10:00Z'),
          orderCode: '2607040001',
        },
      ])
      .mockResolvedValueOnce([
        {
          erpOrderCreatedAt: new Date('2026-07-04T02:00:00Z'),
          submittedAt: new Date('2026-07-04T02:10:00Z'),
          orderCode: '2607040001',
        },
      ])
      .mockResolvedValueOnce([
        {
          erpOrderCreatedAt: new Date('2026-07-04T02:00:00Z'),
          submittedAt: new Date('2026-07-04T02:10:00Z'),
          orderCode: '2607040001',
        },
      ]);

    const result = await service.getSummary(
      { id: 'user-1', email: 'staff@phongvu.vn', jobRoleCode: 'SA' },
      { date: '2026-07-04' },
    );

    expect(result.totalRevenue).toBe(17500000);
    expect(result.completedRevenue).toBe(12500000);
    expect(result.salesProgress.day.actual).toBe(12500000);
    expect(result.salesProgress.day.actual).not.toBe(
      Math.round(result.totalRevenue / 1.08),
    );
    expect(prisma.salesReport.findMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        where: expect.objectContaining({
          AND: expect.arrayContaining([
            expect.objectContaining({
              erpLifecycleStatus: {
                in: ['COMPLETED', 'COMPLETED_PARTIAL_RETURN'],
              },
            }),
          ]),
        }),
      }),
    );
  });

  it('shares each SR monthly target across its active SA assignments', async () => {
    const { service, prisma } = createHarness();
    prisma.salesReport.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    prisma.store.findMany.mockResolvedValue([
      {
        storeId: 'CP01',
        organizationNodeId: 'node-cp01',
      },
      {
        storeId: 'CP02',
        organizationNodeId: 'node-cp02',
      },
    ]);
    prisma.salesTarget.findMany.mockResolvedValue([
      {
        organizationNodeId: 'node-cp01',
        targetBeforeTax: BigInt(300000000),
      },
      {
        organizationNodeId: 'node-cp02',
        targetBeforeTax: BigInt(310000000),
      },
    ]);
    prisma.user.findMany.mockResolvedValueOnce([
      {
        store: null,
        organizationNode: {
          id: 'sa-1',
          stores: [{ storeId: 'CP01' }, { storeId: 'CP02' }],
          children: [],
        },
        organizationAssignments: [],
      },
      {
        store: null,
        organizationNode: {
          id: 'sa-2',
          stores: [{ storeId: 'CP01' }],
          children: [],
        },
        organizationAssignments: [],
      },
    ]);

    const result = await service.getSummary(
      { id: 'user-1', email: 'staff@phongvu.vn', jobRoleCode: 'SA' },
      { date: '2026-07-04' },
    );

    expect(result.salesProgress).toMatchObject({
      status: 'AVAILABLE',
      scope: 'PERSONAL_SA',
      missingStoreCodes: [],
      day: { target: 16025806 },
      week: { target: 80129032 },
      month: { target: 496800000 },
    });
    expect(result.scopeSalesProgress).toMatchObject({
      status: 'AVAILABLE',
      scope: 'MANAGED',
      month: { target: 658800000 },
    });
  });

  it('lets a managed dashboard select an SA for personal sales progress', async () => {
    const { service, prisma, salesReports } = createHarness();
    salesReports.describeHomeSummaryScope.mockResolvedValueOnce({
      available: true,
      scope: 'MANAGED_SCOPE',
      scopeLabel: 'Showroom: CP75',
      scopeDetail: 'CP75',
      unavailableMessage: null,
      ownUserId: null,
      ownEmail: null,
      ownPersonnelCode: null,
      allowedStoreCodes: ['CP75'],
    });
    prisma.salesReport.findMany.mockResolvedValue([]);
    prisma.store.findMany.mockResolvedValue([
      {
        storeId: 'CP75',
        organizationNodeId: 'node-cp75',
      },
    ]);
    prisma.salesTarget.findMany.mockResolvedValue([
      {
        organizationNodeId: 'node-cp75',
        targetBeforeTax: BigInt(310000000),
      },
    ]);
    prisma.user.findMany.mockResolvedValue([
      {
        id: 'sa-1',
        email: 'sa1@phongvu.vn',
        firstName: 'SA',
        lastName: 'Một',
        jobRoleCode: 'SA',
        areaCode: 'HCM',
        regionCode: 'SOUTH',
        store: {
          storeId: 'CP75',
          storeName: 'CP75',
          area: {
            code: 'HCM',
            region: { code: 'SOUTH' },
          },
          organizationNode: null,
        },
        area: {
          code: 'HCM',
          region: { code: 'SOUTH' },
        },
        region: { code: 'SOUTH' },
        organizationNode: null,
        organizationAssignments: [],
      },
      {
        id: 'sa-2',
        email: 'sa2@phongvu.vn',
        firstName: 'SA',
        lastName: 'Hai',
        jobRoleCode: 'SA',
        areaCode: 'HCM',
        regionCode: 'SOUTH',
        store: {
          storeId: 'CP75',
          storeName: 'CP75',
          area: {
            code: 'HCM',
            region: { code: 'SOUTH' },
          },
          organizationNode: null,
        },
        area: {
          code: 'HCM',
          region: { code: 'SOUTH' },
        },
        region: { code: 'SOUTH' },
        organizationNode: null,
        organizationAssignments: [],
      },
    ]);

    const result = await service.getSummary(
      { id: 'manager-1', email: 'manager@phongvu.vn' },
      {
        date: '2026-07-04',
        scope: 'MANAGED_SCOPE',
        organizationNodeId: 'node-cp75',
        salesProgressUserId: 'sa-2',
      },
    );

    expect(result.salesProgressAssignees).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          userId: 'sa-1',
          label: 'SA Một',
          isSelected: false,
          storeCodes: ['CP75'],
        }),
        expect.objectContaining({
          userId: 'sa-2',
          label: 'SA Hai',
          isSelected: true,
          storeCodes: ['CP75'],
        }),
      ]),
    );
    expect(result.selectedSalesProgressUserId).toBe('sa-2');
    expect(result.salesProgress.scope).toBe('PERSONAL_SA');
    expect(result.personalSalesProgress.scope).toBe('PERSONAL_SA');
    expect(result.scopeSalesProgress.scope).toBe('MANAGED');
  });

  it('keeps managed sales KPIs on the dashboard scope until an SA is selected', async () => {
    const { service, prisma, salesReports } = createHarness();
    salesReports.describeHomeSummaryScope.mockResolvedValueOnce({
      available: true,
      scope: 'MANAGED_SCOPE',
      scopeLabel: 'Showroom: CP75',
      scopeDetail: 'CP75',
      unavailableMessage: null,
      ownUserId: null,
      ownEmail: null,
      ownPersonnelCode: null,
      allowedStoreCodes: ['CP75'],
    });
    prisma.salesReport.findMany.mockResolvedValue([]);
    prisma.store.findMany.mockResolvedValue([
      {
        storeId: 'CP75',
        organizationNodeId: 'node-cp75',
      },
    ]);
    prisma.salesTarget.findMany.mockResolvedValue([
      {
        organizationNodeId: 'node-cp75',
        targetBeforeTax: BigInt(310000000),
      },
    ]);
    prisma.user.findMany.mockResolvedValue([
      {
        id: 'sa-1',
        email: 'sa1@phongvu.vn',
        firstName: 'SA',
        lastName: 'Một',
        jobRoleCode: 'SA',
        areaCode: 'HCM',
        regionCode: 'SOUTH',
        store: {
          storeId: 'CP75',
          storeName: 'CP75',
          area: {
            code: 'HCM',
            region: { code: 'SOUTH' },
          },
          organizationNode: null,
        },
        area: {
          code: 'HCM',
          region: { code: 'SOUTH' },
        },
        region: { code: 'SOUTH' },
        organizationNode: null,
        organizationAssignments: [],
      },
    ]);

    const result = await service.getSummary(
      { id: 'manager-1', email: 'manager@phongvu.vn' },
      {
        date: '2026-07-04',
        scope: 'MANAGED_SCOPE',
        organizationNodeId: 'node-cp75',
      },
    );

    expect(result.selectedSalesProgressUserId).toBeNull();
    expect(result.personalSalesProgress.status).toBe('NOT_APPLICABLE');
    expect(result.salesProgressAssignees).toEqual([
      expect.objectContaining({
        userId: 'sa-1',
        isSelected: false,
        storeCodes: ['CP75'],
      }),
    ]);
    expect(prisma.homeSummaryOrderFact.count).toHaveBeenNthCalledWith(1, {
      where: expect.objectContaining({
        AND: expect.arrayContaining([{ storeCode: { in: ['CP75'] } }]),
      }),
    });
    expect(
      JSON.stringify(prisma.homeSummaryOrderFact.count.mock.calls[0][0].where),
    ).not.toContain('sa-1');
  });

  it('offers SA assignees on all-system scope without selecting one by default', async () => {
    const { service, prisma, salesReports } = createHarness();
    salesReports.describeHomeSummaryScope.mockResolvedValueOnce({
      available: true,
      scope: 'ALL',
      scopeLabel: 'Toàn hệ thống',
      scopeDetail: 'Tất cả showroom',
      unavailableMessage: null,
      ownUserId: null,
      ownEmail: null,
      ownPersonnelCode: null,
      allowedStoreCodes: [],
    });
    prisma.salesReport.findMany.mockResolvedValue([]);
    prisma.store.findMany.mockResolvedValue([
      {
        storeId: 'CP75',
        organizationNodeId: 'node-cp75',
      },
    ]);
    prisma.salesTarget.findMany.mockResolvedValue([
      {
        organizationNodeId: 'node-cp75',
        targetBeforeTax: BigInt(310000000),
      },
    ]);
    prisma.user.findMany.mockResolvedValue([
      {
        id: 'sa-1',
        email: 'sa1@phongvu.vn',
        firstName: 'SA',
        lastName: 'Một',
        jobRoleCode: 'SA',
        areaCode: 'HCM',
        regionCode: 'SOUTH',
        store: {
          storeId: 'CP75',
          storeName: 'CP75',
          area: {
            code: 'HCM',
            region: { code: 'SOUTH' },
          },
          organizationNode: null,
        },
        area: {
          code: 'HCM',
          region: { code: 'SOUTH' },
        },
        region: { code: 'SOUTH' },
        organizationNode: null,
        organizationAssignments: [],
      },
    ]);

    const result = await service.getSummary(
      { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
      {
        date: '2026-07-04',
        scope: 'ALL',
      },
    );

    expect(result.selectedSalesProgressUserId).toBeNull();
    expect(result.personalSalesProgress.status).toBe('NOT_APPLICABLE');
    expect(result.scopeSalesProgress.scope).toBe('ALL');
    expect(result.salesProgressAssignees).toEqual([
      expect.objectContaining({
        userId: 'sa-1',
        isSelected: false,
        storeCodes: ['CP75'],
      }),
    ]);
  });

  it('uses the selected SA for sales KPIs while finance stays on the dashboard scope', async () => {
    const { service, prisma, salesReports } = createHarness();
    salesReports.describeHomeSummaryScope.mockResolvedValueOnce({
      available: true,
      scope: 'MANAGED_SCOPE',
      scopeLabel: 'Showroom: CP75',
      scopeDetail: 'CP75',
      unavailableMessage: null,
      ownUserId: null,
      ownEmail: null,
      ownPersonnelCode: null,
      allowedStoreCodes: ['CP75'],
    });
    prisma.salesReport.findMany.mockResolvedValue([]);
    prisma.store.findMany.mockResolvedValue([
      {
        storeId: 'CP75',
        organizationNodeId: 'node-cp75',
      },
    ]);
    prisma.salesTarget.findMany.mockResolvedValue([
      {
        organizationNodeId: 'node-cp75',
        targetBeforeTax: BigInt(310000000),
      },
    ]);
    prisma.user.findMany.mockResolvedValue([
      {
        id: 'sa-1',
        email: 'sa1@phongvu.vn',
        firstName: 'SA',
        lastName: 'Một',
        jobRoleCode: 'SA',
        areaCode: 'HCM',
        regionCode: 'SOUTH',
        store: {
          storeId: 'CP75',
          storeName: 'CP75',
          area: {
            code: 'HCM',
            region: { code: 'SOUTH' },
          },
          organizationNode: null,
        },
        area: {
          code: 'HCM',
          region: { code: 'SOUTH' },
        },
        region: { code: 'SOUTH' },
        organizationNode: null,
        organizationAssignments: [],
      },
      {
        id: 'sa-2',
        email: 'sa2@phongvu.vn',
        firstName: 'SA',
        lastName: 'Hai',
        jobRoleCode: 'SA',
        areaCode: 'HCM',
        regionCode: 'SOUTH',
        store: {
          storeId: 'CP75',
          storeName: 'CP75',
          area: {
            code: 'HCM',
            region: { code: 'SOUTH' },
          },
          organizationNode: null,
        },
        area: {
          code: 'HCM',
          region: { code: 'SOUTH' },
        },
        region: { code: 'SOUTH' },
        organizationNode: null,
        organizationAssignments: [],
      },
    ]);

    const result = await service.getSummary(
      { id: 'manager-1', email: 'manager@phongvu.vn' },
      {
        date: '2026-07-04',
        scope: 'MANAGED_SCOPE',
        organizationNodeId: 'node-cp75',
        salesProgressUserId: 'sa-2',
      },
    );

    expect(result.selectedSalesProgressUserId).toBe('sa-2');
    expect(prisma.homeSummaryOrderFact.count).toHaveBeenNthCalledWith(1, {
      where: expect.objectContaining({
        AND: expect.arrayContaining([
          expect.objectContaining({
            OR: expect.arrayContaining([
              {
                sourceUserEmail: {
                  equals: 'sa2@phongvu.vn',
                  mode: 'insensitive',
                },
              },
              {
                reportCreatedByEmail: {
                  equals: 'sa2@phongvu.vn',
                  mode: 'insensitive',
                },
              },
            ]),
          }),
        ]),
      }),
    });
    expect(prisma.salesReportErpOrderCache.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          AND: expect.arrayContaining([
            expect.objectContaining({
              OR: expect.arrayContaining([
                {
                  sourceUserEmail: {
                    equals: 'sa2@phongvu.vn',
                    mode: 'insensitive',
                  },
                },
                {
                  consultantEmail: {
                    equals: 'sa2@phongvu.vn',
                    mode: 'insensitive',
                  },
                },
                {
                  sellerEmail: {
                    equals: 'sa2@phongvu.vn',
                    mode: 'insensitive',
                  },
                },
              ]),
            }),
          ]),
        }),
        select: expect.objectContaining({ lifecycleStatus: true }),
      }),
    );
    const selectedSaWhereClauses = JSON.stringify({
      orderCounts: prisma.homeSummaryOrderFact.count.mock.calls.map(
        ([args]: any[]) => args.where,
      ),
      reportCounts: prisma.homeSummaryReportFact.count.mock.calls.map(
        ([args]: any[]) => args.where,
      ),
      orderCache: prisma.salesReportErpOrderCache.findMany.mock.calls.map(
        ([args]: any[]) => args.where,
      ),
      salesReports: prisma.salesReport.findMany.mock.calls.map(
        ([args]: any[]) => args.where,
      ),
      behaviorCounts: prisma.salesReport.count.mock.calls.map(
        ([args]: any[]) => args.where,
      ),
    });
    expect(selectedSaWhereClauses).not.toContain('SA_CP75_HCM_SOUTH');
    expect(selectedSaWhereClauses).not.toContain('sourceUserId');
    expect(selectedSaWhereClauses).not.toContain('createdByUserId');
    expect(selectedSaWhereClauses).not.toContain('reportCreatedByUserId');
    expect(selectedSaWhereClauses).not.toContain('consultantCustomId');
    expect(selectedSaWhereClauses).not.toContain('sellerId');
    expect(selectedSaWhereClauses).not.toContain('createdByPersonnelCode');
    expect(selectedSaWhereClauses).toContain('sa2@phongvu.vn');
    const selectedSaReportQueries = prisma.salesReport.findMany.mock.calls
      .map(([args]: any[]) => args.where)
      .filter((where: any) => JSON.stringify(where).includes('sa2@phongvu.vn'));
    expect(selectedSaReportQueries.length).toBeGreaterThan(0);
    const selectedSaProgressReportQueries = selectedSaReportQueries.filter(
      (where: any) => JSON.stringify(where).includes('erpLifecycleStatus'),
    );
    expect(selectedSaProgressReportQueries.length).toBeGreaterThan(0);
    for (const where of selectedSaProgressReportQueries) {
      expect(where).toEqual(
        expect.objectContaining({
          AND: expect.arrayContaining([
            expect.objectContaining({
              erpLifecycleStatus: {
                in: ['COMPLETED', 'COMPLETED_PARTIAL_RETURN'],
              },
            }),
            {
              createdByEmail: {
                equals: 'sa2@phongvu.vn',
                mode: 'insensitive',
              },
            },
          ]),
        }),
      );
    }
    const selectedSaMainKpiQuery = selectedSaReportQueries.find(
      (where: any) =>
        JSON.stringify(where).includes('erpExcludedAt') &&
        !JSON.stringify(where).includes('erpLifecycleStatus'),
    );
    expect(selectedSaMainKpiQuery).toEqual(
      expect.objectContaining({
        AND: expect.arrayContaining([
          {
            createdByEmail: {
              equals: 'sa2@phongvu.vn',
              mode: 'insensitive',
            },
          },
        ]),
      }),
    );
    expect(prisma.mapVietinTransaction.count).toHaveBeenNthCalledWith(1, {
      where: expect.objectContaining({
        AND: expect.arrayContaining([{ storeCode: { in: ['CP75'] } }]),
      }),
    });
  });

  it('does not expose finance metrics when its dashboard section is disabled', async () => {
    const { service, prisma, featureService } = createHarness();
    featureService.canAccessFeature.mockImplementation(
      async (_user: any, featureCode: string) =>
        featureCode === 'HOME_DASHBOARD_SALES',
    );

    await expect(
      service.getSummary(
        { id: 'user-1', email: 'staff@phongvu.vn' },
        { date: '2026-07-04' },
      ),
    ).resolves.toMatchObject({
      available: true,
      salesAvailable: true,
      financeAvailable: false,
      totalTransferredAmount: 0,
      totalStatements: 0,
      totalStatementsWithOrder: 0,
      totalStatementsWithoutOrder: 0,
      statementOrderRate: 0,
    });

    expect(prisma.mapVietinTransaction.count).not.toHaveBeenCalled();
    expect(prisma.mapVietinTransaction.aggregate).not.toHaveBeenCalled();
  });

  it('passes the requested dashboard scope to sales report scope resolution', async () => {
    const { service, salesReports } = createHarness();

    await service.getSummary(
      { id: 'super-1', email: 'super@phongvu.vn' },
      { date: '2026-07-04', scope: 'OWN' },
    );

    expect(salesReports.describeHomeSummaryScope).toHaveBeenCalledWith(
      { id: 'super-1', email: 'super@phongvu.vn' },
      'OWN',
      null,
      { allowOwnScope: true },
    );
  });

  it('passes selected organization node to dashboard scope resolution', async () => {
    const { service, salesReports } = createHarness();

    await service.getSummary(
      { id: 'manager-1', email: 'manager@phongvu.vn' },
      {
        date: '2026-07-04',
        scope: 'MANAGED_SCOPE',
        organizationNodeId: 'org-area-hcm',
      },
    );

    expect(salesReports.describeHomeSummaryScope).toHaveBeenCalledWith(
      { id: 'manager-1', email: 'manager@phongvu.vn' },
      'MANAGED_SCOPE',
      'org-area-hcm',
      { allowOwnScope: true },
    );
  });

  it('returns a neutral unavailable state when the user has no summary scope', async () => {
    const { service, salesReports, prisma } = createHarness();
    salesReports.describeHomeSummaryScope.mockResolvedValueOnce({
      available: false,
      scope: 'UNAVAILABLE',
      scopeLabel: 'Chưa sẵn sàng',
      scopeDetail: null,
      unavailableMessage: 'Không có quyền xem tổng quan.',
      ownUserId: null,
      ownEmail: null,
      ownPersonnelCode: null,
      allowedStoreCodes: [],
    });

    await expect(
      service.getSummary({ id: 'user-2' }, {}),
    ).resolves.toMatchObject({
      available: false,
      scope: 'UNAVAILABLE',
      totalOrders: 0,
      totalReports: 0,
      notPurchasedReports: 0,
      financeAvailable: false,
      totalStatements: 0,
      statementOrderRate: 0,
      unavailableMessage: 'Không có quyền xem tổng quan.',
    });
    expect(prisma.salesReport.findMany).not.toHaveBeenCalled();
  });

  it('keeps a personal previous-year period unavailable when a winning active CSV grain lacks personal coverage', async () => {
    const summaryDate = new Date('2025-08-10T00:00:00.000Z');
    const prisma = {
      salesHistoryActiveGrain: {
        findMany: jest.fn().mockResolvedValue([
          {
            summaryDate,
            storeCode: 'CP01',
            currentVersionId: 'version-incomplete',
          },
        ]),
      },
      salesHistoryCoverage: {
        findMany: jest.fn().mockResolvedValue([
          {
            versionId: 'version-incomplete',
            summaryDate,
            storeCode: 'CP01',
          },
        ]),
      },
      salesHistoryAggregate: {
        findMany: jest.fn().mockResolvedValue([
          {
            versionId: 'version-incomplete',
            summaryDate,
            storeCode: 'CP01',
            dimensionType: 'USER_STORE',
            dimensionKey: 'user-1',
            totalRevenue: 900n,
            totalOrders: 1,
            extendedInsuranceQuantity: 0,
            laptopQuantity: 1,
            pcQuantity: 0,
            assembledPcQuantity: 0,
            appleQuantity: 0,
            monitorQuantity: 0,
            printerQuantity: 0,
            accessoriesQuantity: 0,
          },
        ]),
      },
      homeSummaryDailyAggregate: { findMany: jest.fn() },
    };
    const service = new HomeSummaryService(prisma as any, {} as any, {} as any);

    const result = await (service as any).overlayActiveCsvHistory(
      { startDate: '2025-08-10', endDate: '2025-08-10' },
      {
        scope: 'OWN',
        ownUserId: 'user-1',
        ownEmail: 'sale@phongvu.vn',
        allowedStoreCodes: ['CP01'],
      },
    );

    expect(Array.from(result.unavailable)).toEqual(
      expect.arrayContaining(['totalRevenue', 'totalOrders']),
    );
    expect(result.values.totalRevenue).toBe(0);
    expect(result.values.totalOrders).toBe(0);
    expect(prisma.salesHistoryCoverage.findMany).toHaveBeenCalledWith({
      where: expect.objectContaining({
        versionId: { in: ['version-incomplete'] },
        reasonCodes: { has: 'PERSONAL_COVERAGE_INCOMPLETE' },
      }),
      select: {
        versionId: true,
        summaryDate: true,
        storeCode: true,
      },
    });
  });

  it('returns available zero for a personal-complete winning grain even when a stale version was incomplete', async () => {
    const summaryDate = new Date('2025-08-10T00:00:00.000Z');
    const prisma = {
      salesHistoryActiveGrain: {
        findMany: jest.fn().mockResolvedValue([
          {
            summaryDate,
            storeCode: 'CP01',
            currentVersionId: 'version-complete',
          },
        ]),
      },
      salesHistoryCoverage: {
        findMany: jest.fn().mockResolvedValue([
          {
            versionId: 'version-stale',
            summaryDate,
            storeCode: 'CP01',
          },
        ]),
      },
      salesHistoryAggregate: { findMany: jest.fn().mockResolvedValue([]) },
      homeSummaryDailyAggregate: { findMany: jest.fn() },
    };
    const service = new HomeSummaryService(prisma as any, {} as any, {} as any);

    const result = await (service as any).overlayActiveCsvHistory(
      { startDate: '2025-08-10', endDate: '2025-08-10' },
      {
        scope: 'OWN',
        ownUserId: 'user-1',
        ownEmail: 'sale@phongvu.vn',
        allowedStoreCodes: ['CP01'],
      },
    );

    expect(result.source).toBe('HYBRID_CSV');
    expect(Array.from(result.unavailable)).not.toEqual(
      expect.arrayContaining(['totalRevenue', 'totalOrders']),
    );
    expect(result.values.totalRevenue).toBe(0);
    expect(result.values.totalOrders).toBe(0);
  });
});
