import * as XLSX from 'xlsx';
import { SalesReportFollowUpsService } from './sales-report-follow-ups.service';

describe('SalesReportFollowUpsService', () => {
  const graceUntilEnv = 'SALES_REPORT_FOLLOW_UP_CONTACT_GRACE_UNTIL';
  const originalGraceUntil = process.env[graceUntilEnv];

  beforeEach(() => {
    delete process.env[graceUntilEnv];
    jest.useFakeTimers().setSystemTime(new Date('2026-07-27T05:00:00.000Z'));
  });

  afterEach(() => jest.useRealTimers());

  afterAll(() => {
    if (originalGraceUntil === undefined) delete process.env[graceUntilEnv];
    else process.env[graceUntilEnv] = originalGraceUntil;
  });

  function purchasedCaseFixture() {
    return {
      id: 'case-purchase',
      status: 'OPEN',
      assigneeUserId: 'user-1',
      assigneeEmail: 'sale@phongvu.vn',
      assigneeName: 'Sale User',
      followUpCount: 0,
      sourceReport: {
        id: 'source-not-purchased',
        reportType: 'NOT_PURCHASED',
        customerName: 'Nguyễn Văn A',
        customerPhone: '0900000000',
        customerZaloContact: null,
        storeCode: 'CP62',
        storeName: 'CP62',
        organizationNodeId: 'node-cp62',
        organizationNodeName: 'CP62',
        regionCode: null,
        areaCode: null,
      },
      entries: [],
    };
  }

  function createPurchaseHarness(options: {
    existingConvertibleReport: {
      id: string;
      entrySource: 'SYNC_LIST' | null;
    } | null;
    convertedCount?: number;
  }) {
    const row = purchasedCaseFixture();
    const prisma: any = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'user-1',
          email: 'sale@phongvu.vn',
          role: 'SUPER_ADMIN',
        }),
      },
      salesReportFollowUpCase: {
        findUnique: jest.fn().mockResolvedValue(row),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        update: jest.fn().mockResolvedValue({}),
      },
      salesReportFollowUpEntry: {
        create: jest.fn().mockResolvedValue({}),
      },
      salesReport: {
        updateMany: jest
          .fn()
          .mockResolvedValue({ count: options.convertedCount ?? 1 }),
        findUnique: jest.fn().mockResolvedValue({
          id: options.existingConvertibleReport?.id,
          reportType: 'PURCHASED',
          orderCode: '2606290001',
          entrySource: 'COMEBACK',
          items: [],
          payments: [],
          categorySelections: [],
        }),
        create: jest.fn().mockResolvedValue({
          id: 'new-comeback',
          reportType: 'PURCHASED',
          orderCode: '2606290001',
          entrySource: 'COMEBACK',
          items: [],
          payments: [],
          categorySelections: [],
        }),
      },
    };
    prisma.$transaction = jest.fn((callback: any) => callback(prisma));
    const salesReports = {
      create: jest.fn(async (_user: any, _body: any, createOptions: any) => {
        const persisted = await createOptions.persist(
          { reportType: 'PURCHASED' },
          { items: true, payments: true, categorySelections: true },
          {
            existingConvertibleReport: options.existingConvertibleReport,
            orderCode: '2606290001',
          },
        );
        return {
          ...persisted.report,
          convertedExistingReport: persisted.convertedExistingReport,
        };
      }),
    };
    const redis = { publishMessage: jest.fn().mockResolvedValue(undefined) };
    const service = new SalesReportFollowUpsService(
      prisma,
      salesReports as any,
      redis as any,
    );
    return { service, prisma, salesReports, redis };
  }

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

  it('trả lịch sử chăm sóc gồm mọi trạng thái có ít nhất một lần chăm sóc', async () => {
    const row = {
      id: 'case-history',
      status: 'PURCHASED',
      assigneeUserId: 'user-a',
      assigneeEmail: 'a@phongvu.vn',
      assigneeName: 'Nhân viên A',
      lastFollowUpAt: new Date('2026-07-20T02:00:00Z'),
      lastFollowUpByName: 'Nhân viên A',
      followUpCount: 1,
      priorityAt: new Date('2026-07-20T02:00:00Z'),
      sourceReport: {
        id: 'report-history',
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
          outcome: 'PURCHASED',
          notPurchasedReason: null,
          notPurchasedOtherReason: null,
          actorName: 'Nhân viên A',
          actorEmail: 'a@phongvu.vn',
          contactedAt: new Date('2026-07-20T02:00:00Z'),
        },
      ],
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
      salesReportFollowUpCase: { findMany },
    };
    const service = new SalesReportFollowUpsService(
      prisma as any,
      {} as any,
      {} as any,
    );

    const result = await service.list(
      { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
      { status: 'HISTORY', page: 0, limit: 20 },
    );

    expect(result.items).toHaveLength(1);
    expect(result.items[0]).toMatchObject({
      id: 'case-history',
      status: 'PURCHASED',
      followUpCount: 1,
    });
    const where = findMany.mock.calls[0][0].where;
    expect(JSON.stringify(where)).toContain('followUpCount');
    expect(JSON.stringify(where)).toContain('"gt":0');
    expect(JSON.stringify(where)).not.toContain('PURCHASED_ELSEWHERE');
    expect(findMany.mock.calls[0][0].orderBy[0]).toEqual({
      lastFollowUpAt: { sort: 'desc', nulls: 'last' },
    });
  });

  it('lọc cả ba tab theo lần chăm sóc gần nhất hoặc ngày tiếp xúc đầu', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
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

    await service.list(
      { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
      {
        status: 'OPEN',
        startDate: '2026-07-01',
        endDate: '2026-07-10',
      },
    );

    const where = findMany.mock.calls[0][0].where;
    const serialized = JSON.stringify(where);
    expect(serialized).toContain('lastFollowUpAt');
    expect(serialized).toContain('submittedAt');
    expect(serialized).toContain('2026-06-30T17:00:00.000Z');
    expect(serialized).toContain('2026-07-10T17:00:00.000Z');
  });

  it('mặc định 30 ngày và chặn khoảng ngày vượt quá 90 ngày', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
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
      { status: 'OPEN' },
    );
    expect(result.startDate).toBe('2026-06-28');
    expect(result.endDate).toBe('2026-07-27');

    await expect(
      service.list(
        { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
        { startDate: '2026-01-01', endDate: '2026-04-01' },
      ),
    ).rejects.toThrow('Chỉ có thể chọn tối đa 90 ngày');
  });

  it('chỉ manager được xuất XLSX và giữ đúng scope, keyword, ngày chăm sóc', async () => {
    const entry = {
      id: 'entry-1',
      caseId: 'case-1',
      sequenceNumber: 2,
      outcome: 'NOT_PURCHASED',
      notPurchasedReason: 'PRICE_HESITATION',
      notPurchasedOtherReason: 'Chờ khuyến mãi',
      actorName: 'Nhân viên A',
      actorEmail: 'sale@phongvu.vn',
      contactedAt: new Date('2026-07-20T03:15:00.000Z'),
      purchasedReport: null,
      case: {
        id: 'case-1',
        status: 'OPEN',
        assigneeName: 'Nhân viên A',
        assigneeEmail: 'sale@phongvu.vn',
        sourceReport: {
          reportType: 'NOT_PURCHASED',
          customerName: 'Khách A',
          customerPhone: '0900000000',
          customerContactChannels: ['PHONE', 'ZALO_PERSONAL'],
          customerZaloContact: null,
          customerNeed: 'Laptop văn phòng',
          categoryGroupNameVi: 'Laptop',
          categorySelections: [{ categoryGroupNameVi: 'Laptop', sortOrder: 0 }],
          submittedAt: new Date('2026-07-01T02:00:00.000Z'),
          createdByName: 'Nhân viên A',
          createdByEmail: 'sale@phongvu.vn',
          storeCode: 'CP01',
          storeName: 'Phong Vũ CP01',
        },
      },
    };
    const purchasedEntry = {
      ...entry,
      id: 'entry-2',
      sequenceNumber: 3,
      outcome: 'PURCHASED',
      notPurchasedReason: null,
      notPurchasedOtherReason: null,
      purchasedReport: {
        orderCode: '2607010002',
        erpGrandTotal: 1234567,
      },
    };
    const findMany = jest.fn().mockResolvedValue([entry, purchasedEntry]);
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'manager-1',
          email: 'manager@phongvu.vn',
          role: 'USER',
          jobRoleCode: 'STORE_MANAGER',
          store: { storeId: 'CP01' },
          organizationAssignments: [],
        }),
      },
      salesReportFollowUpEntry: { findMany },
    };
    const service = new SalesReportFollowUpsService(
      prisma as any,
      {} as any,
      {} as any,
    );

    const buffer = await service.exportHistory(
      { id: 'manager-1', email: 'manager@phongvu.vn', role: 'USER' },
      {
        startDate: '2026-07-01',
        endDate: '2026-07-31',
        storeCode: 'CP01',
        search: 'Khách A',
      },
    );

    const workbook = XLSX.read(buffer, { type: 'buffer' });
    const rows = XLSX.utils.sheet_to_json<unknown[]>(
      workbook.Sheets['Lịch sử chăm sóc'],
      { header: 1 },
    );
    expect(rows[0]).toEqual(
      expect.arrayContaining([
        'Mã showroom',
        'Lần chăm sóc',
        'Kết quả',
        'Mã đơn mua',
        'Doanh số',
      ]),
    );
    expect(rows[1]).toEqual(
      expect.arrayContaining([
        'CP01',
        'Khách A',
        'Điện thoại, Zalo cá nhân',
        2,
        'Phân vân giá',
        'Chờ khuyến mãi',
      ]),
    );
    expect(rows[1][19]).toBe('');
    expect(rows[2][19]).toBe('2607010002');
    expect(rows[2][20]).toBe(1234567);
    const request = findMany.mock.calls[0][0];
    expect(request.take).toBe(10_001);
    expect(JSON.stringify(request.where)).toContain('2026-06-30T17:00:00.000Z');
    expect(JSON.stringify(request.where)).toContain('CP01');
    expect(JSON.stringify(request.where)).toContain('Khách A');
  });

  it('không tạo file khi khoảng ngày không có lịch sử chăm sóc', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          email: 'admin@phongvu.vn',
          role: 'SUPER_ADMIN',
        }),
      },
      salesReportFollowUpEntry: { findMany },
    };
    const service = new SalesReportFollowUpsService(
      prisma as any,
      {} as any,
      {} as any,
    );

    await expect(
      service.exportHistory(
        { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
        { startDate: '2026-07-01', endDate: '2026-07-31' },
      ),
    ).rejects.toThrow('Không có lịch sử chăm sóc trong khoảng ngày đã chọn');
    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({ take: 10_001 }),
    );
  });

  it('yêu cầu thu hẹp khoảng ngày khi lịch sử vượt quá 10.000 lượt', async () => {
    const findMany = jest.fn().mockResolvedValue(new Array(10_001).fill({}));
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          email: 'admin@phongvu.vn',
          role: 'SUPER_ADMIN',
        }),
      },
      salesReportFollowUpEntry: { findMany },
    };
    const service = new SalesReportFollowUpsService(
      prisma as any,
      {} as any,
      {} as any,
    );

    await expect(
      service.exportHistory(
        { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
        { startDate: '2026-07-01', endDate: '2026-07-31' },
      ),
    ).rejects.toThrow(
      'Dữ liệu vượt quá 10.000 lượt chăm sóc. Vui lòng thu hẹp khoảng ngày.',
    );
  });

  it('chặn nhân viên tải lịch sử trước khi truy vấn dữ liệu', async () => {
    const findMany = jest.fn();
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'staff-1',
          email: 'staff@phongvu.vn',
          role: 'USER',
          jobRoleCode: 'SA',
          store: { storeId: 'CP01' },
          organizationAssignments: [],
        }),
      },
      salesReportFollowUpEntry: { findMany },
    };
    const service = new SalesReportFollowUpsService(
      prisma as any,
      {} as any,
      {} as any,
    );

    await expect(
      service.exportHistory(
        { id: 'staff-1', email: 'staff@phongvu.vn', role: 'USER' },
        { startDate: '2026-07-01', endDate: '2026-07-31' },
      ),
    ).rejects.toThrow('Chỉ quản lý mới có thể tải lịch sử chăm sóc');
    expect(findMany).not.toHaveBeenCalled();
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

  it('atomically converts and links the existing synced report without creating a new report', async () => {
    const { service, prisma } = createPurchaseHarness({
      existingConvertibleReport: {
        id: 'existing-synced',
        entrySource: 'SYNC_LIST',
      },
    });

    await expect(
      service.createEntry(
        { id: 'user-1', email: 'sale@phongvu.vn', role: 'SUPER_ADMIN' },
        'case-purchase',
        {
          outcome: 'PURCHASED',
          purchasedReport: { orderCode: '2606290001' } as any,
        },
      ),
    ).resolves.toMatchObject({
      caseStatus: 'PURCHASED',
      convertedExistingReport: true,
      report: { id: 'existing-synced' },
    });
    expect(prisma.salesReport.updateMany).toHaveBeenCalledWith({
      where: {
        id: 'existing-synced',
        orderCode: '2606290001',
        reportType: 'PURCHASED',
        entrySource: 'SYNC_LIST',
      },
      data: { entrySource: 'COMEBACK' },
    });
    expect(prisma.salesReport.create).not.toHaveBeenCalled();
    expect(prisma.salesReportFollowUpEntry.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        caseId: 'case-purchase',
        outcome: 'PURCHASED',
        purchasedReportId: 'existing-synced',
      }),
    });
    expect(prisma.salesReportFollowUpCase.update).toHaveBeenCalledWith({
      where: { id: 'case-purchase' },
      data: expect.objectContaining({
        status: 'PURCHASED',
        convertedReportId: 'existing-synced',
      }),
    });
  });

  it('atomically converts and links a legacy report without creating a new report', async () => {
    const { service, prisma } = createPurchaseHarness({
      existingConvertibleReport: {
        id: 'existing-legacy',
        entrySource: null,
      },
    });

    await expect(
      service.createEntry(
        { id: 'user-1', email: 'sale@phongvu.vn', role: 'SUPER_ADMIN' },
        'case-purchase',
        {
          outcome: 'PURCHASED',
          purchasedReport: { orderCode: ' 260629 0001 ' } as any,
        },
      ),
    ).resolves.toMatchObject({
      caseStatus: 'PURCHASED',
      convertedExistingReport: true,
      report: { id: 'existing-legacy' },
    });
    expect(prisma.salesReport.updateMany).toHaveBeenCalledWith({
      where: {
        id: 'existing-legacy',
        orderCode: '2606290001',
        reportType: 'PURCHASED',
        entrySource: null,
      },
      data: { entrySource: 'COMEBACK' },
    });
    expect(prisma.salesReport.create).not.toHaveBeenCalled();
    expect(prisma.salesReportFollowUpEntry.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        caseId: 'case-purchase',
        outcome: 'PURCHASED',
        purchasedReportId: 'existing-legacy',
      }),
    });
    expect(prisma.salesReportFollowUpCase.update).toHaveBeenCalledWith({
      where: { id: 'case-purchase' },
      data: expect.objectContaining({
        status: 'PURCHASED',
        convertedReportId: 'existing-legacy',
      }),
    });
  });

  it('fails closed when another request already converted the legacy report', async () => {
    const { service, prisma } = createPurchaseHarness({
      existingConvertibleReport: {
        id: 'existing-legacy',
        entrySource: null,
      },
      convertedCount: 0,
    });

    await expect(
      service.createEntry(
        { id: 'user-1', email: 'sale@phongvu.vn', role: 'SUPER_ADMIN' },
        'case-purchase',
        {
          outcome: 'PURCHASED',
          purchasedReport: { orderCode: '2606290001' } as any,
        },
      ),
    ).rejects.toThrow(
      'Đơn hàng này đã được ghi nhận là khách quay lại, không thể tạo báo cáo mua hàng trùng.',
    );
    expect(prisma.salesReport.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ entrySource: null }),
      }),
    );
    expect(prisma.salesReport.create).not.toHaveBeenCalled();
    expect(prisma.salesReportFollowUpEntry.create).not.toHaveBeenCalled();
    expect(prisma.salesReportFollowUpCase.update).not.toHaveBeenCalled();
  });

  it('keeps creating a new comeback report when no synced report exists', async () => {
    const { service, prisma } = createPurchaseHarness({
      existingConvertibleReport: null,
    });

    await expect(
      service.createEntry(
        { id: 'user-1', email: 'sale@phongvu.vn', role: 'SUPER_ADMIN' },
        'case-purchase',
        {
          outcome: 'PURCHASED',
          purchasedReport: { orderCode: '2606290001' } as any,
        },
      ),
    ).resolves.toMatchObject({
      caseStatus: 'PURCHASED',
      convertedExistingReport: false,
      report: { id: 'new-comeback' },
    });
    expect(prisma.salesReport.updateMany).not.toHaveBeenCalled();
    expect(prisma.salesReport.create).toHaveBeenCalled();
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
