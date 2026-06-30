import { BadRequestException } from '@nestjs/common';
import { SalesReportsService } from './sales-reports.service';

describe('SalesReportsService', () => {
  function createHarness() {
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue(userFixture()),
      },
      salesReport: {
        findUnique: jest.fn().mockResolvedValue(null),
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
    };
    const service = new SalesReportsService(
      prisma as any,
      categories as any,
      erp as any,
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

  it('re-checks ERP and stores normalized order rows for purchased report', async () => {
    const { service, prisma, erp } = createHarness();

    await service.create(userFixture(), {
      ...baseInput(),
      reportType: 'PURCHASED',
      orderCode: ' 2606290001 ',
      customerType: undefined,
    });

    expect(erp.lookupOrder).toHaveBeenCalledWith('2606290001', 'CP62');
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
        'Các lý do khách không trả góp',
        'Số lượng laptop',
        'Số lượng PC',
        'Số lượng PC ráp',
        'Số lượng Apple',
        'Số lượng màn hình',
        'Số lượng máy in',
        'Số lượng phụ kiện',
        'Số lượng dịch vụ bảo hiểm',
      ].join(','),
    );
    expect(lines[1]).toContain('2,1000,2000');
    expect(lines[1]).toContain('Khách từ chối: Lãi suất/Phí trả góp cao: 1');
    expect(lines[1]).toContain(',3,2,1,1,3,1,4,1');
    expect(lines[1]).not.toContain('"');
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
