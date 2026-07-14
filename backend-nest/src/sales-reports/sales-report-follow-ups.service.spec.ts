import { SalesReportFollowUpsService } from './sales-report-follow-ups.service';

describe('SalesReportFollowUpsService', () => {
  it('chỉ truy vấn hồ sơ có số điện thoại hoặc Zalo cá nhân', async () => {
    const sourceReport = {
      id: 'report-1',
      reportType: 'NOT_PURCHASED',
      customerName: 'Nguyễn Văn A',
      customerPhone: null,
      customerZaloContact: 'zalo-khach-a',
      categoryGroupId: 'NH01',
      categoryGroupNameVi: 'Laptop',
      categorySelections: [],
      submittedAt: new Date('2026-07-10T02:00:00Z'),
      createdByName: 'Nhân viên A',
      createdByEmail: 'a@phongvu.vn',
      notPurchasedReason: 'CUSTOMER_BROWSING',
      notPurchasedOtherReason: null,
      storeCode: 'CP01',
      storeName: 'Phong Vũ CP01',
    };
    const row = {
      id: 'case-1',
      status: 'OPEN',
      assigneeUserId: 'user-a',
      assigneeEmail: 'a@phongvu.vn',
      assigneeName: 'Nhân viên A',
      lastFollowUpAt: null,
      lastFollowUpByName: null,
      followUpCount: 0,
      sourceReport,
      entries: [],
    };
    const findMany = jest.fn().mockResolvedValue([row]);
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          email: 'admin@phongvu.vn',
          role: 'SUPER_ADMIN',
        }),
      },
      salesReportFollowUpCase: {
        count: jest.fn().mockResolvedValue(1),
        findMany,
      },
      $transaction: jest.fn((operations: Promise<unknown>[]) =>
        Promise.all(operations),
      ),
    };
    const service = new SalesReportFollowUpsService(
      prisma as any,
      {} as any,
      {} as any,
    );

    const result = await service.list(
      { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
      { status: 'OPEN', page: 0, limit: 20 },
    );

    expect(result.items).toHaveLength(1);
    expect(result.items[0].customerZaloContact).toBe('zalo-khach-a');
    expect(result.managedScope).toBe(true);
    const where = findMany.mock.calls[0][0].where;
    expect(JSON.stringify(where)).toContain('customerPhone');
    expect(JSON.stringify(where)).toContain('customerZaloContact');
    expect(JSON.stringify(where)).not.toContain('assigneeUserId');
    expect(JSON.stringify(where)).not.toContain('storeCode');
  });
});
