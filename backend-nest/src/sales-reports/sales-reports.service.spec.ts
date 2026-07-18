import { BadRequestException } from '@nestjs/common';
import * as XLSX from 'xlsx';
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
      organizationNode: {
        findMany: jest.fn().mockResolvedValue([]),
        findUnique: jest.fn().mockResolvedValue(null),
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
      matchDeepestListingCategory: jest.fn().mockResolvedValue({
        categoryType: 'memory',
        categoryGroup: {
          id: 'NH03',
          catGroupName: 'Computer components',
          catGroupNameVi: 'Linh kiện máy tính',
        },
        sourceLevel: 4,
      }),
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

  it('publishes order cache changes with a strict server-derived audience', async () => {
    const redis = { publishMessage: jest.fn().mockResolvedValue(undefined) };
    const { service } = createHarness({ redis });
    const payload = {
      source: 'erp_status_sync',
      dates: ['2026-07-15'],
      newOrderCount: 0,
      mappedOrderCount: 2,
      storeCodes: ['CP01'],
      recipientUserIds: ['user-1'],
    };

    await (service as any).publishOrderCacheUpdated(payload);

    expect(redis.publishMessage).toHaveBeenCalledWith(
      'SALES_REPORT_ORDERS_UPDATED',
      expect.objectContaining({
        schemaVersion: 1,
        type: 'SALES_REPORT_ORDERS_UPDATED',
        audience: expect.objectContaining({
          storeCodes: ['CP01'],
          recipientUserIds: ['user-1'],
          roles: ['SUPER_ADMIN'],
          featureCodes: ['SALES_REPORT'],
        }),
        payload,
      }),
    );
  });

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

  it('blocks cached zero-value ERP orders before ERP lookup', async () => {
    const { service, prisma, erp } = createHarness();
    prisma.salesReportErpOrderCache.findUnique.mockResolvedValueOnce({
      excludedAt: new Date('2026-07-07T01:00:00Z'),
      exclusionReason: 'ERP_ORDER_ZERO_VALUE_INTERNAL',
    });

    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        reportType: 'PURCHASED',
        orderCode: '2607070000',
      }),
    ).rejects.toThrow('Đơn 0 VND là đơn vận hành nội bộ, không cần báo cáo.');

    expect(erp.lookupOrder).not.toHaveBeenCalled();
  });

  it('blocks a purchased report when ERP still marks the order unpaid', async () => {
    const { service, prisma, erp } = createHarness();
    erp.lookupOrder.mockResolvedValueOnce({
      ...erpOrderFixture(),
      erpPaymentStatus: 'pending_payment',
    });

    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        reportType: 'PURCHASED',
        orderCode: '2606290001',
      }),
    ).rejects.toThrow(
      'Đơn chưa thanh toán, vui lòng vào spos bấm Thanh toán lại hoặc Hủy đơn.',
    );

    expect(erp.lookupOrder).toHaveBeenCalledTimes(1);
    expect(prisma.salesReport.create).not.toHaveBeenCalled();
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
          customerPhone: null,
          customerContactChannels: [],
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

  it('validates not-purchased phone and stores explicit contact channels', async () => {
    const { service, prisma, erp } = createHarness();

    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        customerPhone: '1900123456',
      }),
    ).rejects.toThrow(
      'Số điện thoại phải gồm đúng 10 chữ số và bắt đầu bằng 0, hoặc để trống.',
    );

    await service.create(userFixture(), {
      ...baseInput(),
      customerPhone: '0901234567',
      customerContactChannels: ['ZALO_PERSONAL', 'ZALO_OA'],
    });

    expect(erp.lookupOrder).not.toHaveBeenCalled();
    expect(prisma.salesReport.create).toHaveBeenLastCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          customerPhone: '0901234567',
          customerContactChannels: ['PHONE', 'ZALO_PERSONAL', 'ZALO_OA'],
          customerZaloContact: null,
        }),
      }),
    );
  });

  it('maps legacy Zalo text to the personal Zalo contact channel', async () => {
    const { service, prisma } = createHarness();

    await service.create(userFixture(), {
      ...baseInput(),
      customerPhone: '',
      customerZaloContact: 'legacy-zalo-contact',
    });

    expect(prisma.salesReport.create).toHaveBeenLastCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          customerPhone: null,
          customerContactChannels: ['ZALO_PERSONAL'],
          customerZaloContact: 'legacy-zalo-contact',
        }),
      }),
    );
  });

  it('records the entry source for purchased reports from the synced order list', async () => {
    const { service, prisma } = createHarness();

    await service.create(userFixture(), {
      ...baseInput(),
      reportType: 'PURCHASED',
      orderCode: '2606290001',
      entrySource: 'SYNC_LIST',
    });

    expect(prisma.salesReport.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          reportType: 'PURCHASED',
          orderCode: '2606290001',
          rawResponses: expect.objectContaining({
            reportType: 'PURCHASED',
            entrySource: 'SYNC_LIST',
          }),
        }),
      }),
    );
  });

  it('blocks comeback credit when ERP has no creator email', async () => {
    const { service, prisma } = createHarness();

    await expect(
      service.create(userFixture(), {
        ...baseInput(),
        reportType: 'PURCHASED',
        orderCode: '2606290001',
        entrySource: 'COMEBACK',
      }),
    ).rejects.toThrow('Đơn hàng chưa có email nhân viên bán hàng trên ERP.');

    expect(prisma.salesReport.create).not.toHaveBeenCalled();
  });

  it('credits comeback to ERP creator and audits the actual submitter', async () => {
    const { service, prisma, erp } = createHarness();
    erp.lookupOrder.mockResolvedValueOnce({
      ...erpOrderFixture(),
      creatorEmail: 'erp.owner@phongvu.vn',
      creatorName: 'ERP Owner',
    });

    await service.create(userFixture(), {
      ...baseInput(),
      reportType: 'PURCHASED',
      orderCode: '2606290001',
      entrySource: 'COMEBACK',
    });

    expect(prisma.salesReport.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          createdByEmail: 'erp.owner@phongvu.vn',
          createdByName: 'ERP Owner',
          submittedByUserId: 'user-1',
          submittedByEmail: 'sale@phongvu.vn',
          entrySource: 'COMEBACK',
        }),
      }),
    );
  });

  it('returns ERP autofill hints when checking a purchased order', async () => {
    const { service, erp } = createHarness();
    erp.lookupOrder.mockResolvedValueOnce({
      ...erpOrderFixture(),
      customerType: 'PERSONAL',
      customerIsStudent: true,
      promotionCodes: ['EXAM_SCORE_EXCHANGE', 'STUDENT'],
      installmentNeed: true,
      installmentLoanAmount: 5000000,
    });

    await expect(
      service.checkOrder(userFixture(), '2606290001'),
    ).resolves.toMatchObject({
      customerType: 'PERSONAL',
      customerIsStudent: true,
      promotionCodes: ['EXAM_SCORE_EXCHANGE', 'STUDENT'],
      installmentNeed: true,
      installmentLoanAmount: 5000000,
    });
  });

  it('lets a user ERP detail check persist a partial return after background quota is exhausted', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-07-14T02:00:00Z'));
    const { service, prisma, erp } = createHarness();
    prisma.salesReportErpOrderCache.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({
        lifecycleStatus: 'PENDING',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
        paymentStatus: 'fully_paid',
        confirmationStatus: 'active',
        fulfillmentStatus: 'PROCESSING',
        statusCheckedAt: new Date('2026-07-14T01:00:00Z'),
        statusCheckAttemptedAt: new Date('2026-07-14T01:30:00Z'),
        statusCheckAttemptDate: new Date('2026-07-14T00:00:00Z'),
        statusCheckAttemptCount: 5,
        statusCheckFailureCount: 0,
        sanitizedSnapshot: { orderId: '2606290001' },
      });
    erp.lookupOrder.mockResolvedValueOnce({
      ...erpOrderFixture(),
      erpLifecycleStatus: 'COMPLETED_PARTIAL_RETURN',
      erpHasReturnedFullItems: false,
      erpReturnedAfterTaxAmount: 250000,
      erpStatusCheckedAt: new Date('2026-07-14T02:00:00Z'),
    });

    try {
      await expect(
        service.checkOrder(userFixture(), '2606290001'),
      ).resolves.toMatchObject({ orderCode: '2606290001' });
      expect(erp.lookupOrder).toHaveBeenCalledTimes(1);
      expect(erp.lookupOrderStatus).not.toHaveBeenCalled();
      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2606290001' },
          update: expect.objectContaining({
            lifecycleStatus: 'COMPLETED_PARTIAL_RETURN',
            returnedAfterTaxAmount: 250000,
            statusCheckAttemptDate: new Date('2026-07-14T00:00:00Z'),
            statusCheckAttemptCount: 5,
          }),
        }),
      );
      expect(prisma.salesReport.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2606290001', reportType: 'PURCHASED' },
          data: expect.objectContaining({
            erpLifecycleStatus: 'COMPLETED_PARTIAL_RETURN',
            erpReturnedAfterTaxAmount: 250000,
          }),
        }),
      );
    } finally {
      jest.useRealTimers();
    }
  });

  it('does not autofill the parent Accessories group for a gift item', async () => {
    const { service, categories, erp } = createHarness();
    const baseOrder = erpOrderFixture();
    const laptopItem = {
      ...baseOrder.items[0],
      sku: 'LAPTOP-1',
      sellerSku: 'LAPTOP-1',
      name: 'Laptop HP',
      listingCategories: [
        { code: 'NH01', name: 'Laptop', level: 1 },
        { code: 'NH01-01-01-01', name: 'Laptop', level: 4 },
      ],
    };
    const giftItem = {
      ...baseOrder.items[0],
      sku: '231000787',
      sellerSku: '231000787',
      name: 'Túi dệt PP Phong Vũ (55x18x40)',
      listingCategories: [
        { code: 'NH11', name: 'Accessories', level: 1 },
        {
          code: 'NH11-01-98-01',
          name: 'Linh kiện (Quà tặng phụ kiện máy tính)',
          level: 4,
        },
      ],
    };
    categories.matchDeepestListingCategory.mockImplementation(
      async (listingCategories: Array<{ code?: string }>) => {
        const gift = listingCategories.some((category) =>
          category.code?.startsWith('NH11-01-98'),
        );
        return {
          categoryType: gift ? 'gift' : 'laptop',
          categoryGroup: {
            id: gift ? 'NH11' : 'NH01',
            catGroupName: gift ? 'Accessories' : 'Laptop',
            catGroupNameVi: gift ? 'Phụ kiện' : 'Laptop',
          },
          sourceLevel: 4,
        };
      },
    );
    erp.lookupOrder.mockResolvedValueOnce({
      ...baseOrder,
      orderCode: '26071137825630',
      erpOrderId: '26071137825630',
      items: [laptopItem, giftItem],
    });

    const result = await service.checkOrder(userFixture(), '26071137825630');

    expect(categories.matchDeepestListingCategory).toHaveBeenCalledTimes(2);
    expect(result.categoryGroups).toEqual([
      expect.objectContaining({ id: 'NH01' }),
    ]);
    expect(result.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ sku: '231000787', categoryType: 'gift' }),
      ]),
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
          statusCheckAttemptDate: expect.any(Date),
          statusCheckAttemptCount: 1,
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

  it('persists and blocks zero-value ERP orders after ERP lookup', async () => {
    const { service, prisma, erp } = createHarness();
    erp.lookupOrder.mockResolvedValueOnce({
      ...erpOrderFixture(),
      orderCode: '2607070000',
      erpOrderId: '2607070000',
      erpGrandTotal: 0,
      sanitizedSnapshot: { orderId: '2607070000', grandTotal: 0 },
    });

    await expect(
      service.checkOrder(userFixture(), '2607070000'),
    ).rejects.toThrow('Đơn 0 VND là đơn vận hành nội bộ, không cần báo cáo.');

    expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { orderCode: '2607070000' },
        create: expect.objectContaining({
          orderCode: '2607070000',
          grandTotal: 0,
          exclusionReason: 'ERP_ORDER_ZERO_VALUE_INTERNAL',
          excludedAt: expect.any(Date),
        }),
      }),
    );
    expect(prisma.salesReport.updateMany).toHaveBeenCalledWith({
      where: { orderCode: '2607070000' },
      data: {
        erpExcludedAt: expect.any(Date),
        erpExclusionReason: 'ERP_ORDER_ZERO_VALUE_INTERNAL',
      },
    });
  });

  it('uses ERP createdFromSiteDisplayName as the cache store source when checking an order', async () => {
    const { service, prisma, erp } = createHarness();
    const noStoreUser = {
      id: 'admin-user',
      email: 'admin@hoanghochoi.com',
      firstName: 'Admin',
      lastName: 'User',
      jobRoleCode: 'SA',
      store: null,
      organizationNode: null,
      organizationAssignments: [],
    };
    prisma.user.findUnique.mockResolvedValueOnce(noStoreUser);
    erp.lookupOrder.mockResolvedValueOnce({
      ...erpOrderFixture(),
      orderCode: '26070732198240',
      erpOrderId: '26070732198240',
      erpTerminalName:
        'ĐỊA ĐIỂM KINH DOANH 52 - CÔNG TY CỔ PHẦN THƯƠNG MẠI - DỊCH VỤ PHONG VŨ',
      sanitizedSnapshot: {
        ...erpOrderFixture().sanitizedSnapshot,
        orderId: '26070732198240',
        createdFromSiteDisplayName:
          '[CP58] ĐỊA ĐIỂM KINH DOANH 52 - CÔNG TY CỔ PHẦN THƯƠNG MẠI - DỊCH VỤ PHONG VŨ',
      },
    });

    await service.checkOrder(noStoreUser, '26070732198240');

    expect(erp.lookupOrder).toHaveBeenCalledWith('26070732198240', null);
    expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { orderCode: '26070732198240' },
        create: expect.objectContaining({
          orderCode: '26070732198240',
          storeCode: 'CP58',
          sourceUserEmail: 'admin@hoanghochoi.com',
        }),
        update: expect.objectContaining({
          storeCode: 'CP58',
          sourceUserEmail: 'admin@hoanghochoi.com',
        }),
      }),
    );
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
    prisma.salesReportErpOrderCache.findMany
      .mockResolvedValueOnce([erpOrderCacheFixture('2607010002')])
      .mockResolvedValueOnce([erpOrderCacheFixture('2607010002')]);

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
      prisma.salesReportErpOrderCache.findMany.mock.calls[1][0];
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

  it('maps manual purchased reports to cached cockpit orders by order code', async () => {
    const { service, prisma } = createHarness();
    const manager = storeManagerFixture('CP67');
    prisma.user.findUnique.mockResolvedValue(manager);
    const cachedOrder = {
      ...erpOrderCacheFixture('2607077777'),
      storeCode: 'CP67',
      storeName: 'CP67',
      consultantEmail: 'sale.cp67@phongvu.vn',
      sourceUserEmail: 'sale.cp67@phongvu.vn',
      orderCreatedAt: new Date('2026-07-07T02:00:00Z'),
    };
    const manualReport = {
      ...exportReportFixture(),
      orderCode: '2607077777',
      storeCode: 'CP46',
      storeName: 'CP46',
      erpOrderCreatedAt: new Date('2026-07-06T02:00:00Z'),
      submittedAt: new Date('2026-07-08T02:00:00Z'),
    };
    prisma.salesReport.count.mockResolvedValueOnce(1);
    prisma.salesReportErpOrderCache.count.mockResolvedValueOnce(0);
    prisma.salesReport.findMany
      .mockResolvedValueOnce([{ orderCode: '2607077777' }])
      .mockResolvedValueOnce([manualReport])
      .mockResolvedValueOnce([]);
    prisma.salesReportErpOrderCache.findMany
      .mockResolvedValueOnce([cachedOrder])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([cachedOrder]);

    const result = await service.orderCockpit(
      { id: manager.id, email: manager.email, role: 'USER' },
      { date: '2026-07-07', storeCode: 'CP67' },
    );

    expect(result.reportedOrders).toHaveLength(1);
    expect(result.reportedOrders[0].orderCode).toBe('2607077777');
    expect(result.unreportedOrders).toHaveLength(0);
    const reportedCodeWhere = JSON.stringify(
      prisma.salesReport.findMany.mock.calls[0][0].where,
    );
    const reportedListWhere = JSON.stringify(
      prisma.salesReport.findMany.mock.calls[1][0].where,
    );
    expect(reportedCodeWhere).toContain('"in":["2607077777"]');
    expect(reportedListWhere).toContain('"in":["2607077777"]');
    expect(
      JSON.stringify(
        prisma.salesReportErpOrderCache.count.mock.calls[0][0].where,
      ),
    ).toContain('"notIn":["2607077777"]');
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
    prisma.salesReportErpOrderCache.findMany
      .mockResolvedValueOnce([erpOrderCacheFixture('2607010002')])
      .mockResolvedValueOnce([erpOrderCacheFixture('2607010002')]);

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
      prisma.salesReportErpOrderCache.findMany.mock.calls[1][0];
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
    prisma.salesReportErpOrderCache.findMany
      .mockResolvedValueOnce([
        { ...erpOrderCacheFixture('2607010003'), storeCode: 'CP01' },
      ])
      .mockResolvedValueOnce([
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
      prisma.salesReportErpOrderCache.findMany.mock.calls[1][0];
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
    const order = erpListOrderFixture();
    erp.listRecentOrders.mockResolvedValueOnce([
      {
        ...order,
        sanitizedSnapshot: {
          ...order.sanitizedSnapshot,
          createdFromSiteDisplayName:
            '[CP62] ĐỊA ĐIỂM KINH DOANH 02 - CÔNG TY CỔ PHẦN THƯƠNG MẠI - DỊCH VỤ PHONG VŨ',
        },
      },
    ]);

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
            orderCreatedAt: new Date('2026-07-01T01:00:00Z'),
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

  it('backfills cached order date from ERP snapshot instead of using fetch time', async () => {
    const { service, prisma, erp } = createHarness();
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    const oldLookback = process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
    delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = '1';
    erp.listRecentOrders.mockResolvedValueOnce([
      {
        ...erpListOrderFixture(),
        orderCode: '26070337539840',
        orderCreatedAt: null,
        fetchedAt: new Date('2026-07-11T12:55:08Z'),
        storeCode: 'CP75',
        storeName: null,
        grandTotal: 60400000,
        sanitizedSnapshot: {
          orderCode: '26070337539840',
          createdAt: '2026-07-03T09:43:34Z',
          createdFromSiteDisplayName:
            '[CP75] ĐỊA ĐIỂM KINH DOANH 63 - CÔNG TY CỔ PHẦN THƯƠNG MẠI - DỊCH VỤ PHONG VŨ',
        },
      },
    ]);
    prisma.salesReportErpOrderCache.findMany.mockResolvedValueOnce([]);

    try {
      await service.syncScheduledErpOrderCache('test-snapshot-date');

      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '26070337539840' },
          create: expect.objectContaining({
            orderCreatedAt: new Date('2026-07-03T09:43:34Z'),
            fetchedAt: new Date('2026-07-11T12:55:08Z'),
            storeCode: 'CP75',
          }),
          update: expect.objectContaining({
            orderCreatedAt: new Date('2026-07-03T09:43:34Z'),
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

  it('keeps pending status retry metadata when list sync refreshes the row', async () => {
    const { service, prisma, erp } = createHarness();
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    const oldLookback = process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
    delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = '1';
    const attemptedAt = new Date('2026-07-07T01:10:00Z');
    const listCheckedAt = new Date('2026-07-07T01:20:00Z');
    erp.listRecentOrders.mockResolvedValueOnce([
      {
        ...erpListOrderFixture(),
        lifecycleStatus: 'PENDING',
        paymentStatus: 'pending_payment',
        statusCheckedAt: listCheckedAt,
        fetchedAt: listCheckedAt,
      },
    ]);
    prisma.salesReportErpOrderCache.findMany.mockResolvedValueOnce([
      {
        orderCode: '2607010002',
        paymentStatus: 'fully_paid',
        confirmationStatus: 'active',
        fulfillmentStatus: 'PROCESSING',
        lifecycleStatus: 'PENDING',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
        statusCheckedAt: new Date('2026-07-07T01:00:00Z'),
        statusCheckAttemptedAt: attemptedAt,
        statusCheckAttemptDate: new Date('2026-07-07T00:00:00Z'),
        statusCheckAttemptCount: 2,
        statusCheckFailureCount: 2,
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
      await service.syncScheduledErpOrderCache('test-preserve-pending-retry');

      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607010002' },
          update: expect.objectContaining({
            lifecycleStatus: 'PENDING',
            paymentStatus: 'pending_payment',
            statusCheckedAt: listCheckedAt,
            statusCheckAttemptedAt: attemptedAt,
            statusCheckAttemptDate: new Date('2026-07-07T00:00:00Z'),
            statusCheckAttemptCount: 2,
            statusCheckFailureCount: 2,
          }),
        }),
      );
      expect(prisma.salesReport.updateMany).toHaveBeenCalledWith({
        where: { orderCode: '2607010002', reportType: 'PURCHASED' },
        data: expect.objectContaining({
          erpLifecycleStatus: 'PENDING',
          erpStatusCheckedAt: listCheckedAt,
          erpStatusCheckAttemptedAt: attemptedAt,
          erpStatusCheckAttemptDate: new Date('2026-07-07T00:00:00Z'),
          erpStatusCheckAttemptCount: 2,
          erpStatusCheckFailureCount: 2,
        }),
      });
      expect(
        prisma.salesReportErpOrderCache.upsert.mock.calls[0][0].update,
      ).not.toHaveProperty('excludedAt');
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

  it('scheduled sync excludes zero-value ERP orders without counting them as reportable new orders', async () => {
    const { service, prisma, erp } = createHarness();
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    const oldLookback = process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
    delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = '1';
    erp.listRecentOrders.mockResolvedValueOnce([
      {
        ...erpListOrderFixture(),
        orderCode: '2607070000',
        erpOrderId: '2607070000',
        grandTotal: 0,
        sanitizedSnapshot: { orderCode: '2607070000', grandTotal: 0 },
      },
    ]);

    try {
      const result = await service.syncScheduledErpOrderCache('test-zero');

      expect(result).toMatchObject({
        count: 1,
        newOrderCount: 0,
        excludedOrderCount: 1,
      });
      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607070000' },
          create: expect.objectContaining({
            orderCode: '2607070000',
            grandTotal: 0,
            exclusionReason: 'ERP_ORDER_ZERO_VALUE_INTERNAL',
            excludedAt: expect.any(Date),
          }),
        }),
      );
      expect(prisma.salesReport.updateMany).toHaveBeenCalledWith({
        where: { orderCode: '2607070000' },
        data: {
          erpExcludedAt: expect.any(Date),
          erpExclusionReason: 'ERP_ORDER_ZERO_VALUE_INTERNAL',
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

  it('maps the ERP creator to the source user without using the owner store during scheduled sync', async () => {
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
            storeCode: null,
            storeName: null,
            organizationNodeId: null,
          }),
          update: expect.objectContaining({
            sourceUserId: 'sale-cp01',
            sourceUserEmail: 'sale.cp01@phongvu.vn',
            storeCode: null,
            storeName: null,
            organizationNodeId: null,
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

  it('does not map a store from siteDisplayName or owner during scheduled sync', async () => {
    const { service, prisma, erp } = createHarness();
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    const oldLookback = process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
    delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = '1';
    erp.listRecentOrders.mockResolvedValueOnce([
      {
        ...erpListOrderFixture(),
        orderCode: '26071132604790',
        storeCode: null,
        storeName: null,
        consultantEmail: 'hoang.nv1@phongvu-mna.vn',
        sellerEmail: 'hoang.nv1@phongvu-mna.vn',
        sanitizedSnapshot: {
          orderCode: '26071132604790',
          createdFromSiteDisplayName: null,
          siteDisplayName:
            '[CP72] ĐỊA ĐIỂM KINH DOANH 60 - CÔNG TY CỔ PHẦN THƯƠNG MẠI - DỊCH VỤ PHONG VŨ',
        },
      },
    ]);
    prisma.user.findMany.mockResolvedValueOnce([
      {
        id: 'manager-cp75',
        email: 'hoang.nv1@phongvu-mna.vn',
        store: {
          storeId: 'CP75',
          storeName: 'Phong Vu CP75',
          organizationNodeId: 'node-cp75',
        },
        organizationNode: null,
        organizationAssignments: [],
      },
    ]);
    try {
      await service.syncScheduledErpOrderCache('test-site-display-store');

      expect(prisma.store.findMany).not.toHaveBeenCalled();
      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '26071132604790' },
          create: expect.objectContaining({
            sourceUserId: 'manager-cp75',
            sourceUserEmail: 'hoang.nv1@phongvu-mna.vn',
            storeCode: null,
            storeName: null,
            organizationNodeId: null,
          }),
          update: expect.objectContaining({
            sourceUserId: 'manager-cp75',
            sourceUserEmail: 'hoang.nv1@phongvu-mna.vn',
            storeCode: null,
            storeName: null,
            organizationNodeId: null,
          }),
        }),
      );
      expect(
        prisma.salesReportErpOrderCache.upsert.mock.calls[0][0].create
          .storeCode,
      ).toBeNull();
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

  it('does not backfill store scope from an existing mapped user during scheduled sync', async () => {
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
        mappedOrderCount: 0,
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
            storeCode: null,
            storeName: null,
            organizationNodeId: null,
          }),
        }),
      );
      expect(redis.publishMessage).not.toHaveBeenCalled();
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

  it('clears cache store mapping when createdFromSiteDisplayName is missing', async () => {
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
      expect(upsert.update).toEqual(
        expect.objectContaining({
          storeCode: null,
          storeName: null,
          organizationNodeId: null,
        }),
      );
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

  it('does not overwrite a createdFromSiteDisplayName store source with weaker owner mapping', async () => {
    const { service, prisma, erp } = createHarness();
    const oldEnabled = process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    const oldLookback = process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS;
    delete process.env.ERP_ORDER_CACHE_SYNC_ENABLED;
    process.env.ERP_ORDER_CACHE_SYNC_LOOKBACK_DAYS = '1';
    erp.listRecentOrders.mockResolvedValueOnce([
      {
        ...erpListOrderFixture(),
        orderCode: '26070732198240',
        storeCode: null,
        storeName: null,
        consultantEmail: null,
        sellerEmail: null,
        sanitizedSnapshot: {
          orderCode: '26070732198240',
        },
      },
    ]);
    prisma.salesReportErpOrderCache.findMany.mockResolvedValueOnce([
      {
        orderCode: '26070732198240',
        sanitizedSnapshot: {
          orderCode: '26070732198240',
          createdFromSiteDisplayName:
            '[CP58] ĐỊA ĐIỂM KINH DOANH 52 - CÔNG TY CỔ PHẦN THƯƠNG MẠI - DỊCH VỤ PHONG VŨ',
        },
        consultantEmail: null,
        sellerEmail: null,
        storeCode: 'CP58',
        organizationNodeId: null,
        sourceUserId: 'sale-cp62',
        sourceUserEmail: 'sale@phongvu.vn',
      },
    ]);
    prisma.user.findMany.mockResolvedValueOnce([
      {
        id: 'sale-cp62',
        email: 'sale@phongvu.vn',
        store: {
          storeId: 'CP62',
          storeName: 'Phong Vu CP62',
          organizationNodeId: 'node-cp62',
        },
        organizationNode: null,
        organizationAssignments: [],
      },
    ]);

    try {
      await service.syncScheduledErpOrderCache('test-preserve-created-site');

      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '26070732198240' },
          update: expect.objectContaining({
            storeCode: 'CP58',
          }),
        }),
      );
      expect(
        prisma.salesReportErpOrderCache.upsert.mock.calls[0][0].update
          .storeCode,
      ).not.toBe('CP62');
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
      cache: process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED,
      batch: process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE,
      concurrency: process.env.ERP_ORDER_STATUS_SYNC_CONCURRENCY,
      storeLimit: process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED = 'false';
    process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE = '50';
    process.env.ERP_ORDER_STATUS_SYNC_CONCURRENCY = '2';
    process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT = '50';
    const recentOrderDate = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const row = (index: number, lifecycleStatus: string) => ({
      orderCode: String(2607012000 + index),
      storeCode: 'CP62',
      erpLifecycleStatus: lifecycleStatus,
      erpStatusCheckedAt: new Date(recentOrderDate),
      erpOrderCreatedAt: new Date(recentOrderDate),
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
      restoreEnv('ERP_ORDER_STATUS_CACHE_SYNC_ENABLED', previous.cache);
      restoreEnv('ERP_ORDER_STATUS_SYNC_BATCH_SIZE', previous.batch);
      restoreEnv('ERP_ORDER_STATUS_SYNC_CONCURRENCY', previous.concurrency);
      restoreEnv('ERP_ORDER_STATUS_SYNC_STORE_LIMIT', previous.storeLimit);
    }
  });

  it('syncs pending cache order statuses with per-store quota', async () => {
    const { service, prisma, erp } = createHarness();
    const previous = {
      enabled: process.env.ERP_ORDER_STATUS_SYNC_ENABLED,
      cache: process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED,
      batch: process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE,
      storeLimit: process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE = '5';
    process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT = '2';
    const cacheRow = (orderCode: string) => ({
      orderCode,
      storeCode: 'CP62',
      lifecycleStatus: 'PENDING',
      statusCheckedAt: new Date('2026-07-07T01:00:00Z'),
      statusCheckAttemptedAt: null,
      statusCheckFailureCount: 0,
      orderCreatedAt: new Date('2026-07-07T00:30:00Z'),
    });
    prisma.salesReportErpOrderCache.findMany
      .mockResolvedValueOnce([
        cacheRow('2607071001'),
        cacheRow('2607071002'),
        cacheRow('2607071003'),
      ])
      .mockResolvedValueOnce([]);
    prisma.salesReport.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    erp.lookupOrderStatus.mockImplementation(async (orderCode: string) => ({
      ...erpListOrderFixture(),
      orderCode,
      lifecycleStatus: 'COMPLETED',
      hasReturnedFullItems: false,
      returnedAfterTaxAmount: 0,
      statusCheckedAt: new Date('2026-07-07T02:00:00Z'),
    }));

    try {
      await expect(service.syncErpOrderStatuses('test')).resolves.toEqual({
        skipped: false,
        processed: 2,
        changed: 2,
        failed: 0,
      });
      expect(erp.lookupOrderStatus).toHaveBeenCalledTimes(2);
      expect(erp.lookupOrderStatus).toHaveBeenNthCalledWith(
        1,
        '2607071001',
        'CP62',
      );
      expect(erp.lookupOrderStatus).toHaveBeenNthCalledWith(
        2,
        '2607071002',
        'CP62',
      );
      expect(prisma.salesReportErpOrderCache.findMany).toHaveBeenNthCalledWith(
        1,
        expect.objectContaining({
          where: expect.objectContaining({
            lifecycleStatus: 'PENDING',
          }),
          take: 20,
        }),
      );
    } finally {
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous.enabled);
      restoreEnv('ERP_ORDER_STATUS_CACHE_SYNC_ENABLED', previous.cache);
      restoreEnv('ERP_ORDER_STATUS_SYNC_BATCH_SIZE', previous.batch);
      restoreEnv('ERP_ORDER_STATUS_SYNC_STORE_LIMIT', previous.storeLimit);
    }
  });

  it('uses the one-hour default pending status re-check window', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-07-07T01:06:00Z'));
    const { service, prisma, erp } = createHarness();
    const previous = {
      enabled: process.env.ERP_ORDER_STATUS_SYNC_ENABLED,
      cache: process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED,
      batch: process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE,
      storeLimit: process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT,
      pending: process.env.ERP_ORDER_STATUS_PENDING_RECHECK_MINUTES,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE = '5';
    process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT = '5';
    delete process.env.ERP_ORDER_STATUS_PENDING_RECHECK_MINUTES;
    const pendingRow = {
      orderCode: '2607071001',
      storeCode: 'CP62',
      lifecycleStatus: 'PENDING',
      statusCheckedAt: new Date('2026-07-07T01:00:00Z'),
      statusCheckAttemptedAt: new Date('2026-07-07T01:00:30Z'),
      statusCheckAttemptDate: new Date('2026-07-07T00:00:00Z'),
      statusCheckAttemptCount: 1,
      statusCheckFailureCount: 0,
      orderCreatedAt: new Date('2026-07-06T21:00:00Z'),
      fetchedAt: new Date('2026-07-06T21:00:00Z'),
    };
    prisma.salesReportErpOrderCache.findMany.mockImplementation(
      async ({ where }: any) =>
        where.lifecycleStatus === 'PENDING' ? [pendingRow] : [],
    );
    prisma.salesReport.findMany.mockResolvedValue([]);
    erp.lookupOrderStatus.mockResolvedValue({
      ...erpListOrderFixture(),
      orderCode: '2607071001',
      lifecycleStatus: 'COMPLETED',
      hasReturnedFullItems: false,
      returnedAfterTaxAmount: 0,
      statusCheckedAt: new Date('2026-07-07T02:01:00Z'),
    });

    try {
      await expect(
        service.syncErpOrderStatuses('before-one-hour'),
      ).resolves.toEqual({
        skipped: false,
        processed: 0,
        changed: 0,
        failed: 0,
      });
      expect(erp.lookupOrderStatus).not.toHaveBeenCalled();

      jest.setSystemTime(new Date('2026-07-07T02:01:00Z'));
      await expect(service.syncErpOrderStatuses('test')).resolves.toEqual({
        skipped: false,
        processed: 1,
        changed: 1,
        failed: 0,
      });
      expect(erp.lookupOrderStatus).toHaveBeenCalledWith('2607071001', 'CP62');
    } finally {
      jest.useRealTimers();
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous.enabled);
      restoreEnv('ERP_ORDER_STATUS_CACHE_SYNC_ENABLED', previous.cache);
      restoreEnv('ERP_ORDER_STATUS_SYNC_BATCH_SIZE', previous.batch);
      restoreEnv('ERP_ORDER_STATUS_SYNC_STORE_LIMIT', previous.storeLimit);
      restoreEnv('ERP_ORDER_STATUS_PENDING_RECHECK_MINUTES', previous.pending);
    }
  });

  it('waits three hours from order creation before syncing pending status', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-07-07T05:00:00Z'));
    const { service, prisma, erp } = createHarness();
    const previous = {
      enabled: process.env.ERP_ORDER_STATUS_SYNC_ENABLED,
      cache: process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED,
      batch: process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE,
      storeLimit: process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE = '5';
    process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT = '5';
    const pendingRow = {
      orderCode: '2607071059',
      storeCode: 'CP62',
      lifecycleStatus: 'PENDING',
      statusCheckedAt: new Date('2026-07-07T02:01:00Z'),
      statusCheckAttemptedAt: null,
      statusCheckAttemptDate: null,
      statusCheckAttemptCount: 0,
      statusCheckFailureCount: 0,
      orderCreatedAt: new Date('2026-07-07T02:01:00Z'),
      fetchedAt: new Date('2026-07-07T02:01:00Z'),
    };
    prisma.salesReportErpOrderCache.findMany.mockImplementation(
      async ({ where }: any) =>
        where.lifecycleStatus === 'PENDING' ? [pendingRow] : [],
    );
    prisma.salesReport.findMany.mockResolvedValue([]);
    erp.lookupOrderStatus.mockResolvedValue({
      ...erpListOrderFixture(),
      orderCode: pendingRow.orderCode,
      lifecycleStatus: 'COMPLETED',
      hasReturnedFullItems: false,
      returnedAfterTaxAmount: 0,
      statusCheckedAt: new Date('2026-07-07T05:01:00Z'),
    });

    try {
      await expect(
        service.syncErpOrderStatuses('before-three-hours'),
      ).resolves.toEqual({
        skipped: false,
        processed: 0,
        changed: 0,
        failed: 0,
      });
      expect(erp.lookupOrderStatus).not.toHaveBeenCalled();
      expect(prisma.salesReportErpOrderCache.findMany).toHaveBeenNthCalledWith(
        1,
        expect.objectContaining({
          where: expect.objectContaining({
            lifecycleStatus: 'PENDING',
            AND: expect.arrayContaining([
              { orderCreatedAt: { lte: new Date('2026-07-07T02:00:00Z') } },
            ]),
          }),
        }),
      );
      expect(prisma.salesReport.findMany).toHaveBeenNthCalledWith(
        1,
        expect.objectContaining({
          where: expect.objectContaining({
            erpLifecycleStatus: 'PENDING',
            erpOrderCreatedAt: {
              lte: new Date('2026-07-07T02:00:00Z'),
            },
          }),
        }),
      );

      jest.setSystemTime(new Date('2026-07-07T05:01:00Z'));
      await expect(
        service.syncErpOrderStatuses('at-three-hours'),
      ).resolves.toEqual({
        skipped: false,
        processed: 1,
        changed: 1,
        failed: 0,
      });
      expect(erp.lookupOrderStatus).toHaveBeenCalledWith(
        pendingRow.orderCode,
        'CP62',
      );
    } finally {
      jest.useRealTimers();
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous.enabled);
      restoreEnv('ERP_ORDER_STATUS_CACHE_SYNC_ENABLED', previous.cache);
      restoreEnv('ERP_ORDER_STATUS_SYNC_BATCH_SIZE', previous.batch);
      restoreEnv('ERP_ORDER_STATUS_SYNC_STORE_LIMIT', previous.storeLimit);
    }
  });

  it('caps pending background checks at three per Vietnam day and resets next day', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-07-07T02:00:00Z'));
    const { service, prisma, erp } = createHarness();
    const previous = {
      enabled: process.env.ERP_ORDER_STATUS_SYNC_ENABLED,
      cache: process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED,
      batch: process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE,
      storeLimit: process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE = '5';
    process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT = '5';
    const exhaustedPending = {
      orderCode: '2607071101',
      storeCode: 'CP62',
      lifecycleStatus: 'PENDING',
      statusCheckedAt: new Date('2026-07-07T01:00:00Z'),
      statusCheckAttemptedAt: new Date('2026-07-07T01:50:00Z'),
      statusCheckAttemptDate: new Date('2026-07-07T00:00:00Z'),
      statusCheckAttemptCount: 3,
      statusCheckFailureCount: 0,
      orderCreatedAt: new Date('2026-07-06T20:30:00Z'),
      fetchedAt: new Date('2026-07-06T20:30:00Z'),
    };
    prisma.salesReportErpOrderCache.findMany
      .mockResolvedValueOnce([exhaustedPending])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([exhaustedPending])
      .mockResolvedValueOnce([]);
    prisma.salesReport.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    erp.lookupOrderStatus.mockImplementation(async (orderCode: string) => ({
      ...erpListOrderFixture(),
      orderCode,
      lifecycleStatus: 'COMPLETED',
      hasReturnedFullItems: false,
      returnedAfterTaxAmount: 0,
      statusCheckedAt: new Date(),
    }));

    try {
      await expect(service.syncErpOrderStatuses('same-day')).resolves.toEqual({
        skipped: false,
        processed: 0,
        changed: 0,
        failed: 0,
      });
      expect(erp.lookupOrderStatus).not.toHaveBeenCalled();

      jest.setSystemTime(new Date('2026-07-07T17:01:00Z'));
      await expect(service.syncErpOrderStatuses('next-day')).resolves.toEqual({
        skipped: false,
        processed: 1,
        changed: 1,
        failed: 0,
      });
      expect(erp.lookupOrderStatus).toHaveBeenCalledTimes(1);
      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607071101' },
          update: expect.objectContaining({
            statusCheckAttemptDate: new Date('2026-07-08T00:00:00Z'),
            statusCheckAttemptCount: 1,
          }),
        }),
      );
    } finally {
      jest.useRealTimers();
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous.enabled);
      restoreEnv('ERP_ORDER_STATUS_CACHE_SYNC_ENABLED', previous.cache);
      restoreEnv('ERP_ORDER_STATUS_SYNC_BATCH_SIZE', previous.batch);
      restoreEnv('ERP_ORDER_STATUS_SYNC_STORE_LIMIT', previous.storeLimit);
    }
  });

  it('uses a pending-to-completed lookup as the completed check for two days', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-07-07T02:00:00Z'));
    const { service, prisma, erp } = createHarness();
    const previous = {
      enabled: process.env.ERP_ORDER_STATUS_SYNC_ENABLED,
      cache: process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED,
      batch: process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE,
      storeLimit: process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE = '5';
    process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT = '5';
    const pendingRow = {
      orderCode: '2607071102',
      storeCode: 'CP62',
      lifecycleStatus: 'PENDING',
      statusCheckedAt: new Date('2026-07-07T00:30:00Z'),
      statusCheckAttemptedAt: new Date('2026-07-07T01:00:00Z'),
      statusCheckAttemptDate: new Date('2026-07-07T00:00:00Z'),
      statusCheckAttemptCount: 1,
      statusCheckFailureCount: 0,
      orderCreatedAt: new Date('2026-07-06T20:30:00Z'),
      fetchedAt: new Date('2026-07-06T20:30:00Z'),
    };
    const completedRow = {
      ...pendingRow,
      lifecycleStatus: 'COMPLETED',
      statusCheckAttemptedAt: new Date('2026-07-07T02:00:00Z'),
      statusCheckAttemptCount: 2,
    };
    let pendingAvailable = true;
    let completedAvailable = false;
    prisma.salesReportErpOrderCache.findMany.mockImplementation(
      async ({ where }: any) => {
        if (where.lifecycleStatus === 'PENDING') {
          if (!pendingAvailable) return [];
          pendingAvailable = false;
          return [pendingRow];
        }
        return completedAvailable ? [completedRow] : [];
      },
    );
    prisma.salesReport.findMany.mockResolvedValue([]);

    try {
      await expect(service.syncErpOrderStatuses('transition')).resolves.toEqual(
        {
          skipped: false,
          processed: 1,
          changed: 1,
          failed: 0,
        },
      );
      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          update: expect.objectContaining({
            lifecycleStatus: 'COMPLETED',
            statusCheckAttemptDate: new Date('2026-07-07T00:00:00Z'),
            statusCheckAttemptCount: 2,
          }),
        }),
      );
      completedAvailable = true;

      await expect(service.syncErpOrderStatuses('same-day')).resolves.toEqual({
        skipped: false,
        processed: 0,
        changed: 0,
        failed: 0,
      });
      expect(erp.lookupOrderStatus).toHaveBeenCalledTimes(1);

      jest.setSystemTime(new Date('2026-07-08T02:00:00Z'));
      await expect(service.syncErpOrderStatuses('next-day')).resolves.toEqual({
        skipped: false,
        processed: 0,
        changed: 0,
        failed: 0,
      });
      expect(erp.lookupOrderStatus).toHaveBeenCalledTimes(1);

      jest.setSystemTime(new Date('2026-07-09T02:00:00Z'));
      await expect(
        service.syncErpOrderStatuses('two-days-later'),
      ).resolves.toEqual({
        skipped: false,
        processed: 1,
        changed: 0,
        failed: 0,
      });
      expect(erp.lookupOrderStatus).toHaveBeenCalledTimes(2);
    } finally {
      jest.useRealTimers();
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous.enabled);
      restoreEnv('ERP_ORDER_STATUS_CACHE_SYNC_ENABLED', previous.cache);
      restoreEnv('ERP_ORDER_STATUS_SYNC_BATCH_SIZE', previous.batch);
      restoreEnv('ERP_ORDER_STATUS_SYNC_STORE_LIMIT', previous.storeLimit);
    }
  });

  it('prioritizes the newest sale date for pending and completed candidates', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-07-10T02:00:00Z'));
    const { service, prisma, erp } = createHarness();
    const previous = {
      enabled: process.env.ERP_ORDER_STATUS_SYNC_ENABLED,
      cache: process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED,
      batch: process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE,
      storeLimit: process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_SYNC_BATCH_SIZE = '4';
    process.env.ERP_ORDER_STATUS_SYNC_STORE_LIMIT = '5';
    const cacheRow = (
      orderCode: string,
      lifecycleStatus: string,
      orderCreatedAt: string,
    ) => ({
      orderCode,
      storeCode: 'CP62',
      lifecycleStatus,
      statusCheckedAt: null,
      statusCheckAttemptedAt: null,
      statusCheckAttemptDate: null,
      statusCheckAttemptCount: 0,
      statusCheckFailureCount: 0,
      orderCreatedAt: new Date(orderCreatedAt),
      fetchedAt: new Date(orderCreatedAt),
    });
    const pendingRecent = cacheRow(
      '2607092001',
      'PENDING',
      '2026-07-09T04:00:00Z',
    );
    const pendingOld = cacheRow(
      '2607082001',
      'PENDING',
      '2026-07-08T04:00:00Z',
    );
    const completedRecent = cacheRow(
      '2607093001',
      'COMPLETED',
      '2026-07-09T03:00:00Z',
    );
    const completedOld = cacheRow(
      '2607083001',
      'COMPLETED',
      '2026-07-08T03:00:00Z',
    );
    prisma.salesReportErpOrderCache.findMany
      .mockResolvedValueOnce([pendingRecent, pendingOld])
      .mockResolvedValueOnce([completedRecent, completedOld]);
    prisma.salesReport.findMany.mockResolvedValue([]);
    erp.lookupOrderStatus.mockImplementation(async (orderCode: string) => ({
      ...erpListOrderFixture(),
      orderCode,
      lifecycleStatus: 'COMPLETED',
      hasReturnedFullItems: false,
      returnedAfterTaxAmount: 0,
      statusCheckedAt: new Date('2026-07-10T02:00:00Z'),
    }));

    try {
      await expect(service.syncErpOrderStatuses('priority')).resolves.toEqual({
        skipped: false,
        processed: 4,
        changed: 2,
        failed: 0,
      });
      expect(
        erp.lookupOrderStatus.mock.calls.map(([orderCode]) => orderCode),
      ).toEqual(['2607092001', '2607082001', '2607093001', '2607083001']);
      expect(prisma.salesReportErpOrderCache.findMany).toHaveBeenNthCalledWith(
        1,
        expect.objectContaining({
          orderBy: expect.arrayContaining([{ orderCreatedAt: 'desc' }]),
        }),
      );
      expect(prisma.salesReportErpOrderCache.findMany).toHaveBeenNthCalledWith(
        2,
        expect.objectContaining({
          orderBy: expect.arrayContaining([{ orderCreatedAt: 'desc' }]),
        }),
      );
    } finally {
      jest.useRealTimers();
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous.enabled);
      restoreEnv('ERP_ORDER_STATUS_CACHE_SYNC_ENABLED', previous.cache);
      restoreEnv('ERP_ORDER_STATUS_SYNC_BATCH_SIZE', previous.batch);
      restoreEnv('ERP_ORDER_STATUS_SYNC_STORE_LIMIT', previous.storeLimit);
    }
  });

  it('does not refresh completed orders older than ten sale days', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-07-14T02:00:00Z'));
    const { service, prisma, erp } = createHarness();
    const previous = {
      enabled: process.env.ERP_ORDER_STATUS_SYNC_ENABLED,
      cache: process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED = 'true';
    prisma.salesReportErpOrderCache.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        {
          orderCode: '2607031103',
          storeCode: 'CP62',
          lifecycleStatus: 'COMPLETED',
          statusCheckedAt: new Date('2026-07-03T01:00:00Z'),
          statusCheckAttemptedAt: new Date('2026-07-03T01:00:00Z'),
          statusCheckAttemptDate: new Date('2026-07-03T00:00:00Z'),
          statusCheckAttemptCount: 1,
          statusCheckFailureCount: 0,
          orderCreatedAt: new Date('2026-07-03T00:00:00Z'),
          fetchedAt: new Date('2026-07-03T00:00:00Z'),
        },
      ]);
    prisma.salesReport.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);

    try {
      await expect(
        service.syncErpOrderStatuses('old-completed'),
      ).resolves.toEqual({
        skipped: false,
        processed: 0,
        changed: 0,
        failed: 0,
      });
      expect(erp.lookupOrderStatus).not.toHaveBeenCalled();
    } finally {
      jest.useRealTimers();
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous.enabled);
      restoreEnv('ERP_ORDER_STATUS_CACHE_SYNC_ENABLED', previous.cache);
    }
  });

  it('runs scheduled ERP order status sync with the 5-minute source label', async () => {
    const { service } = createHarness();
    const syncSpy = jest
      .spyOn(service, 'syncErpOrderStatuses')
      .mockResolvedValue({
        skipped: false,
        processed: 0,
        changed: 0,
        failed: 0,
      });

    await service.handleErpOrderStatusSync();

    expect(syncSpy).toHaveBeenCalledWith('scheduled_5m');
  });

  it('keeps refreshing the remaining orders when one ERP status lookup fails', async () => {
    const { service, prisma, erp } = createHarness();
    const previous = {
      enabled: process.env.ERP_ORDER_STATUS_SYNC_ENABLED,
      cache: process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED = 'false';
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
            statusCheckAttemptCount: 1,
            statusCheckFailureCount: 1,
          }),
        }),
      );
    } finally {
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous.enabled);
      restoreEnv('ERP_ORDER_STATUS_CACHE_SYNC_ENABLED', previous.cache);
    }
  });

  it('continues status sync when a reported order is missing its cache row', async () => {
    const { service, prisma, erp } = createHarness();
    const previous = {
      enabled: process.env.ERP_ORDER_STATUS_SYNC_ENABLED,
      cache: process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED = 'false';
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
          data: expect.objectContaining({
            erpStatusCheckAttemptCount: 1,
            erpStatusCheckFailureCount: 1,
          }),
        }),
      );
      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '2607013002' },
          create: expect.objectContaining({ orderCode: '2607013002' }),
        }),
      );
    } finally {
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous.enabled);
      restoreEnv('ERP_ORDER_STATUS_CACHE_SYNC_ENABLED', previous.cache);
    }
  });

  it('backfills status-sync cache store from ERP createdFromSiteDisplayName', async () => {
    const { service, prisma, erp } = createHarness();
    const previous = {
      enabled: process.env.ERP_ORDER_STATUS_SYNC_ENABLED,
      cache: process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED,
    };
    process.env.ERP_ORDER_STATUS_SYNC_ENABLED = 'true';
    process.env.ERP_ORDER_STATUS_CACHE_SYNC_ENABLED = 'false';
    prisma.salesReport.findMany
      .mockResolvedValueOnce([
        {
          orderCode: '26070732198240',
          storeCode: null,
          erpLifecycleStatus: 'PENDING',
          erpStatusCheckedAt: null,
          erpOrderCreatedAt: new Date('2026-07-07T06:59:38Z'),
        },
      ])
      .mockResolvedValueOnce([]);
    erp.lookupOrderStatus.mockResolvedValueOnce({
      ...erpListOrderFixture(),
      orderCode: '26070732198240',
      storeCode: null,
      storeName: null,
      lifecycleStatus: 'COMPLETED',
      hasReturnedFullItems: false,
      returnedAfterTaxAmount: 0,
      statusCheckedAt: new Date('2026-07-07T08:25:19Z'),
      sanitizedSnapshot: {
        orderCode: '26070732198240',
        createdFromSiteDisplayName:
          '[CP58] ĐỊA ĐIỂM KINH DOANH 52 - CÔNG TY CỔ PHẦN THƯƠNG MẠI - DỊCH VỤ PHONG VŨ',
      },
    });
    prisma.store.findMany.mockResolvedValueOnce([
      {
        storeId: 'CP58',
        storeName: 'Phong Vu CP58',
        organizationNodeId: 'node-cp58',
      },
    ]);

    try {
      await expect(service.syncErpOrderStatuses('test')).resolves.toEqual({
        skipped: false,
        processed: 1,
        changed: 1,
        failed: 0,
      });
      expect(prisma.salesReportErpOrderCache.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { orderCode: '26070732198240' },
          create: expect.objectContaining({
            orderCode: '26070732198240',
            storeCode: 'CP58',
            storeName: 'Phong Vu CP58',
            organizationNodeId: 'node-cp58',
          }),
          update: expect.objectContaining({
            storeCode: 'CP58',
            storeName: 'Phong Vu CP58',
            organizationNodeId: 'node-cp58',
          }),
        }),
      );
    } finally {
      restoreEnv('ERP_ORDER_STATUS_SYNC_ENABLED', previous.enabled);
      restoreEnv('ERP_ORDER_STATUS_CACHE_SYNC_ENABLED', previous.cache);
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

  it('uses ERP promotion and student autofill over stale purchased payload', async () => {
    const { service, prisma, erp } = createHarness();
    erp.lookupOrder.mockResolvedValueOnce({
      ...erpOrderFixture(),
      customerType: 'PERSONAL',
      customerIsStudent: true,
      promotionCodes: ['EXAM_SCORE_EXCHANGE'],
    });

    await service.create(userFixture(), {
      ...baseInput(),
      reportType: 'PURCHASED',
      orderCode: '26061334475421',
      customerType: 'BUSINESS',
      customerIsStudent: false,
      promotionCodes: ['OTHER'],
    });

    expect(prisma.salesReport.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          orderCode: '26061334475421',
          customerType: 'PERSONAL',
          customerIsStudent: true,
          promotionCodes: ['EXAM_SCORE_EXCHANGE'],
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

  it('exports Vietnamese HVTC XLSX rows per report', async () => {
    const { service, prisma } = createHarness();
    prisma.salesReport.findMany.mockResolvedValueOnce([exportReportFixture()]);

    const workbook = await service.exportWorkbook(
      { ...userFixture(), role: 'SUPER_ADMIN' },
      {},
    );
    const { rows, sheetName } = readWorkbookRows(workbook);

    expect(sheetName).toBe('HVTC');
    expect(workbook.subarray(0, 2).toString()).toBe('PK');
    expect(rows[0]).toEqual([
      'Ngày báo cáo',
      'Email người báo cáo',
      'Mã nhân viên tư vấn ERP',
      'Tên khách hàng',
      'Số điện thoại khách hàng',
      'Kênh liên hệ khách hàng',
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
    ]);
    expect(rows).toHaveLength(2);
    expect(rows[1][3]).toBe('Nguyen, Van A');
    expect(rows[1][4]).toBe('0900000000');
    expect(rows[1][5]).toBe('Điện thoại; Zalo cá nhân');
    expect(rows[1]).toContain('Mua hàng');
    expect(rows[1]).toContain('Có');
    expect(rows[0]).not.toContain('Report date');
  });

  it('exports Vietnamese revenue summary XLSX by category type', async () => {
    const { service, prisma } = createHarness();
    prisma.salesReport.findMany.mockResolvedValueOnce(revenueReportFixtures());

    const workbook = await service.exportWorkbook(
      { ...userFixture(), role: 'SUPER_ADMIN' },
      { exportType: 'REVENUE' },
    );
    const { rows, sheetName } = readWorkbookRows(workbook);

    expect(sheetName).toBe('Doanh so');
    expect(rows[0]).toEqual([
      'Số đơn hàng duy nhất',
      'Tổng doanh thu khách hàng doanh nghiệp',
      'Tổng doanh thu khách hàng cá nhân',
      'Báo cáo có nhu cầu trả góp',
      'Trả góp thành công (theo báo cáo bán hàng)',
      'Số lượng laptop',
      'Số lượng PC',
      'Số lượng PC ráp',
      'Số lượng Apple',
      'Số lượng màn hình',
      'Số lượng máy in',
      'Số lượng phụ kiện',
      'Số lượng dịch vụ bảo hiểm',
      'Các lý do khách không trả góp',
    ]);
    expect(rows[1].slice(0, 5)).toEqual([2, 1000, 2000, 2, 1]);
    expect(rows[1].slice(5, 13)).toEqual([3, 2, 1, 1, 3, 1, 4, 1]);
    expect(rows[1][13]).toBe('Khách từ chối: Lãi suất/Phí trả góp cao: 1');
  });

  it('summarizes promotion counts for Home main KPIs', () => {
    const { service } = createHarness();

    const summary = service.summarizeSalesRevenueRows([
      { ...exportReportFixture(), promotionCodes: ['EXAM_SCORE_EXCHANGE'] },
      { ...exportReportFixture(), promotionCodes: ['STUDENT'] },
      {
        ...exportReportFixture(),
        promotionCodes: ['EXAM_SCORE_EXCHANGE', 'STUDENT'],
      },
    ]);

    expect(summary.examScorePromotionCount).toBe(2);
    expect(summary.studentPromotionCount).toBe(2);
  });

  it('exports installment XLSX rows only for installment reports', async () => {
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
        id: 'report-not-purchased-installment',
        reportType: 'NOT_PURCHASED',
        orderCode: null,
        erpPaymentMethods: [],
        installmentApproved: false,
        installmentLoanAmount: 1000000,
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

    const workbook = await service.exportWorkbook(
      { ...userFixture(), role: 'SUPER_ADMIN' },
      { exportType: 'INSTALLMENT' },
    );
    const { rows, sheetName } = readWorkbookRows(workbook);

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
    expect(sheetName).toBe('Tra gop');
    expect(rows[0]).toEqual([
      'Ngày báo cáo',
      'Email người báo cáo',
      'Số tiền vay trả góp',
      'Đối tác trả góp',
      'Kết quả duyệt hồ sơ',
      'Loại báo cáo',
      'Phương thức thanh toán cuối cùng',
      'Lý do không trả góp',
    ]);
    expect(rows).toHaveLength(4);
    expect(rows[1]).toEqual([
      '29/06/2026 08:00:00',
      'sale@phongvu.vn',
      5000000,
      'VNPAY_POS; MPOS',
      'Đã duyệt',
      'Mua hàng',
      'Trả góp',
      'Khách chốt trả góp bình thường (Không có lý do)',
    ]);
    expect(rows[2][2]).toBe(2500000);
    expect(rows[2][3]).toBe('PAYOO_POS');
    expect(rows[2][4]).toBe('Chưa duyệt');
    expect(rows[2][6]).toBe('Trả thẳng');
    expect(rows[3][5]).toBe('Chưa mua hàng');
    expect(rows[3][6]).toBe('Chưa mua hàng');
    expect(JSON.stringify(rows)).not.toContain('2606290888');
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

  it('offers all and active organization node dashboard scopes to super admin', async () => {
    const { service, prisma } = createHarness();
    const { domainNode, regionNode, areaNode, storeNode, inactiveStoreNode } =
      organizationTreeFixture();
    prisma.organizationNode.findMany.mockResolvedValueOnce([domainNode]);

    const options = await service.listHomeSummaryScopeOptions(
      {
        ...adminSalesUser(),
        id: 'super-1',
        role: 'SUPER_ADMIN',
        featureAccess: {
          [FEATURE_KEYS.ADMIN_SALES_REPORTS]: true,
          [FEATURE_KEYS.SALES_REPORT]: true,
        },
      },
      { allowOwnScope: true },
    );

    expect(prisma.organizationNode.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { isActive: true, parentId: null },
      }),
    );
    expect(options.map((option) => option.value)).toEqual([
      'ALL',
      `NODE:${regionNode.id}`,
      `NODE:${areaNode.id}`,
      `NODE:${storeNode.id}`,
      'OWN',
    ]);
    expect(options[0]).toMatchObject({
      label: 'Toàn hệ thống',
      isDefault: true,
    });
    expect(options).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          label: 'Miền: Miền Nam',
          organizationNodeType: 'LV2_REGION',
          storeCount: 1,
        }),
        expect.objectContaining({
          label: 'Vùng: Hồ Chí Minh',
          organizationNodeType: 'LV3_AREA',
          storeCount: 1,
        }),
        expect.objectContaining({
          label: 'Showroom: CP75',
          organizationNodeType: 'LV4_STORE',
          storeCount: 1,
        }),
      ]),
    );
    expect(options.map((option) => option.organizationNodeId)).not.toContain(
      domainNode.id,
    );
    expect(options.map((option) => option.organizationNodeId)).not.toContain(
      inactiveStoreNode.id,
    );
  });

  it('resolves selected organization node dashboard scope for super admin', async () => {
    const { service, prisma } = createHarness();
    const { areaNode } = organizationTreeFixture();
    prisma.organizationNode.findUnique.mockResolvedValueOnce(areaNode);

    await expect(
      service.describeHomeSummaryScope(
        { ...adminSalesUser(), role: 'SUPER_ADMIN' },
        'MANAGED_SCOPE',
        areaNode.id,
        { allowOwnScope: true },
      ),
    ).resolves.toMatchObject({
      available: true,
      scope: 'MANAGED_SCOPE',
      scopeLabel: 'Vùng: Hồ Chí Minh',
      allowedStoreCodes: ['CP75'],
    });

    expect(prisma.organizationNode.findUnique).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: areaNode.id },
      }),
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

  it('offers an aggregate assigned-SR dashboard scope for multi-showroom staff', async () => {
    const { service, prisma } = createHarness();
    const { cp46StoreNode, cp46PositionNode, cp67StoreNode, cp67PositionNode } =
      multiShowroomAssignmentFixture();
    const user = {
      ...userFixture(),
      jobRoleCode: 'SA',
      store: null,
      organizationNode: cp46PositionNode,
      organizationAssignments: [
        {
          organizationNodeId: cp46PositionNode.id,
          organizationNode: cp46PositionNode,
          isPrimary: true,
        },
        {
          organizationNodeId: cp67PositionNode.id,
          organizationNode: cp67PositionNode,
          isPrimary: false,
        },
      ],
    };
    prisma.user.findUnique.mockResolvedValue(user);

    const options = await service.listHomeSummaryScopeOptions(user, {
      allowOwnScope: true,
    });

    expect(options.map((option) => option.value)).toEqual([
      'MANAGED_SCOPE',
      `NODE:${cp46StoreNode.id}`,
      `NODE:${cp67StoreNode.id}`,
      'OWN',
    ]);
    expect(options[0]).toMatchObject({
      label: 'Tất cả SR được gán',
      scope: 'MANAGED_SCOPE',
      organizationNodeId: null,
      storeCount: 2,
      isDefault: true,
    });

    await expect(
      service.describeHomeSummaryScope(user, 'MANAGED_SCOPE', null, {
        allowOwnScope: true,
      }),
    ).resolves.toMatchObject({
      available: true,
      scope: 'MANAGED_SCOPE',
      scopeLabel: 'Tất cả SR được gán',
      scopeDetail: 'CP46, CP67',
      allowedStoreCodes: ['CP46', 'CP67'],
    });
  });

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

function readWorkbookRows(buffer: Buffer) {
  const workbook = XLSX.read(buffer, { type: 'buffer' });
  const sheetName = workbook.SheetNames[0];
  if (!sheetName) throw new Error('Workbook has no sheets');
  const sheet = workbook.Sheets[sheetName];
  if (!sheet) throw new Error(`Workbook sheet not found: ${sheetName}`);
  const rows = XLSX.utils.sheet_to_json(sheet, {
    header: 1,
    raw: true,
    defval: '',
  }) as Array<Array<string | number>>;
  return { sheetName, rows };
}

function baseInput() {
  return {
    reportType: 'NOT_PURCHASED',
    categoryGroupId: 'NH03',
    customerName: 'Nguyen Van A',
    customerPhone: '',
    customerContactChannels: [],
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

function multiShowroomAssignmentFixture() {
  const cp46StoreNode: any = {
    id: 'node-cp46',
    type: 'LV4_STORE',
    displayName: 'CP46',
    businessCode: 'CP46',
    stores: [{ storeId: 'CP46', storeName: 'CP46' }],
    parent: null,
    children: [],
  };
  const cp67StoreNode: any = {
    id: 'node-cp67',
    type: 'LV4_STORE',
    displayName: 'CP67',
    businessCode: 'CP67',
    stores: [{ storeId: 'CP67', storeName: 'CP67' }],
    parent: null,
    children: [],
  };
  const cp46PositionNode = {
    id: 'node-cp46-sa',
    type: 'LV5_POSITION',
    displayName: 'SA CP46',
    stores: [],
    parent: cp46StoreNode,
    children: [],
  };
  const cp67PositionNode = {
    id: 'node-cp67-sa',
    type: 'LV5_POSITION',
    displayName: 'SA CP67',
    stores: [],
    parent: cp67StoreNode,
    children: [],
  };
  cp46StoreNode.children = [cp46PositionNode];
  cp67StoreNode.children = [cp67PositionNode];
  return { cp46StoreNode, cp46PositionNode, cp67StoreNode, cp67PositionNode };
}

function organizationTreeFixture() {
  const storeNode: any = {
    id: 'org-store-cp75',
    type: 'LV4_STORE',
    displayName: 'CP75',
    businessCode: 'CP75',
    isActive: true,
    stores: [{ storeId: 'CP75', storeName: 'CP75' }],
    parent: null,
    children: [],
  };
  const inactiveStoreNode: any = {
    id: 'org-store-cp00',
    type: 'LV4_STORE',
    displayName: 'CP00',
    businessCode: 'CP00',
    isActive: false,
    stores: [],
    parent: null,
    children: [],
  };
  const areaNode: any = {
    id: 'org-area-hcm',
    type: 'LV3_AREA',
    displayName: 'Hồ Chí Minh',
    businessCode: 'HCM',
    isActive: true,
    stores: [],
    parent: null,
    children: [storeNode, inactiveStoreNode],
  };
  const regionNode: any = {
    id: 'org-region-south',
    type: 'LV2_REGION',
    displayName: 'Miền Nam',
    businessCode: 'MIEN_NAM',
    isActive: true,
    stores: [],
    parent: null,
    children: [areaNode],
  };
  const domainNode: any = {
    id: 'org-domain',
    type: 'LV0_DOMAIN',
    displayName: 'Phong Vũ',
    businessCode: 'PHONGVU',
    isActive: true,
    stores: [],
    parent: null,
    children: [regionNode],
  };
  storeNode.parent = areaNode;
  inactiveStoreNode.parent = areaNode;
  areaNode.parent = regionNode;
  regionNode.parent = domainNode;
  return { domainNode, regionNode, areaNode, storeNode, inactiveStoreNode };
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
    customerIsStudent: false,
    customerNeed: 'RAM DDR5',
    promotionCodes: ['OTHER'],
    installmentNeed: false,
    installmentLoanAmount: null,
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
    customerContactChannels: ['PHONE', 'ZALO_PERSONAL'],
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
      installmentNeed: false,
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
