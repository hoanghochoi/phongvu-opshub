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
});

function baseInput() {
  return {
    reportType: 'NOT_PURCHASED',
    categoryGroupId: 'NH03',
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
