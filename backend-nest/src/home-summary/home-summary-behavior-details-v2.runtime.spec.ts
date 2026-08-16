import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { HomeSummaryBehaviorDetailsV2Runtime } from './home-summary-behavior-details-v2.runtime';

describe('HomeSummaryBehaviorDetailsV2Runtime', () => {
  function createHarness() {
    const prisma = {
      homeSummaryReportFact: {
        count: jest.fn().mockResolvedValue(2),
        findMany: jest
          .fn()
          .mockResolvedValue([
            { salesReportId: 'report-1' },
            { salesReportId: 'report-2' },
          ]),
      },
      homeSummaryOrderFact: {
        count: jest.fn().mockResolvedValue(2),
        findMany: jest.fn().mockResolvedValue([
          {
            orderCode: 'ORDER-1',
            grandTotal: 100,
            orderCreatedAt: new Date('2026-07-04T01:00:00Z'),
            fetchedAt: new Date('2026-07-04T01:05:00Z'),
            storeCode: 'CP75',
            consultantName: 'Tư vấn',
            consultantEmail: 'consultant@example.com',
            sellerName: null,
            sellerEmail: null,
            sourceUserEmail: null,
          },
          {
            orderCode: 'ORDER-2',
            grandTotal: 200,
            orderCreatedAt: new Date('2026-07-04T02:00:00Z'),
            fetchedAt: new Date('2026-07-04T02:05:00Z'),
            storeCode: 'CP75',
            consultantName: null,
            consultantEmail: null,
            sellerName: 'Bán hàng',
            sellerEmail: 'seller@example.com',
            sourceUserEmail: null,
          },
        ]),
      },
      salesReport: {
        count: jest.fn().mockResolvedValue(2),
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'report-1',
            submittedAt: new Date('2026-07-04T03:00:00Z'),
            storeCode: 'CP75',
            createdByName: 'Nhân viên',
            createdByEmail: 'staff@example.com',
            customerName: 'Khách hàng',
            customerType: 'PERSONAL',
            categoryGroupName: 'Laptop',
            categoryGroupNameVi: 'Máy tính xách tay',
            notPurchasedReason: 'PRICE_HESITATION',
            notPurchasedOtherReason: null,
            orderCode: 'ORDER-1',
            erpOrderId: null,
            installmentStatus: 'FAILED',
            installmentFailureReason: null,
            installmentNoInstallmentReason: 'HIGH_INTEREST_OR_FEE',
            installmentPartnerCodes: ['MPOS'],
          },
          {
            id: 'report-2',
            submittedAt: new Date('2026-07-04T04:00:00Z'),
            storeCode: 'CP75',
            createdByName: 'Nhân viên 2',
            createdByEmail: 'staff2@example.com',
            customerName: null,
            customerType: null,
            categoryGroupName: null,
            categoryGroupNameVi: null,
            notPurchasedReason: null,
            notPurchasedOtherReason: null,
            orderCode: null,
            erpOrderId: null,
            installmentStatus: 'SUCCESS',
            installmentFailureReason: null,
            installmentNoInstallmentReason: 'NORMAL_INSTALLMENT',
            installmentPartnerCodes: ['MIRAE_ASSET'],
          },
        ]),
      },
      $transaction: jest.fn(async (input: any[]) => Promise.all(input)),
    };
    const callbacks = {
      parseSummaryRange: jest.fn().mockReturnValue({
        start: new Date('2026-07-04T00:00:00Z'),
        end: new Date('2026-07-05T00:00:00Z'),
        startDate: '2026-07-04',
        endDate: '2026-07-04',
      }),
      parseScopeParam: jest.fn().mockReturnValue('ALL'),
      optionalText: jest.fn((value: unknown, maxLength: number) => {
        const text = String(value || '').trim();
        return text ? text.slice(0, maxLength) : null;
      }),
      normalizeOrderCode: jest.fn(
        (value: unknown) => String(value || '').trim() || null,
      ),
      safeUserLabel: jest.fn().mockReturnValue('userId:user-1'),
      resolveSectionAccess: jest.fn().mockResolvedValue({
        salesAvailable: true,
      }),
      describeHomeSummaryScope: jest.fn().mockResolvedValue({
        available: true,
        scope: 'ALL',
        scopeLabel: 'Toàn hệ thống',
        unavailableMessage: null,
      }),
      resolveSelectedSalesMetricsScope: jest.fn().mockResolvedValue({
        scope: { scope: 'ALL', scopeLabel: 'Toàn hệ thống' },
        selectedUserId: null,
      }),
      reportScopeWhere: jest.fn().mockReturnValue({ summaryDate: {} }),
      orderScopeWhere: jest.fn().mockReturnValue({ summaryDate: {} }),
      salesReportMainKpiWhere: jest
        .fn()
        .mockReturnValue({ erpExcludedAt: null }),
      mapNotPurchased: jest.fn((row) => ({
        kind: 'not-purchased',
        id: row.id,
      })),
      mapUnreportedOrder: jest.fn((row) => ({
        kind: 'unreported',
        id: row.orderCode,
      })),
      mapInstallmentNeed: jest.fn((row) => ({
        kind: 'installment',
        id: row.id,
      })),
      unreportedEmployeeNamesByEmail: jest
        .fn()
        .mockResolvedValue(
          new Map([['consultant@example.com|CP75', 'Tư vấn']]),
        ),
      logger: { log: jest.fn() },
    };
    return {
      prisma,
      callbacks,
      runtime: new HomeSummaryBehaviorDetailsV2Runtime(
        prisma as any,
        callbacks as any,
      ),
    };
  }

  it('loads NOT_PURCHASED pages and encodes a kind-bound cursor', async () => {
    const { runtime, prisma, callbacks } = createHarness();
    const result = await runtime.load({ id: 'user-1' }, {
      kind: 'NOT_PURCHASED',
      limit: 1,
    } as any);

    expect(result).toMatchObject({
      kind: 'NOT_PURCHASED',
      total: 2,
      items: [{ kind: 'not-purchased', id: 'report-1' }],
      nextCursor: expect.any(String),
    });
    expect(callbacks.mapNotPurchased).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'report-1' }),
    );
    expect(prisma.homeSummaryReportFact.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        take: 2,
        orderBy: { salesReportId: 'asc' },
      }),
    );
    expect(
      JSON.parse(Buffer.from(result.nextCursor!, 'base64url').toString('utf8')),
    ).toEqual({ v: 1, kind: 'NOT_PURCHASED', id: 'report-1' });
  });

  it('excludes reported order codes before loading UNREPORTED_ORDER pages', async () => {
    const { runtime, prisma } = createHarness();
    prisma.homeSummaryReportFact.findMany.mockResolvedValueOnce([
      { orderCode: ' ORDER-1 ' },
    ]);

    const result = await runtime.load({ id: 'user-1' }, {
      kind: 'UNREPORTED_ORDER',
      limit: 2,
    } as any);

    expect(result.items).toEqual([
      { kind: 'unreported', id: 'ORDER-1' },
      { kind: 'unreported', id: 'ORDER-2' },
    ]);
    expect(prisma.homeSummaryOrderFact.count).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          AND: expect.arrayContaining([{ orderCode: { notIn: ['ORDER-1'] } }]),
        }),
      }),
    );
  });

  it('loads INSTALLMENT_NEED rows through the main KPI scope', async () => {
    const { runtime, callbacks, prisma } = createHarness();
    const result = await runtime.load({ id: 'user-1' }, {
      kind: 'INSTALLMENT_NEED',
      limit: 1,
    } as any);

    expect(result.items).toEqual([{ kind: 'installment', id: 'report-1' }]);
    expect(callbacks.salesReportMainKpiWhere).toHaveBeenCalled();
    expect(prisma.salesReport.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        take: 2,
        orderBy: { id: 'asc' },
      }),
    );
  });

  it('fails closed for access denial and malformed cursors', async () => {
    const denied = createHarness();
    denied.callbacks.resolveSectionAccess.mockResolvedValue({
      salesAvailable: false,
    });
    await expect(
      denied.runtime.load({ id: 'user-1' }, { kind: 'NOT_PURCHASED' } as any),
    ).rejects.toBeInstanceOf(ForbiddenException);

    const malformed = createHarness();
    await expect(
      malformed.runtime.load({ id: 'user-1' }, {
        kind: 'NOT_PURCHASED',
        cursor: 'not-a-cursor',
      } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
