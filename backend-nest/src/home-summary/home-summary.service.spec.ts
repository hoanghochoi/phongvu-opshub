import { HomeSummaryService } from './home-summary.service';

describe('HomeSummaryService', () => {
  function createHarness() {
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
        grandTotal: 12500000,
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
      },
      {
        grandTotal: 5000000,
        lifecycleStatus: 'COMPLETED_PARTIAL_RETURN',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 1000000,
      },
      {
        grandTotal: 7000000,
        lifecycleStatus: 'CANCELLED',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
      },
      {
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
      mapVietinTransaction: {
        count: jest
          .fn()
          .mockResolvedValueOnce(4)
          .mockResolvedValueOnce(3)
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
    );
    return { service, prisma, salesReports, featureService };
  }

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

  it('caches repeated Home scope option loads for the same user for the Home TTL', async () => {
    const { service, salesReports, featureService } = createHarness();
    const user = { id: 'user-1', email: 'staff@phongvu.vn' };

    const first = await service.listScopeOptions(user);
    const second = await service.listScopeOptions(user);

    expect(second).toBe(first);
    expect(featureService.canAccessFeature).toHaveBeenCalledTimes(2);
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
      totalRevenue: 16500000,
      totalOrders: 2,
      totalReports: 2,
      reportedOrders: 1,
      notPurchasedReports: 1,
      unreportedOrders: 1,
      averageOrderValue: 8250000,
      completedRevenue: 12500000,
      pendingRevenue: 4000000,
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
      totalStatements: 4,
      totalStatementsWithOrder: 3,
      totalStatementsWithoutOrder: 1,
      statementOrderRate: 75,
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
          returnedAfterTaxAmount: true,
        }),
      }),
    );
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
          erpGrandTotal: 1080000,
          erpReturnedAfterTaxAmount: 108000,
        },
      ])
      .mockResolvedValueOnce([
        {
          erpOrderCreatedAt: new Date('2026-07-04T02:00:00Z'),
          submittedAt: new Date('2026-07-04T02:10:00Z'),
          erpGrandTotal: 1080000,
          erpReturnedAfterTaxAmount: 108000,
        },
      ])
      .mockResolvedValueOnce([
        {
          erpOrderCreatedAt: new Date('2026-07-04T02:00:00Z'),
          submittedAt: new Date('2026-07-04T02:10:00Z'),
          erpGrandTotal: 1080000,
          erpReturnedAfterTaxAmount: 108000,
        },
      ]);

    const result = await service.getSummary(
      { id: 'user-1', email: 'staff@phongvu.vn', jobRoleCode: 'SA' },
      { date: '2026-07-04' },
    );

    expect(result.totalRevenue).toBe(16500000);
    expect(result.completedRevenue).toBe(972000);
    expect(result.salesProgress.day.actual).toBe(900000);
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
      day: { target: 14838710 },
      week: { target: 74193548 },
      month: { target: 460000000 },
    });
    expect(result.scopeSalesProgress).toMatchObject({
      status: 'AVAILABLE',
      scope: 'MANAGED',
      month: { target: 610000000 },
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
});
