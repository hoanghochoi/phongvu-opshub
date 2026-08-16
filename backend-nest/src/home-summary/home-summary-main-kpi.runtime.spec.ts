import {
  HomeSummaryMainKpiRuntime,
  HomeSummaryMainKpiCallbacks,
} from './home-summary-main-kpi.runtime';

describe('HomeSummaryMainKpiRuntime', () => {
  const scope = {
    available: true,
    scope: 'OWN' as const,
    scopeLabel: 'Cá nhân',
    scopeDetail: 'CP01',
    unavailableMessage: null,
    ownUserId: 'user-1',
    ownEmail: 'staff@phongvu.vn',
    ownPersonnelCode: 'PV001',
    allowedStoreCodes: ['CP01'],
  };
  const range = {
    start: new Date('2026-07-01T00:00:00.000Z'),
    end: new Date('2026-08-01T00:00:00.000Z'),
  };

  function createRuntime() {
    const prisma: any = {
      salesReport: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    const canonicalRevenue = {
      values: new Map([['ORDER-1', 12500000]]),
      presentCodes: new Set(['ORDER-1']),
      invalidCodes: new Set(),
    };
    const summary = {
      orderCountUnique: 1,
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
    };
    const callbacks: HomeSummaryMainKpiCallbacks = {
      salesReportMainKpiWhere: jest
        .fn()
        .mockReturnValue({ id: { not: '__NO_MAIN_KPI__' } }),
      loadCanonicalRevenueForRows: jest
        .fn()
        .mockResolvedValue(canonicalRevenue),
      summarizeSalesRevenueRows: jest.fn().mockReturnValue(summary),
    };
    return {
      prisma,
      callbacks,
      canonicalRevenue,
      summary,
      runtime: new HomeSummaryMainKpiRuntime(prisma, callbacks),
    };
  }

  it('loads the existing main-KPI row shape and maps the facade summary', async () => {
    const { runtime, prisma, callbacks, canonicalRevenue, summary } =
      createRuntime();
    const rows = [
      {
        id: 'report-1',
        reportType: 'PURCHASED',
        orderCode: 'ORDER-1',
        erpOrderId: 'ERP-1',
        customerType: 'BUSINESS',
        promotionCodes: ['STUDENT'],
        installmentNeed: true,
        installmentStatus: 'SUCCESS',
        installmentNoInstallmentReason: null,
        items: [],
      },
    ];
    prisma.salesReport.findMany.mockResolvedValue(rows);

    await expect(runtime.build(scope, range)).resolves.toEqual({
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
    });
    expect(callbacks.salesReportMainKpiWhere).toHaveBeenCalledWith(
      scope,
      range,
    );
    expect(prisma.salesReport.findMany).toHaveBeenCalledWith({
      where: { id: { not: '__NO_MAIN_KPI__' } },
      select: expect.objectContaining({
        id: true,
        orderCode: true,
        customerType: true,
        promotionCodes: true,
        installmentNeed: true,
        items: expect.objectContaining({
          orderBy: { createdAt: 'asc' },
        }),
      }),
    });
    expect(callbacks.loadCanonicalRevenueForRows).toHaveBeenCalledWith(
      rows,
      'main_kpis',
    );
    expect(callbacks.summarizeSalesRevenueRows).toHaveBeenCalledWith(
      rows,
      canonicalRevenue,
    );
    expect(summary).toBeDefined();
  });

  it('returns a stable zero summary when sales are unavailable', () => {
    const { runtime } = createRuntime();

    expect(runtime.empty()).toEqual({
      businessCustomerRevenue: 0,
      personalCustomerRevenue: 0,
      examScorePromotionCount: 0,
      studentPromotionCount: 0,
      installmentNeedCount: 0,
      successfulInstallmentCount: 0,
      extendedInsuranceQuantity: 0,
      laptopQuantity: 0,
      pcQuantity: 0,
      assembledPcQuantity: 0,
      appleQuantity: 0,
      monitorQuantity: 0,
      printerQuantity: 0,
      accessoriesQuantity: 0,
    });
  });
});
