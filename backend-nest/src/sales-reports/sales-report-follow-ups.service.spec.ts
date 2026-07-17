import { SalesReportFollowUpsService } from './sales-report-follow-ups.service';

describe('SalesReportFollowUpsService', () => {
  const graceUntilEnv = 'SALES_REPORT_FOLLOW_UP_CONTACT_GRACE_UNTIL';
  const originalGraceUntil = process.env[graceUntilEnv];

  beforeEach(() => {
    delete process.env[graceUntilEnv];
  });

  afterAll(() => {
    if (originalGraceUntil === undefined) delete process.env[graceUntilEnv];
    else process.env[graceUntilEnv] = originalGraceUntil;
  });

  it('sau grace chỉ hiển thị số điện thoại hợp lệ hoặc kênh Zalo đã lưu', async () => {
    process.env[graceUntilEnv] = '2000-07-31T02:00:00.000Z';
    const makeRow = (
      id: string,
      customerPhone: string | null,
      customerZaloContact: string | null,
      customerContactChannels: string[] = [],
    ) => ({
      id,
      status: 'OPEN',
      assigneeUserId: 'user-a',
      assigneeEmail: 'a@phongvu.vn',
      assigneeName: 'Nhân viên A',
      lastFollowUpAt: null,
      lastFollowUpByName: null,
      followUpCount: 0,
      sourceReport: {
        id: `report-${id}`,
        reportType: 'NOT_PURCHASED',
        customerName: 'Nguyễn Văn A',
        customerPhone,
        customerContactChannels,
        customerZaloContact,
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
      },
      entries: [],
    });
    const candidates = [
      makeRow('valid-phone', '0909000000', null, ['PHONE']),
      makeRow('valid-zalo-personal', null, null, ['ZALO_PERSONAL']),
      makeRow('valid-zalo-oa', null, null, ['ZALO_OA']),
      makeRow('invalid-zero', '0', null),
      makeRow('invalid-text', 'Không cung cấp', null),
    ];
    const rows = candidates.slice(0, 3);
    const findMany = jest
      .fn()
      .mockImplementation(({ select }: { select?: unknown }) =>
        Promise.resolve(select ? candidates : rows),
      );
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          email: 'admin@phongvu.vn',
          role: 'SUPER_ADMIN',
        }),
      },
      salesReportFollowUpCase: {
        findMany,
      },
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

    expect(result.items).toHaveLength(3);
    expect(result.total).toBe(3);
    expect(result.items.map((item) => item.id)).toEqual([
      'valid-phone',
      'valid-zalo-personal',
      'valid-zalo-oa',
    ]);
    expect(result.managedScope).toBe(true);
    expect(result.contactGracePeriodActive).toBe(false);
    expect(result.contactGracePeriodEndsAt?.toISOString()).toBe(
      '2000-07-31T02:00:00.000Z',
    );
    const where = findMany.mock.calls[0][0].where;
    expect(JSON.stringify(where)).toContain('customerPhone');
    expect(JSON.stringify(where)).toContain('customerContactChannels');
    expect(JSON.stringify(where)).not.toContain('customerZaloContact');
    expect(JSON.stringify(where)).not.toContain('assigneeUserId');
    expect(JSON.stringify(where)).not.toContain('storeCode');
  });

  it('hiển thị toàn bộ hồ sơ trước thời điểm kết thúc rà soát liên hệ', async () => {
    process.env[graceUntilEnv] = '2099-07-31T02:00:00.000Z';
    const makeRow = (
      id: string,
      customerPhone: string | null,
      customerZaloContact: string | null,
      customerContactChannels: string[] = [],
    ) => ({
      id,
      status: 'OPEN',
      assigneeUserId: 'user-a',
      assigneeEmail: 'a@phongvu.vn',
      assigneeName: 'Nhân viên A',
      lastFollowUpAt: null,
      lastFollowUpByName: null,
      followUpCount: 0,
      sourceReport: {
        id: `report-${id}`,
        reportType: 'NOT_PURCHASED',
        customerName: 'Nguyễn Văn A',
        customerPhone,
        customerContactChannels,
        customerZaloContact,
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
      },
      entries: [],
    });
    const candidates = [
      makeRow('valid-phone', '0909000000', null),
      makeRow('invalid-text', 'Không cung cấp', null),
      makeRow('missing-contact', null, null),
    ];
    const findMany = jest.fn().mockResolvedValue(candidates);
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          email: 'admin@phongvu.vn',
          role: 'SUPER_ADMIN',
        }),
      },
      salesReportFollowUpCase: { findMany },
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

    expect(result.items.map((item) => item.id)).toEqual([
      'valid-phone',
      'invalid-text',
      'missing-contact',
    ]);
    expect(result.total).toBe(3);
    expect(result.contactGracePeriodActive).toBe(true);
    expect(result.contactGracePeriodEndsAt?.toISOString()).toBe(
      '2099-07-31T02:00:00.000Z',
    );
    const where = findMany.mock.calls[0][0].where;
    expect(JSON.stringify(where)).not.toContain('customerPhone');
    expect(JSON.stringify(where)).not.toContain('customerZaloContact');
  });

  it('vẫn trả lịch sử khi danh sách nhân viên phân công bị lỗi tạm thời', async () => {
    const row = {
      id: 'case-detail',
      status: 'OPEN',
      assigneeUserId: 'user-a',
      assigneeEmail: 'a@phongvu.vn',
      assigneeName: 'Nhân viên A',
      lastFollowUpAt: null,
      lastFollowUpByName: null,
      followUpCount: 0,
      sourceReport: {
        reportType: 'NOT_PURCHASED',
        customerName: 'Nguyễn Văn A',
        customerPhone: '0909000000',
        customerContactChannels: ['PHONE'],
        customerZaloContact: null,
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
      },
      entries: [
        {
          id: 'entry-1',
          sequenceNumber: 1,
          outcome: 'NOT_PURCHASED',
          notPurchasedReason: 'PRICE_HESITATION',
          notPurchasedOtherReason: null,
          actorName: 'Nhân viên A',
          actorEmail: 'a@phongvu.vn',
          contactedAt: new Date('2026-07-11T02:00:00Z'),
        },
      ],
    };
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          email: 'admin@phongvu.vn',
          role: 'SUPER_ADMIN',
        }),
        findMany: jest.fn().mockRejectedValue(new Error('temporary pool busy')),
      },
      salesReportFollowUpCase: {
        findUnique: jest.fn().mockResolvedValue(row),
      },
    };
    const service = new SalesReportFollowUpsService(
      prisma as any,
      {} as any,
      {} as any,
    );

    const result = await service.detail(
      { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
      'case-detail',
    );

    expect(result.entries).toHaveLength(1);
    expect(result.assignmentCandidates).toEqual([]);
  });

  it('publishes follow-up changes with a strict server-derived audience', async () => {
    const redis = { publishMessage: jest.fn().mockResolvedValue(undefined) };
    const service = new SalesReportFollowUpsService(
      {} as any,
      {} as any,
      redis as any,
    );

    await (service as any).publish(
      {
        id: 'case-1',
        assigneeUserId: 'assignee-1',
        sourceReport: { storeCode: 'CP01' },
      },
      { id: 'actor-1' },
      'follow_up_reassigned',
      ['target-1'],
    );

    expect(redis.publishMessage).toHaveBeenCalledWith(
      'SALES_REPORT_ORDERS_UPDATED',
      expect.objectContaining({
        schemaVersion: 1,
        type: 'SALES_REPORT_ORDERS_UPDATED',
        eventId: expect.any(String),
        occurredAt: expect.any(String),
        audience: expect.objectContaining({
          storeCodes: ['CP01'],
          recipientUserIds: ['assignee-1', 'actor-1', 'target-1'],
          roles: ['SUPER_ADMIN'],
          featureCodes: ['SALES_REPORT'],
        }),
        payload: expect.objectContaining({
          source: 'follow_up_reassigned',
          caseId: 'case-1',
        }),
      }),
    );
  });
});
