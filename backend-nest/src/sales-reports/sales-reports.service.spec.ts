import { BadRequestException } from '@nestjs/common';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { SalesReportErpCanceledOrderException } from './sales-report-erp.service';
import { SalesReportsService } from './sales-reports.service';

describe('SalesReportsService', () => {
  function createHarness(options: { redis?: any } = {}) {
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue(userFixture()),
        findMany: jest.fn().mockResolvedValue([]),
      },
      salesReport: {
        findUnique: jest.fn().mockResolvedValue(null),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
        create: jest.fn().mockImplementation(({ data }: any) =>
          Promise.resolve({
            id: 'report-1',
            submittedAt: new Date('2026-06-29T01:00:00Z'),
            createdAt: new Date('2026-06-29T01:00:00Z'),
            updatedAt: new Date('2026-06-29T01:00:00Z'),
            ...data,
            items: data.items?.create ?? [],
            payments: data.payments?.create ?? [],
          }),
        ),
        count: jest.fn(),
        findMany: jest.fn(),
      },
      salesReportErpOrderCache: {
        findUnique: jest.fn().mockResolvedValue(null),
        count: jest.fn(),
        findMany: jest.fn(),
        upsert: jest.fn().mockResolvedValue({}),
        update: jest.fn().mockResolvedValue({}),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      store: {
        findMany: jest.fn().mockResolvedValue([
          {
            storeId: 'CP62',
            storeName: 'CP62',
            organizationNodeId: 'node-cp62',
          },
        ]),
      },
      $transaction: jest.fn((value: any) =>
        Array.isArray(value) ? Promise.all(value) : value(prisma),
      ),
    };
    const categories = {
      listCategories: jest.fn(),
      requireCategories: jest.fn().mockImplementation((ids: string[]) =>
        Promise.resolve(
          ids.map((id) => ({
            id,
            catGroupName:
              id === 'NH08'
                ? 'Network and Security equipment'
                : 'Computer components',
            catGroupNameVi:
              id === 'NH08' ? 'Thiết bị mạng và an ninh' : 'Linh kiện máy tính',
          })),
        ),
      ),
      matchCategoriesFromErp: jest.fn(),
      matchTypeFromListingCategories: jest.fn().mockResolvedValue('memory'),
    };
    const erp = {
      lookupOrder: jest.fn().mockResolvedValue(erpOrderFixture()),
      lookupOrderStatus: jest.fn().mockResolvedValue({
        ...erpListOrderFixture(),
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
        statusCheckedAt: new Date('2026-07-05T01:00:00Z'),
      }),
      listRecentOrders: jest.fn().mockResolvedValue([erpListOrderFixture()]),
    };
    const service = new SalesReportsService(
      prisma as any,
      categories as any,
      erp as any,
      undefined,
      options.redis,
    );
    return { service, prisma, categories, erp };
  }

  it('requires order code for purchased report', async () => {
    const { service, erp } = createHarness();

    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        reportType: 'PURCHASED',
        orderCode: '',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(erp.lookupOrder).not.toHaveBeenCalled();
  });

  it('blocks duplicate purchased order before ERP lookup', async () => {
    const { service, prisma, erp } = createHarness();
    prisma.salesReport.findUnique.mockResolvedValueOnce({ id: 'existing' });

    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        reportType: 'PURCHASED',
        orderCode: '2606290001',
      }),
    ).rejects.toThrow('Đơn hàng này đã được báo cáo mua hàng.');
    expect(erp.lookupOrder).not.toHaveBeenCalled();
  });

  it('blocks cached canceled orders before ERP lookup', async () => {
    const { service, prisma, erp } = createHarness();
    prisma.salesReportErpOrderCache.findUnique.mockResolvedValueOnce({
      excludedAt: new Date('2026-07-04T01:00:00Z'),
      exclusionReason: 'ERP_ORDER_CANCELLED',
    });

    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        reportType: 'PURCHASED',
        orderCode: '2606290002',
      }),
    ).rejects.toThrow('Đơn đã bị hủy.');

    expect(erp.lookupOrder).not.toHaveBeenCalled();
  });

  it('requires customer need and explicit behavior answers before lookup', async () => {
    const { service, categories, erp } = createHarness();

    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        customerNeed: '',
      }),
    ).rejects.toThrow('Vui lòng nhập nhu cầu khách hàng.');
    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        consultedSolutionAnswer: '',
      }),
    ).rejects.toThrow('Vui lòng chọn kết quả tư vấn 3 giải pháp.');

    expect(categories.requireCategories).not.toHaveBeenCalled();
    expect(erp.lookupOrder).not.toHaveBeenCalled();
  });

  it('creates not-purchased report without ERP lookup', async () => {
    const { service, prisma, erp } = createHarness();

    await service.create(userFixture(), {
      ...baseInput(),
      reportType: 'NOT_PURCHASED',
      orderCode: undefined,
      notPurchasedReason: 'PRICE_HESITATION',
    });

    expect(erp.lookupOrder).not.toHaveBeenCalled();
    expect(prisma.salesReport.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          reportType: 'NOT_PURCHASED',
          orderCode: null,
          customerName: 'Nguyen Van A',
          notPurchasedReason: 'PRICE_HESITATION',
          customerType: 'PERSONAL',
          customerIsStudent: false,
          promotionCodes: [],
          categoryGroupId: 'NH03',
          categorySelections: {
            create: [
              expect.objectContaining({
                categoryGroupId: 'NH03',
                categoryGroupNameVi: 'Linh kiện máy tính',
              }),
            ],
          },
        }),
      }),
    );
  });

  it('persists canceled exclusions when ERP lookup confirms the order was canceled', async () => {
    const { service, prisma, erp } = createHarness();
    erp.lookupOrder.mockRejectedValueOnce(
      new SalesReportErpCanceledOrderException(
        canceledErpOrderCacheItemFixture('2606290002'),
      ),
    );

    await expect(
      service.checkOrder(userFixture(), '2606290002'),
    ).rejects.toThrow('Đơn đã bị hủy.');

    expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { orderCode: '2606290002' },
        create: expect.objectContaining({
          orderCode: '2606290002',
          exclusionReason: 'ERP_ORDER_CANCELLED',
          excludedAt: expect.any(Date),
        }),
      }),
    );
    expect(prisma.salesReport.updateMany).toHaveBeenCalledWith({
      where: { orderCode: '2606290002' },
      data: {
        erpExcludedAt: expect.any(Date),
        erpExclusionReason: 'ERP_ORDER_CANCELLED',
      },
    });
  });

  it('reads cached ERP orders and splits reported from unreported orders', async () => {
    const { service, prisma, erp } = createHarness();
    prisma.salesReport.count.mockResolvedValueOnce(1);
    prisma.salesReportErpOrderCache.count.mockResolvedValueOnce(1);
    prisma.salesReport.findMany
      .mockResolvedValueOnce([{ orderCode: '2607010001' }])
      .mockResolvedValueOnce([
        { ...exportReportFixture(), orderCode: '2607010001' },
      ]);
    prisma.salesReportErpOrderCache.findMany.mockResolvedValueOnce([
      erpOrderCacheFixture('2607010002'),
    ]);

    const result = await service.orderCockpit(userFixture(), {
      startDate: '2026-06-25',
      endDate: '2026-07-01',
    });

    expect(erp.listRecentOrders).not.toHaveBeenCalled();
    expect(prisma.salesReportErpOrderCache.upsert).not.toHaveBeenCalled();
    expect(result.reportedOrders).toHaveLength(1);
    expect(result.unreportedOrders).toHaveLength(1);
    expect(result.unreportedOrders[0].orderCode).toBe('2607010002');
    expect(result.scope).toBe('OWN');
    expect(result.syncSucceeded).toBe(true);
    expect(result.syncCount).toBe(0);
    expect(result.startDate).toBe('2026-06-25');
    expect(result.endDate).toBe('2026-07-01');
    expect(result.date).toBe('2026-07-01');
    expect(result.limit).toBe(20);
    expect(result.reportedPage).toBe(0);
    expect(result.reportedTotal).toBe(1);
    expect(result.unreportedPage).toBe(0);
    expect(result.unreportedTotal).toBe(1);
    expect(prisma.salesReport.findMany).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        select: { orderCode: true },
      }),
    );
    expect(prisma.salesReport.findMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        skip: 0,
        take: 20,
      }),
    );
    const cacheFindArgs =
      prisma.salesReportErpOrderCache.findMany.mock.calls[0][0];
    expect(cacheFindArgs).toEqual(
      expect.objectContaining({
        skip: 0,
        take: 20,
      }),
    );
    expect(JSON.stringify(cacheFindArgs.where)).toContain('"excludedAt":null');
    expect(JSON.stringify(cacheFindArgs.where)).toContain(
      '"notIn":["2607010001"]',
    );
    expect(
      JSON.stringify(prisma.salesReport.findMany.mock.calls[1][0].where),
    ).toContain('"erpExcludedAt":null');
  });

  it('rejects an order cockpit date range whose end is before its start', async () => {
    const { service } = createHarness();

    await expect(
      service.orderCockpit(userFixture(), {
        startDate: '2026-07-02',
        endDate: '2026-07-01',
      }),
    ).rejects.toThrow('Ngày kết thúc phải bằng hoặc sau ngày bắt đầu.');
  });

  it('lets super admin see all cached unreported orders without store scope', async () => {
    const { service, prisma } = createHarness();
    prisma.salesReport.count.mockResolvedValueOnce(0);
    prisma.salesReportErpOrderCache.count.mockResolvedValueOnce(25);
    prisma.salesReport.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    prisma.salesReportErpOrderCache.findMany.mockResolvedValueOnce([
      erpOrderCacheFixture('2607010002'),
    ]);

    const result = await service.orderCockpit(
      { ...userFixture(), role: 'SUPER_ADMIN' },
      {
        date: '2026-07-01',
        reportedPage: 2,
        unreportedPage: 1,
      },
    );

    expect(result.scope).toBe('MANAGED_SCOPE');
    expect(result.reportedPage).toBe(2);
    expect(result.unreportedPage).toBe(1);
    expect(result.unreportedTotal).toBe(25);
    expect(prisma.salesReport.findMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        skip: 40,
        take: 20,
      }),
    );
    const cacheFindArgs =
      prisma.salesReportErpOrderCache.findMany.mock.calls[0][0];
    expect(cacheFindArgs).toEqual(
      expect.objectContaining({
        skip: 20,
        take: 20,
      }),
    );
    expect(JSON.stringify(cacheFindArgs.where)).not.toContain('storeCode');
  });

  it('lets store managers see cached unreported orders in their showroom scope', async () => {
    const { service, prisma } = createHarness();
    const manager = storeManagerFixture('CP01');
    prisma.user.findUnique.mockResolvedValue(manager);
    prisma.salesReport.count.mockResolvedValueOnce(0);
    prisma.salesReportErpOrderCache.count.mockResolvedValueOnce(1);
    prisma.salesReport.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    prisma.salesReportErpOrderCache.findMany.mockResolvedValueOnce([
      { ...erpOrderCacheFixture('2607010003'), storeCode: 'CP01' },
    ]);

    const result = await service.orderCockpit(
      { id: manager.id, email: manager.email, role: 'USER' },
      {
        date: '2026-07-01',
      },
    );

    expect(result.scope).toBe('MANAGED_SCOPE');
    expect(result.unreportedTotal).toBe(1);
    expect(prisma.user.findUnique).toHaveBeenCalledWith(
      expect.objectContaining({
        select: expect.objectContaining({ jobRoleCode: true }),
      }),
    );
    const cacheFindArgs =
      prisma.salesReportErpOrderCache.findMany.mock.calls[0][0];
    const cacheWhere = JSON.stringify(cacheFindArgs.where);
    expect(cacheWhere).toContain('"storeCode":"CP01"');
    expect(cacheWhere).not.toContain('consultantEmail');
    expect(cacheWhere).not.toContain('sellerEmail');
  });

  it('filters the manager cockpit by date, store and user with scoped options', async () => {
    const { service, prisma } = createHarness();
    const manager = storeManagerFixture('CP01');
    prisma.user.findUnique.mockResolvedValue(manager);
    prisma.salesReport.count.mockResolvedValueOnce(0);
    prisma.salesReportErpOrderCache.count.mockResolvedValueOnce(1);
    prisma.salesReport.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        {
          storeCode: 'CP01',
          storeName: 'Phong Vu CP01',
          createdByEmail: 'sale.cp01@phongvu.vn',
          createdByName: 'Sale CP01',
        },
      ]);
    prisma.salesReportErpOrderCache.findMany
      .mockResolvedValueOnce([
        { ...erpOrderCacheFixture('2607010003'), storeCode: 'CP01' },
      ])
      .mockResolvedValueOnce([
        {
          storeCode: 'CP01',
          storeName: 'Phong Vu CP01',
          consultantEmail: 'sale.cp01@phongvu.vn',
          consultantName: 'Sale CP01',
          sellerEmail: null,
          sellerName: null,
          sourceUserEmail: 'sale.cp01@phongvu.vn',
        },
      ]);

    const result = await service.orderCockpit(
      { id: manager.id, email: manager.email, role: 'USER' },
      {
        date: '2026-07-01',
        storeCode: 'CP01',
        userEmail: 'SALE.CP01@phongvu.vn',
      },
    );

    expect(result.selectedStoreCode).toBe('CP01');
    expect(result.selectedUserEmail).toBe('sale.cp01@phongvu.vn');
    expect(result.storeOptions).toEqual([
      { value: 'CP01', label: 'CP01 - Phong Vu CP01' },
    ]);
    expect(result.userOptions).toEqual([
      {
        value: 'sale.cp01@phongvu.vn',
        label: 'Sale CP01 - sale.cp01@phongvu.vn',
      },
    ]);
    const reportedWhere = JSON.stringify(
      prisma.salesReport.findMany.mock.calls[1][0].where,
    );
    const cacheWhere = JSON.stringify(
      prisma.salesReportErpOrderCache.findMany.mock.calls[0][0].where,
    );
    expect(reportedWhere).toContain('sale.cp01@phongvu.vn');
    expect(reportedWhere).toContain('CP01');
    expect(cacheWhere).toContain('sale.cp01@phongvu.vn');
    expect(cacheWhere).toContain('CP01');
  });

  it('scheduled sync pulls ERP orders and upserts the cache without a client request', async () => {
    const { service, prisma, erp } = createHarness();
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    const oldLookback = process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
    delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = '1';

    try {
      const result = await service.syncScheduledErpOrderCache('test');

      expect(erp.listRecentOrders).toHaveBeenCalledWith(
        expect.objectContaining({
          date: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/),
          limit: 50,
        }),
      );
      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607010002' },
          create: expect.objectContaining({
            orderCode: '2607010002',
            sourceUserEmail: null,
            storeCode: 'CP62',
          }),
        }),
      );
      expect(result).toMatchObject({ skipped: false, count: 1 });
    } finally {
      if (oldEnabled === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_ENABLED = oldEnabled;
      }
      if (oldLookback === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = oldLookback;
      }
    }
  });

  it('keeps verified ERP status when list sync sees the order as pending', async () => {
    const { service, prisma, erp } = createHarness();
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    const oldLookback = process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
    delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = '1';
    const verifiedAt = new Date('2026-07-06T03:40:00Z');
    erp.listRecentOrders.mockResolvedValueOnce([
      {
        ...erpListOrderFixture(),
        fulfillmentStatus: 'DELIVERED',
        lifecycleStatus: 'PENDING',
        statusCheckedAt: new Date('2026-07-06T03:54:00Z'),
        fetchedAt: new Date('2026-07-06T03:54:00Z'),
      },
    ]);
    prisma.salesReportErpOrderCache.findMany.mockResolvedValueOnce([
      {
        orderCode: '2607010002',
        paymentStatus: 'fully_paid',
        confirmationStatus: 'active',
        fulfillmentStatus: 'DELIVERED',
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
        statusCheckedAt: verifiedAt,
        statusCheckAttemptedAt: verifiedAt,
        statusCheckFailureCount: 0,
        excludedAt: null,
        exclusionReason: null,
        consultantEmail: 'sale@phongvu.vn',
        sellerEmail: null,
        storeCode: 'CP62',
        organizationNodeId: 'node-cp62',
        sourceUserId: 'user-1',
        sourceUserEmail: 'sale@phongvu.vn',
      },
    ]);

    try {
      await service.syncScheduledErpOrderCache('test-preserve-status');

      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607010002' },
          update: expect.objectContaining({
            lifecycleStatus: 'COMPLETED',
            fulfillmentStatus: 'DELIVERED',
            statusCheckedAt: verifiedAt,
            statusCheckAttemptedAt: verifiedAt,
            statusCheckFailureCount: 0,
          }),
        }),
      );
      expect(prisma.salesReport.updateMany).toHaveBeenCalledWith({
        where: { orderCode: '2607010002', reportType: 'PURCHASED' },
        data: expect.objectContaining({
          erpLifecycleStatus: 'COMPLETED',
          erpFulfillmentStatus: 'DELIVERED',
          erpStatusCheckedAt: verifiedAt,
          erpStatusCheckFailureCount: 0,
        }),
      });
    } finally {
      if (oldEnabled === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_ENABLED = oldEnabled;
      }
      if (oldLookback === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = oldLookback;
      }
    }
  });

  it('scheduled sync marks canceled ERP orders as excluded and hides related purchased reports', async () => {
    const { service, prisma, erp } = createHarness();
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    const oldLookback = process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
    delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = '1';
    erp.listRecentOrders.mockResolvedValueOnce([
      {
        ...erpListOrderFixture(),
        orderCode: '2607010999',
        erpOrderId: '2607010999',
        confirmationStatus: 'CANCELLED',
        fulfillmentStatus: 'PROCESSING',
      },
    ]);

    try {
      await service.syncScheduledErpOrderCache('test');

      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607010999' },
          create: expect.objectContaining({
            orderCode: '2607010999',
            exclusionReason: 'ERP_ORDER_CANCELLED',
            excludedAt: expect.any(Date),
          }),
        }),
      );
      expect(prisma.salesReport.updateMany).toHaveBeenCalledWith({
        where: { orderCode: '2607010999' },
        data: {
          erpExcludedAt: expect.any(Date),
          erpExclusionReason: 'ERP_ORDER_CANCELLED',
        },
      });
    } finally {
      if (oldEnabled === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_ENABLED = oldEnabled;
      }
      if (oldLookback === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = oldLookback;
      }
    }
  });

  it('maps the ERP creator to the assigned user and store during scheduled sync', async () => {
    const { service, prisma, erp } = createHarness();
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    const oldLookback = process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
    delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = '1';
    erp.listRecentOrders.mockResolvedValueOnce([
      {
        ...erpListOrderFixture(),
        orderCode: '2607010003',
        storeCode: null,
        storeName: null,
        consultantEmail: 'sale.cp01@phongvu.vn',
        sellerEmail: 'sale.cp01@phongvu.vn',
      },
    ]);
    prisma.user.findMany.mockResolvedValueOnce([
      {
        id: 'sale-cp01',
        email: 'Sale.CP01@phongvu.vn',
        store: null,
        organizationNode: null,
        organizationAssignments: [
          {
            organizationNode: {
              id: 'node-cp01',
              stores: [
                {
                  storeId: 'CP01',
                  storeName: 'Phong Vu CP01',
                },
              ],
              children: [],
              parent: null,
            },
          },
        ],
      },
    ]);

    try {
      await service.syncScheduledErpOrderCache('test-owner-map');

      expect(prisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            email: {
              in: ['sale.cp01@phongvu.vn'],
              mode: 'insensitive',
            },
          },
        }),
      );
      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607010003' },
          create: expect.objectContaining({
            sourceUserId: 'sale-cp01',
            sourceUserEmail: 'sale.cp01@phongvu.vn',
            storeCode: 'CP01',
            storeName: 'Phong Vu CP01',
            organizationNodeId: 'node-cp01',
          }),
          update: expect.objectContaining({
            sourceUserId: 'sale-cp01',
            sourceUserEmail: 'sale.cp01@phongvu.vn',
            storeCode: 'CP01',
            organizationNodeId: 'node-cp01',
          }),
        }),
      );
    } finally {
      if (oldEnabled === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_ENABLED = oldEnabled;
      }
      if (oldLookback === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = oldLookback;
      }
    }
  });

  it('backfills missing store scope from an existing mapped user during scheduled sync', async () => {
    const redis = {
      publishMessage: jest.fn().mockResolvedValue(undefined),
    };
    const { service, prisma, erp } = createHarness({ redis });
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    const oldLookback = process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
    delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = '1';
    erp.listRecentOrders.mockResolvedValueOnce([
      {
        ...erpListOrderFixture(),
        orderCode: '2607010004',
        storeCode: null,
        storeName: null,
        consultantEmail: null,
        sellerEmail: null,
      },
    ]);
    prisma.salesReportErpOrderCache.findMany.mockResolvedValueOnce([
      {
        orderCode: '2607010004',
        consultantEmail: null,
        sellerEmail: null,
        storeCode: null,
        organizationNodeId: null,
        sourceUserId: 'sale-cp01',
        sourceUserEmail: 'sale.cp01@phongvu.vn',
      },
    ]);
    prisma.user.findMany.mockResolvedValueOnce([
      {
        id: 'sale-cp01',
        email: 'Sale.CP01@phongvu.vn',
        store: null,
        organizationNode: null,
        organizationAssignments: [
          {
            organizationNode: {
              id: 'node-cp01',
              stores: [
                {
                  storeId: 'CP01',
                  storeName: 'Phong Vu CP01',
                },
              ],
              children: [],
              parent: null,
            },
          },
        ],
      },
    ]);

    try {
      const result =
        await service.syncScheduledErpOrderCache('test-backfill-map');

      expect(result).toMatchObject({
        skipped: false,
        count: 1,
        newOrderCount: 0,
        mappedOrderCount: 1,
      });
      expect(prisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            email: {
              in: ['sale.cp01@phongvu.vn'],
              mode: 'insensitive',
            },
          },
        }),
      );
      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607010004' },
          update: expect.objectContaining({
            sourceUserId: 'sale-cp01',
            sourceUserEmail: 'sale.cp01@phongvu.vn',
            storeCode: 'CP01',
            storeName: 'Phong Vu CP01',
            organizationNodeId: 'node-cp01',
          }),
        }),
      );
      expect(redis.publishMessage).toHaveBeenCalledWith(
        'SALES_REPORT_ORDERS_UPDATED',
        expect.objectContaining({
          newOrderCount: 0,
          mappedOrderCount: 1,
          storeCodes: ['CP01'],
          recipientUserIds: ['sale-cp01'],
        }),
      );
    } finally {
      if (oldEnabled === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_ENABLED = oldEnabled;
      }
      if (oldLookback === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = oldLookback;
      }
    }
  });

  it('does not erase an existing cache owner or store when ERP mapping is missing', async () => {
    const { service, prisma, erp } = createHarness();
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    const oldLookback = process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
    delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = '1';
    erp.listRecentOrders.mockResolvedValueOnce([
      {
        ...erpListOrderFixture(),
        storeCode: null,
        storeName: null,
        consultantCustomId: null,
        consultantName: null,
        consultantEmail: null,
        sellerId: null,
        sellerName: null,
        sellerEmail: null,
      },
    ]);

    try {
      await service.syncScheduledErpOrderCache('test-preserve-map');

      const upsert = prisma.salesReportErpOrderCache.upsert.mock.calls[0][0];
      expect(upsert.create).toEqual(
        expect.objectContaining({ storeCode: null, sourceUserEmail: null }),
      );
      expect(upsert.update).not.toHaveProperty('storeCode');
      expect(upsert.update).not.toHaveProperty('organizationNodeId');
      expect(upsert.update).not.toHaveProperty('sourceUserEmail');
      expect(upsert.update).not.toHaveProperty('consultantEmail');
    } finally {
      if (oldEnabled === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_ENABLED = oldEnabled;
      }
      if (oldLookback === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = oldLookback;
      }
    }
  });

  it('can disable the scheduled ERP order cache sync through env', async () => {
    const { service, prisma, erp } = createHarness();
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_ENABLED = 'false';

    try {
      const result = await service.syncScheduledErpOrderCache('test');

      expect(erp.listRecentOrders).not.toHaveBeenCalled();
      expect(prisma.salesReportErpOrderCache.upsert).not.toHaveBeenCalled();
      expect(result).toEqual({ skipped: true, count: 0, dates: [] });
    } finally {
      if (oldEnabled === undefined) {
        delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
      } else {
        process.env.ERP_ORDER_CACHE_SYNC_ENABLED = oldEnabled;
      }
    }
  });

  it('refreshes a full 50-order status batch with the 40/10 quota and concurrency 2', async () => {
    const { service, prisma, erp } = createHarness();
    const previous = {
      enabled: process.env.ERP_ORDER_STATUS_SYNC_ENABLED,
      batch: process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE,
      concurrency: process.env.ERP_ORDER_STATUS_SYNC_CONCURRENCY,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE = '50';
    process.env.ERP_ORDER_STATUS_SYNC_CONCURRENCY = '2';
    const row = (index: number, lifecycleStatus: string) => ({
      orderCode: String(2607012000 + index),
      storeCode: 'CP62',
      erpLifecycleStatus: lifecycleStatus,
      erpStatusCheckedAt: new Date(
        `2026-07-04T${String(index % 24).padStart(2, '0')}:00:00Z`,
      ),
      erpOrderCreatedAt: new Date('2026-07-04T00:00:00Z'),
    });
    prisma.salesReport.findMany
      .mockResolvedValueOnce(
        Array.from({ length: 45 }, (_, index) => row(index, 'PENDING')),
      )
      .mockResolvedValueOnce(
        Array.from({ length: 5 }, (_, index) => row(index + 100, 'COMPLETED')),
      );
    let active = 0;
    let maxActive = 0;
    erp.lookupOrderStatus.mockImplementation(async (orderCode: string) => {
      active += 1;
      maxActive = Math.max(maxActive, active);
      await new Promise((resolve) => setImmediate(resolve));
      active -= 1;
      return {
        ...erpListOrderFixture(),
        orderCode,
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
        statusCheckedAt: new Date('2026-07-05T01:00:00Z'),
      };
    });

    try {
      await expect(service.syncErpOrderStatuses('test')).resolves.toEqual({
        skipped: false,
        processed: 50,
        changed: 45,
        failed: 0,
      });
      expect(maxActive).toBe(2);
      expect(erp.lookupOrderStatus).toHaveBeenCalledTimes(50);
      expect(prisma.salesReport.findMany).toHaveBeenNthCalledWith(
        1,
        expect.objectContaining({
          where: expect.objectContaining({
            reportType: 'PURCHASED',
            orderCode: { not: null },
            erpLifecycleStatus: 'PENDING',
          }),
          take: 50,
        }),
      );
      expect(prisma.salesReport.findMany).toHaveBeenNthCalledWith(
        2,
        expect.objectContaining({
          where: expect.objectContaining({
            reportType: 'PURCHASED',
            orderCode: { not: null },
            erpLifecycleStatus: {
              in: ['COMPLETED', 'COMPLETED_PARTIAL_RETURN'],
            },
          }),
          take: 50,
        }),
      );
      expect(prisma.salesReportErpOrderCache.findMany).not.toHaveBeenCalled();
    } finally {
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous.enabled);
      restoreEnv('ERP_ORDER_STATUS_SYNC_BATCH_SIZE', previous.batch);
      restoreEnv('ERP_ORDER_STATUS_SYNC_CONCURRENCY', previous.concurrency);
    }
  });

  it('keeps refreshing the remaining orders when one ERP status lookup fails', async () => {
    const { service, prisma, erp } = createHarness();
    const previous = process.env.ERP_ORDER_STATUS_SYNC_ENABLED;
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    prisma.salesReport.findMany
      .mockResolvedValueOnce([
        {
          orderCode: '2607013001',
          storeCode: 'CP62',
          erpLifecycleStatus: 'PENDING',
          erpStatusCheckedAt: null,
          erpOrderCreatedAt: new Date('2026-07-04T00:00:00Z'),
        },
        {
          orderCode: '2607013002',
          storeCode: 'CP62',
          erpLifecycleStatus: 'PENDING',
          erpStatusCheckedAt: null,
          erpOrderCreatedAt: new Date('2026-07-04T00:00:00Z'),
        },
      ])
      .mockResolvedValueOnce([]);
    erp.lookupOrderStatus.mockImplementation(async (orderCode: string) => {
      if (orderCode === '2607013001') throw new Error('ERP unavailable');
      return {
        ...erpListOrderFixture(),
        orderCode,
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
        statusCheckedAt: new Date('2026-07-05T01:00:00Z'),
      };
    });

    try {
      await expect(service.syncErpOrderStatuses('test')).resolves.toEqual({
        skipped: false,
        processed: 2,
        changed: 1,
        failed: 1,
      });
      expect(erp.lookupOrderStatus).toHaveBeenCalledTimes(2);
      expect(prisma.salesReportErpOrderCache.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607013001' },
          data: expect.objectContaining({
            statusCheckFailureCount: { increment: 1 },
          }),
        }),
      );
    } finally {
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous);
    }
  });

  it('continues status sync when a reported order is missing its cache row', async () => {
    const { service, prisma, erp } = createHarness();
    const previous = process.env.ERP_ORDER_STATUS_SYNC_ENABLED;
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    prisma.salesReport.findMany
      .mockResolvedValueOnce([
        {
          orderCode: '2607013001',
          storeCode: 'CP62',
          erpLifecycleStatus: 'PENDING',
          erpStatusCheckedAt: null,
          erpOrderCreatedAt: new Date('2026-07-04T00:00:00Z'),
        },
        {
          orderCode: '2607013002',
          storeCode: 'CP62',
          erpLifecycleStatus: 'PENDING',
          erpStatusCheckedAt: null,
          erpOrderCreatedAt: new Date('2026-07-04T00:00:00Z'),
        },
      ])
      .mockResolvedValueOnce([]);
    prisma.salesReportErpOrderCache.updateMany.mockResolvedValueOnce({
      count: 0,
    });
    erp.lookupOrderStatus.mockImplementation(async (orderCode: string) => {
      if (orderCode === '2607013001') throw new Error('ERP unavailable');
      return {
        ...erpListOrderFixture(),
        orderCode,
        lifecycleStatus: 'COMPLETED',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
        statusCheckedAt: new Date('2026-07-05T01:00:00Z'),
      };
    });

    try {
      await expect(service.syncErpOrderStatuses('test')).resolves.toEqual({
        skipped: false,
        processed: 2,
        changed: 1,
        failed: 1,
      });
      expect(prisma.salesReportErpOrderCache.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607013001' },
        }),
      );
      expect(prisma.salesReport.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607013001', reportType: 'PURCHASED' },
          data: { erpStatusCheckFailureCount: { increment: 1 } },
        }),
      );
      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607013002' },
          create: expect.objectContaining({ orderCode: '2607013002' }),
        }),
      );
    } finally {
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous);
    }
  });

  it('skips status refresh when another API replica owns the Redis lease', async () => {
    const previous = process.env.ERP_ORDER_STATUS_SYNC_ENABLED;
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    const redis = {
      tryAcquireLease: jest.fn().mockResolvedValue(null),
      releaseLease: jest.fn(),
      publishMessage: jest.fn(),
    };
    const { service, prisma, erp } = createHarness({ redis });

    try {
      await expect(service.syncErpOrderStatuses('test')).resolves.toEqual({
        skipped: true,
        processed: 0,
        changed: 0,
        failed: 0,
      });
      expect(redis.tryAcquireLease).toHaveBeenCalled();
      expect(prisma.salesReportErpOrderCache.findMany).not.toHaveBeenCalled();
      expect(erp.lookupOrderStatus).not.toHaveBeenCalled();
    } finally {
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous);
    }
  });

  it('re-checks ERP and stores normalized order rows for purchased report', async () => {
    const { service, prisma, erp } = createHarness();

    await service.create(userFixture(), {
      ...baseInput(),
      reportType: 'PURCHASED',
      orderCode: ' 2606290001 ',
      customerType: undefined,
    });

    expect(erp.lookupOrder).toHaveBeenCalledWith('2606290001', 'CP62');
    expect(prisma.salesReport.create.mock.calls[0][0].data).not.toHaveProperty(
      'jobRoleCode',
    );
    expect(prisma.salesReport.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          reportType: 'PURCHASED',
          orderCode: '2606290001',
          customerName: 'Nguyen Van A',
          erpOrderId: '2606290001',
          erpGrandTotal: 1230000,
          erpPaymentMethods: ['cash'],
          erpCustomerType: 'BUSINESS',
          customerType: 'BUSINESS',
          categorySelections: {
            create: [
              expect.objectContaining({
                categoryGroupId: 'NH03',
                categoryGroupNameVi: 'Linh kiện máy tính',
              }),
            ],
          },
          items: {
            create: [
              expect.objectContaining({
                sellerSku: 'SKU-1',
                productGroupCode: 'NH03',
                categoryType: 'memory',
              }),
            ],
          },
          payments: {
            create: [expect.objectContaining({ paymentMethod: 'cash' })],
          },
        }),
      }),
    );
  });

  it('uses ERP customer type over stale purchased-report payload', async () => {
    const { service, prisma } = createHarness();

    await service.create(userFixture(), {
      ...baseInput(),
      reportType: 'PURCHASED',
      orderCode: '26061334475420',
      customerType: 'PERSONAL',
    });

    expect(prisma.salesReport.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          orderCode: '26061334475420',
          erpCustomerType: 'BUSINESS',
          customerType: 'BUSINESS',
          customerIsStudent: false,
        }),
      }),
    );
  });

  it('stores multiple selected category groups with the first one as primary', async () => {
    const { service, prisma, categories } = createHarness();

    await service.create(userFixture(), {
      ...baseInput(),
      categoryGroupId: 'NH03',
      categoryGroupIds: ['NH03', 'NH08'],
    });

    expect(categories.requireCategories).toHaveBeenCalledWith(['NH03', 'NH08']);
    expect(prisma.salesReport.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          categoryGroupId: 'NH03',
          categoryGroupNameVi: 'Linh kiện máy tính',
          categorySelections: {
            create: [
              expect.objectContaining({
                categoryGroupId: 'NH03',
                sortOrder: 0,
              }),
              expect.objectContaining({
                categoryGroupId: 'NH08',
                sortOrder: 1,
              }),
            ],
          },
        }),
      }),
    );
  });

  it('rejects student flag for business customer type', async () => {
    const { service, prisma } = createHarness();

    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        customerType: 'BUSINESS',
        customerIsStudent: true,
      }),
    ).rejects.toThrow(
      'Doanh nghiệp không thể đồng thời là Học sinh - Sinh viên.',
    );

    expect(prisma.salesReport.create).not.toHaveBeenCalled();
  });

  it('requires installment details and stores selected partners', async () => {
    const { service, prisma } = createHarness();

    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        installmentNeed: true,
        installmentApproved: false,
        installmentNoInstallmentReason: 'BAD_CREDIT_HISTORY',
        installmentPartnerCodes: [],
      }),
    ).rejects.toThrow('Vui lòng chọn đối tác trả góp.');

    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        installmentNeed: true,
        installmentApproved: false,
        installmentPartnerCodes: ['VNPAY_POS'],
      }),
    ).rejects.toThrow('Vui lòng chọn lý do không trả góp.');

    await service.create(userFixture(), {
      ...baseInput(),
      customerIsStudent: true,
      promotionCodes: ['STUDENT', 'OTHER'],
      installmentNeed: true,
      installmentApproved: true,
      installmentLoanAmount: 5000000,
      installmentNoInstallmentReason: 'NORMAL_INSTALLMENT',
      installmentPartnerCodes: ['VNPAY_POS', 'MIRAE_ASSET', 'MPOS'],
    });

    expect(prisma.salesReport.create).toHaveBeenLastCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          customerIsStudent: true,
          promotionCodes: ['STUDENT', 'OTHER'],
          installmentNeed: true,
          installmentApproved: true,
          installmentLoanAmount: 5000000,
          installmentNoInstallmentReason: 'NORMAL_INSTALLMENT',
          installmentStatus: 'SUCCESS',
          installmentFailureReason: null,
          installmentPartnerCodes: ['VNPAY_POS', 'MIRAE_ASSET', 'MPOS'],
        }),
      }),
    );
  });

  it('exports Vietnamese HVTC CSV rows per report', async () => {
    const { service, prisma } = createHarness();
    prisma.salesReport.findMany.mockResolvedValueOnce([exportReportFixture()]);

    const csv = await service.exportCsv(
      { ...userFixture(), role: 'SUPER_ADMIN' },
      {},
    );
    const lines = csv.replace(/^\ufeff/, '').split('\n');

    expect(lines[0]).toBe(
      [
        'Ngày báo cáo',
        'Email người báo cáo',
        'Mã nhân viên tư vấn ERP',
        'Tên khách hàng',
        'Số điện thoại khách hàng',
        'Nhu cầu khách hàng',
        'Kết quả tư vấn giải pháp',
        'Lý do khác khi không tư vấn',
        'Kết quả trải nghiệm sản phẩm',
        'Lý do khác khi không trải nghiệm',
        'Kết quả quét Zalo',
        'Lý do khác khi không quét Zalo',
        'Kết quả tải App PV',
        'Lý do khác khi không tải App PV',
        'Loại báo cáo',
        'Lý do khách chưa mua',
        'Lý do khác khi khách chưa mua',
        'Mã showroom',
      ].join(','),
    );
    expect(lines).toHaveLength(2);
    expect(lines[1]).toContain('Nguyen; Van A');
    expect(lines[1]).toContain('Mua hàng');
    expect(lines[1]).toContain('Có');
    expect(lines[1]).not.toContain('"');
    expect(lines[0]).not.toContain('Report date');
  });

  it('exports Vietnamese revenue summary CSV by category type', async () => {
    const { service, prisma } = createHarness();
    prisma.salesReport.findMany.mockResolvedValueOnce(revenueReportFixtures());

    const csv = await service.exportCsv(
      { ...userFixture(), role: 'SUPER_ADMIN' },
      { exportType: 'REVENUE' },
    );
    const lines = csv.replace(/^\ufeff/, '').split('\n');

    expect(lines[0]).toBe(
      [
        'Số đơn hàng duy nhất',
        'Tổng doanh thu khách hàng doanh nghiệp',
        'Tổng doanh thu khách hàng cá nhân',
        'Nhu cầu trả góp (cả có và không)',
        'Trả góp thành công (có đơn trả góp)',
        'Số lượng laptop',
        'Số lượng PC',
        'Số lượng PC ráp',
        'Số lượng Apple',
        'Số lượng màn hình',
        'Số lượng máy in',
        'Số lượng phụ kiện',
        'Số lượng dịch vụ bảo hiểm',
        'Các lý do khách không trả góp',
      ].join(','),
    );
    expect(lines[1]).toContain('2,1000,2000,3,0');
    expect(lines[1]).toContain(',3,2,1,1,3,1,4,1,');
    expect(lines[1]).toContain('Khách từ chối: Lãi suất/Phí trả góp cao: 1');
    expect(lines[1]).not.toContain('"');
  });

  it('exports installment CSV rows only for installment reports', async () => {
    const { service, prisma } = createHarness();
    prisma.salesReport.findMany.mockResolvedValueOnce([
      {
        ...exportReportFixture(),
        erpPaymentMethods: ['cash', 'installment'],
      },
      {
        ...exportReportFixture(),
        id: 'report-installment-cash',
        orderCode: '2606290999',
        erpPaymentMethods: ['cash'],
        installmentApproved: false,
        installmentLoanAmount: 2500000,
        installmentPartnerCodes: ['PAYOO_POS'],
        installmentNoInstallmentReason: 'HIGH_INTEREST_OR_FEE',
      },
      {
        ...exportReportFixture(),
        id: 'report-no-installment',
        orderCode: '2606290888',
        installmentNeed: false,
        installmentPartnerCodes: [],
      },
    ]);

    const csv = await service.exportCsv(
      { ...userFixture(), role: 'SUPER_ADMIN' },
      { exportType: 'INSTALLMENT' },
    );
    const lines = csv.replace(/^\ufeff/, '').split('\n');

    expect(prisma.salesReport.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.any(Object),
      }),
    );
    const exportWhere = JSON.stringify(
      prisma.salesReport.findMany.mock.calls[0][0].where,
    );
    expect(exportWhere).toContain('"installmentNeed":true');
    expect(exportWhere).toContain('"erpExcludedAt":null');
    expect(lines[0]).toBe(
      [
        'Ngày báo cáo',
        'Email người báo cáo',
        'Số tiền vay trả góp',
        'Đối tác trả góp',
        'Kết quả duyệt hồ sơ',
        'Loại báo cáo',
        'Phương thức thanh toán cuối cùng',
        'Lý do không trả góp',
      ].join(','),
    );
    expect(lines).toHaveLength(3);
    expect(lines[1]).toContain('sale@phongvu.vn,5000000,VNPAY_POS; MPOS');
    expect(lines[1]).toContain('Đã duyệt,Mua hàng,Trả góp');
    expect(lines[1]).toContain(
      'Khách chốt trả góp bình thường (Không có lý do)',
    );
    expect(lines[2]).toContain('2500000,PAYOO_POS,Chưa duyệt');
    expect(lines[2]).toContain('Trả thẳng');
    expect(lines.join('\n')).not.toContain('2606290888');
    expect(lines[1]).not.toContain('"');
  });

  it('keeps home dashboard scope options at showroom level for assigned position nodes', async () => {
    const { service, prisma } = createHarness();
    const { storeNode, positionNode } = organizationNodeFixture();
    prisma.user.findUnique.mockResolvedValue({
      organizationNode: positionNode,
      organizationAssignments: [
        {
          organizationNodeId: positionNode.id,
          organizationNode: positionNode,
          isPrimary: true,
        },
      ],
    });

    const options = await service.listHomeSummaryScopeOptions(
      adminSalesUser(),
      {
        allowOwnScope: true,
      },
    );

    expect(options).toEqual([
      expect.objectContaining({
        value: 'OWN',
        label: 'Phạm vi cá nhân',
        isDefault: true,
      }),
      expect.objectContaining({
        value: `NODE:${storeNode.id}`,
        label: 'Showroom: CP75',
        organizationNodeId: storeNode.id,
        organizationNodeType: 'LV4_STORE',
        storeCount: 1,
      }),
    ]);
    expect(options.map((option) => option.organizationNodeId)).not.toContain(
      positionNode.id,
    );
  });

  it.each(['SA', 'TECH', 'WAREHOUSE', 'CASH'])(
    'offers personal and assigned-showroom dashboard scopes to %s',
    async (jobRoleCode) => {
      const { service, prisma } = createHarness();
      const { storeNode, positionNode } = organizationNodeFixture();
      const user = {
        ...userFixture(),
        jobRoleCode,
        store: null,
        organizationNode: positionNode,
        organizationAssignments: [
          {
            organizationNodeId: positionNode.id,
            organizationNode: positionNode,
            isPrimary: true,
          },
        ],
      };
      prisma.user.findUnique.mockResolvedValue(user);

      const options = await service.listHomeSummaryScopeOptions(user, {
        allowOwnScope: true,
      });

      expect(options.map((option) => option.value)).toEqual([
        'OWN',
        `NODE:${storeNode.id}`,
      ]);
      expect(options[0]).toMatchObject({
        label: 'Phạm vi cá nhân',
        isDefault: true,
      });
      expect(options[1]).toMatchObject({
        label: 'Showroom: CP75',
        organizationNodeType: 'LV4_STORE',
        isDefault: false,
      });

      await expect(
        service.describeHomeSummaryScope(user, 'MANAGED_SCOPE', storeNode.id, {
          allowOwnScope: true,
        }),
      ).resolves.toMatchObject({
        available: true,
        scope: 'MANAGED_SCOPE',
        scopeLabel: 'Showroom: CP75',
        allowedStoreCodes: ['CP75'],
      });
    },
  );

  it('rejects broad managed scope for personal-or-showroom dashboard roles', async () => {
    const { service, prisma } = createHarness();
    const user = { ...userFixture(), jobRoleCode: 'SA' };
    prisma.user.findUnique.mockResolvedValue(user);

    await expect(
      service.describeHomeSummaryScope(user, 'MANAGED_SCOPE', null, {
        allowOwnScope: true,
      }),
    ).resolves.toMatchObject({
      available: false,
      scope: 'UNAVAILABLE',
      unavailableMessage:
        'Vui lòng chọn phạm vi cá nhân hoặc một showroom được gán.',
    });
  });

  it('keeps personal dashboard finance scope at the user assigned showroom', async () => {
    const { service } = createHarness();
    const user = {
      ...userFixture(),
      featureAccess: { [FEATURE_KEYS.SALES_REPORT]: true },
    };

    await expect(
      service.describeHomeSummaryScope(user, 'OWN'),
    ).resolves.toMatchObject({
      available: true,
      scope: 'OWN',
      scopeLabel: 'Phạm vi cá nhân',
      allowedStoreCodes: ['CP62'],
    });
  });

  it('allows home dashboard scope requests for the parent showroom of an assigned position node', async () => {
    const { service, prisma } = createHarness();
    const { storeNode, positionNode } = organizationNodeFixture();
    const savedUser = {
      ...adminSalesUser(),
      organizationNode: positionNode,
      organizationAssignments: [
        {
          organizationNodeId: positionNode.id,
          organizationNode: positionNode,
          isPrimary: true,
        },
      ],
    };
    prisma.user.findUnique
      .mockResolvedValueOnce(savedUser)
      .mockResolvedValueOnce(savedUser);

    await expect(
      service.describeHomeSummaryScope(
        adminSalesUser(),
        'MANAGED_SCOPE',
        storeNode.id,
        { allowOwnScope: true },
      ),
    ).resolves.toMatchObject({
      available: true,
      scope: 'MANAGED_SCOPE',
      scopeLabel: 'Showroom: CP75',
      allowedStoreCodes: ['CP75'],
    });
  });
});

function baseInput() {
  return {
    reportType: 'NOT_PURCHASED',
    categoryGroupId: 'NH03',
    customerName: 'Nguyen Van A',
    customerPhone: '',
    customerType: 'PERSONAL',
    customerIsStudent: false,
    promotionCodes: [],
    customerNeed: 'RAM DDR5',
    consultedSolutionAnswer: 'YES',
    consultedSolutionOtherReason: undefined,
    experiencedAnswer: 'YES',
    experiencedOtherReason: undefined,
    zaloAnswer: 'YES',
    zaloOtherReason: undefined,
    appDownloadAnswer: 'YES',
    appDownloadOtherReason: undefined,
    notPurchasedReason: 'PRICE_HESITATION',
    notPurchasedOtherReason: undefined,
  };
}

function userFixture() {
  return {
    id: 'user-1',
    email: 'sale@phongvu.vn',
    firstName: 'Sale',
    lastName: 'CP62',
    jobRoleCode: 'SA',
    store: {
      storeId: 'CP62',
      storeName: 'CP62',
      area: {
        code: 'HCM',
        abbreviation: 'HCM',
        region: { code: 'MN', abbreviation: 'MN' },
      },
      organizationNode: { id: 'node-cp62', displayName: 'CP62' },
    },
    organizationNode: { id: 'node-cp62', displayName: 'CP62' },
    organizationAssignments: [],
  };
}

function adminSalesUser() {
  return {
    ...userFixture(),
    id: 'admin-sales-1',
    featureAccess: {
      [FEATURE_KEYS.ADMIN_SALES_REPORTS]: true,
    },
  };
}

function organizationNodeFixture() {
  const storeNode: any = {
    id: 'node-cp75',
    type: 'LV4_STORE',
    displayName: 'CP75',
    businessCode: 'CP75',
    stores: [{ storeId: 'CP75', storeName: 'CP75' }],
    parent: null,
    children: [],
  };
  const positionNode = {
    id: 'node-cp75-sa',
    type: 'LV5_POSITION',
    displayName: 'SA CP75',
    stores: [],
    parent: storeNode,
    children: [],
  };
  storeNode.children = [positionNode];
  return { storeNode, positionNode };
}

function storeManagerFixture(storeCode: string) {
  return {
    ...userFixture(),
    id: `manager-${storeCode.toLowerCase()}`,
    email: `manager.${storeCode.toLowerCase()}@phongvu.vn`,
    firstName: 'Manager',
    lastName: storeCode,
    jobRoleCode: 'STORE_MANAGER',
    store: {
      storeId: storeCode,
      storeName: storeCode,
      area: {
        code: 'HCM',
        abbreviation: 'HCM',
        region: { code: 'MN', abbreviation: 'MN' },
      },
      organizationNode: {
        id: `node-${storeCode.toLowerCase()}`,
        displayName: storeCode,
      },
    },
    organizationNode: {
      id: `node-${storeCode.toLowerCase()}`,
      displayName: storeCode,
    },
    organizationAssignments: [],
  };
}

function erpOrderFixture() {
  return {
    orderCode: '2606290001',
    erpOrderId: '2606290001',
    erpExternalOrderRef: null,
    erpOrderCreatedAt: new Date('2026-06-29T00:00:00Z'),
    erpPaymentStatus: 'fully_paid',
    erpConfirmationStatus: 'active',
    erpFulfillmentStatus: 'PROCESSING',
    erpTerminalName: 'CP62',
    erpGrandTotal: 1230000,
    erpCustomerType: 'BUSINESS',
    erpPlatformId: 1,
    erpConsultantCustomId: '7583',
    erpConsultantName: 'Sale CP62',
    customerName: 'Nguyen Van A',
    customerType: 'BUSINESS',
    customerNeed: 'RAM DDR5',
    categoryCandidates: ['Computer components'],
    items: [
      {
        sku: 'SKU-1',
        sellerSku: 'SKU-1',
        name: 'RAM DDR5',
        brandCode: null,
        brandName: 'Kingston',
        productTypeCode: null,
        productTypeName: null,
        productGroupId: 'NH03',
        productGroupCode: 'NH03',
        productGroupName: 'Computer components',
        categoryType: null,
        listingCategories: [],
        quantity: 1,
        sellPrice: 1230000,
        finalSellPrice: 1230000,
        rowTotal: 1230000,
        raw: { sellerSku: 'SKU-1' },
      },
    ],
    payments: [
      {
        paymentMethod: 'cash',
        amount: 1230000,
        paidAt: new Date('2026-06-29T00:05:00Z'),
        transactionCode: 'TX-1',
        partnerTransactionCode: null,
        raw: { paymentMethod: 'cash' },
      },
    ],
    paymentMethods: ['cash'],
    sanitizedSnapshot: { orderId: '2606290001' },
    fetchedAt: new Date('2026-06-29T00:06:00Z'),
  };
}

function erpListOrderFixture() {
  return {
    orderCode: '2607010002',
    erpOrderId: '2607010002',
    erpExternalOrderRef: null,
    orderCreatedAt: new Date('2026-07-01T01:00:00Z'),
    paymentStatus: 'fully_paid',
    confirmationStatus: 'active',
    fulfillmentStatus: 'PROCESSING',
    terminalName: 'CP62',
    grandTotal: 2500000,
    customerName: 'Tran Thi B',
    customerPhone: '0900000000',
    customerType: 'PERSONAL',
    paymentMethods: ['cash'],
    platformId: 3,
    consultantCustomId: 'SA_CP62_HCM_MN',
    consultantName: 'Sale CP62',
    consultantEmail: 'sale@phongvu.vn',
    sellerId: null,
    sellerName: null,
    sellerEmail: null,
    storeCode: 'CP62',
    storeName: 'CP62',
    sanitizedSnapshot: { orderCode: '2607010002' },
    fetchedAt: new Date('2026-07-01T01:03:00Z'),
  };
}

function erpOrderCacheFixture(orderCode: string) {
  return {
    id: `cache-${orderCode}`,
    orderCode,
    erpOrderId: orderCode,
    erpExternalOrderRef: null,
    orderCreatedAt: new Date('2026-07-01T01:00:00Z'),
    paymentStatus: 'fully_paid',
    confirmationStatus: 'active',
    fulfillmentStatus: 'PROCESSING',
    terminalName: 'CP62',
    grandTotal: 2500000,
    customerName: 'Tran Thi B',
    customerPhone: '0900000000',
    customerType: 'PERSONAL',
    paymentMethods: ['cash'],
    platformId: 3,
    consultantCustomId: 'SA_CP62_HCM_MN',
    consultantName: 'Sale CP62',
    consultantEmail: 'sale@phongvu.vn',
    sellerId: null,
    sellerName: null,
    sellerEmail: null,
    storeCode: 'CP62',
    storeName: 'CP62',
    organizationNodeId: 'node-cp62',
    sourceUserId: 'user-1',
    sourceUserEmail: 'sale@phongvu.vn',
    sanitizedSnapshot: { orderCode },
    fetchedAt: new Date('2026-07-01T01:03:00Z'),
    createdAt: new Date('2026-07-01T01:03:00Z'),
    updatedAt: new Date('2026-07-01T01:03:00Z'),
  };
}

function canceledErpOrderCacheItemFixture(orderCode: string) {
  return {
    ...erpListOrderFixture(),
    orderCode,
    erpOrderId: orderCode,
    confirmationStatus: 'CANCELLED',
    fulfillmentStatus: 'PROCESSING',
    sanitizedSnapshot: {
      orderCode,
      confirmationStatus: 'CANCELLED',
      fulfillmentStatus: 'PROCESSING',
    },
    fetchedAt: new Date('2026-07-04T01:03:00Z'),
  };
}

function exportReportFixture() {
  return {
    id: 'report-1',
    reportType: 'PURCHASED',
    orderCode: '2606290001',
    customerName: 'Nguyen, Van A',
    customerPhone: '0900000000',
    customerNeed: 'RAM DDR5',
    categoryGroupId: 'NH03',
    categoryGroupName: 'Computer components',
    categoryGroupNameVi: 'Linh kiện máy tính',
    consultedSolutionAnswer: 'YES',
    consultedSolutionOtherReason: null,
    experiencedAnswer: 'YES',
    experiencedOtherReason: null,
    zaloAnswer: 'YES',
    zaloOtherReason: null,
    appDownloadAnswer: 'YES',
    appDownloadOtherReason: null,
    notPurchasedReason: null,
    notPurchasedOtherReason: null,
    customerType: 'BUSINESS',
    customerIsStudent: false,
    promotionCodes: ['EXAM_SCORE_EXCHANGE'],
    installmentNeed: true,
    installmentApproved: true,
    installmentLoanAmount: 5000000,
    installmentNoInstallmentReason: 'NORMAL_INSTALLMENT',
    installmentStatus: 'SUCCESS',
    installmentFailureReason: null,
    installmentPartnerCodes: ['VNPAY_POS', 'MPOS'],
    createdByEmail: 'sale@phongvu.vn',
    createdByName: 'Sale CP62',
    createdByPersonnelCode: '7583',
    storeCode: 'CP62',
    storeName: 'PHAN DANG LUU',
    erpOrderId: '2606290001',
    erpOrderCreatedAt: new Date('2026-06-29T00:00:00Z'),
    erpPaymentStatus: 'fully_paid',
    erpConfirmationStatus: 'active',
    erpFulfillmentStatus: 'DELIVERED',
    erpTerminalName: 'CP62',
    erpGrandTotal: 1500000,
    erpPaymentMethods: ['cash', 'bank_transfer'],
    erpPlatformId: 1,
    submittedAt: new Date('2026-06-29T01:00:00Z'),
    categorySelections: [
      {
        categoryGroupId: 'NH03',
        categoryGroupName: 'Computer components',
        categoryGroupNameVi: 'Linh kiện máy tính',
      },
    ],
    items: [
      {
        sku: 'SKU-1',
        sellerSku: 'SKU-1',
        name: 'RAM DDR5 16GB',
        brandName: 'Kingston',
        productGroupId: 'NH03',
        productGroupCode: 'NH03',
        productGroupName: 'Computer components',
        categoryType: 'memory',
        productTypeCode: 'MEMORY',
        productTypeName: 'Memory',
        quantity: 1,
        finalSellPrice: 1230000,
        rowTotal: 1230000,
      },
      {
        sku: 'SKU-2',
        sellerSku: 'SKU-2',
        name: 'Keyboard',
        brandName: 'Logitech',
        productGroupId: 'NH04',
        productGroupCode: 'NH04',
        productGroupName: 'Peripheral',
        categoryType: 'accessories',
        productTypeCode: 'KEYBOARD',
        productTypeName: 'Keyboard',
        quantity: 1,
        finalSellPrice: 270000,
        rowTotal: 270000,
      },
    ],
    payments: [
      { paymentMethod: 'cash', amount: 500000 },
      { paymentMethod: 'bank_transfer', amount: 1000000 },
    ],
  };
}

function revenueReportFixtures() {
  return [
    {
      ...exportReportFixture(),
      id: 'report-business',
      orderCode: '2606290001',
      customerType: 'BUSINESS',
      erpGrandTotal: 1000,
      items: [
        itemFixture('Laptop gaming', 'laptop', 1),
        itemFixture('PC bộ văn phòng', 'pc', 2),
        itemFixture('CPU Intel', 'cpu', 1),
        itemFixture('Mainboard Asus', 'mainboard', 1),
        itemFixture('RAM DDR5', 'memory', 2),
        itemFixture('SSD 1TB', 'storage', 1),
        itemFixture('Case ATX', 'case', 1),
        itemFixture('Nguồn 650W', 'psu', 1),
        itemFixture('iPhone 15', 'apple', 1),
        itemFixture('Apple Watch', 'apple', 1),
        itemFixture('Màn hình 27 inch', 'monitor', 3),
        itemFixture('Máy in Canon', 'printer', 1),
        itemFixture('Chuột không dây', 'accessories', 4),
        itemFixture('Bảo hiểm mở rộng', 'extendedInsurance', 1),
      ],
    },
    {
      ...exportReportFixture(),
      id: 'report-personal',
      orderCode: '2606290002',
      customerType: 'PERSONAL',
      erpGrandTotal: 2000,
      items: [itemFixture('Laptop văn phòng', 'laptop', 2)],
    },
    {
      ...exportReportFixture(),
      id: 'report-not-purchased',
      reportType: 'NOT_PURCHASED',
      orderCode: null,
      customerType: 'PERSONAL',
      erpGrandTotal: null,
      installmentNeed: true,
      installmentNoInstallmentReason: 'HIGH_INTEREST_OR_FEE',
      items: [],
    },
  ];
}

function itemFixture(name: string, categoryType: string, quantity: number) {
  return {
    sku: `SKU-${name}`,
    sellerSku: `SKU-${name}`,
    name,
    brandName: null,
    productGroupId: null,
    productGroupCode: null,
    productGroupName: null,
    categoryType,
    productTypeCode: null,
    productTypeName: null,
    quantity,
    finalSellPrice: 1,
    rowTotal: quantity,
  };
}

function restoreEnv(key: string, value: string | undefined) {
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}
