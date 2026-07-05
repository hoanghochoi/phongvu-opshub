import { HomeSummaryService } from './home-summary.service';

describe('HomeSummaryService', () => {
  function createHarness() {
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
      },
      salesReportErpOrderCache: {
        findMany: jest.fn().mockResolvedValue([
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
        ]),
      },
      homeSummaryReportFact: {
        upsert: jest.fn().mockResolvedValue({}),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
        count: jest.fn().mockResolvedValue(2),
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

  it('returns scoped summary metrics from dedicated home summary facts', async () => {
    const { service, prisma, salesReports } = createHarness();

    await expect(
      service.getSummary({ id: 'user-1', email: 'staff@phongvu.vn' }, {}),
    ).resolves.toMatchObject({
      available: true,
      scope: 'OWN',
      scopeLabel: 'Phạm vi cá nhân',
      coverageLabel: 'Tỉ lệ báo cáo',
      totalRevenue: 12500000,
      totalOrders: 2,
      totalReports: 2,
      reportedOrders: 1,
      unreportedOrders: 1,
      coverageRate: 50,
      conversionRate: 100,
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
    expect(prisma.homeSummaryOrderFact.upsert).toHaveBeenCalledTimes(2);
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

  it('does not expose finance metrics when its dashboard section is disabled', async () => {
    const { service, prisma, featureService } = createHarness();
    featureService.canAccessFeature.mockImplementation(
      async (_user: any, featureCode: string) =>
        featureCode === 'HOME_DASHBOARD_SALES',
    );

    await expect(
      service.getSummary({ id: 'user-1', email: 'staff@phongvu.vn' }, {}),
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
      financeAvailable: false,
      totalStatements: 0,
      statementOrderRate: 0,
      unavailableMessage: 'Không có quyền xem tổng quan.',
    });
    expect(prisma.salesReport.findMany).not.toHaveBeenCalled();
  });
});
