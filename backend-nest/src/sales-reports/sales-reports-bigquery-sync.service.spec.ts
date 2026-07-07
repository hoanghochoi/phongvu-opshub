import { SalesReportsBigQuerySyncService } from './sales-reports-bigquery-sync.service';

const ENV_KEYS = [
  'SALES_REPORT_BIGQUERY_SYNC_ENABLED',
  'SALES_REPORT_BIGQUERY_SYNC_ON_STARTUP',
  'SALES_REPORT_BIGQUERY_PROJECT_ID',
  'SALES_REPORT_BIGQUERY_DATASET_ID',
  'SALES_REPORT_BIGQUERY_KEY_FILE',
  'SALES_REPORT_BIGQUERY_TABLE_PREFIX',
  'SALES_REPORT_BIGQUERY_REPORT_TABLE_ID',
  'SALES_REPORT_BIGQUERY_REVENUE_TABLE_ID',
  'SALES_REPORT_BIGQUERY_ITEM_TABLE_ID',
  'SALES_REPORT_BIGQUERY_PAYMENT_TABLE_ID',
  'SALES_REPORT_BIGQUERY_MAX_ROWS',
  'BIGQUERY_PROJECT_ID',
  'BIGQUERY_DATASET_ID',
  'BIGQUERY_KEY_FILE',
  'GOOGLE_APPLICATION_CREDENTIALS',
];

describe('SalesReportsBigQuerySyncService', () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeEach(() => {
    originalEnv = { ...process.env };
    for (const key of ENV_KEYS) delete process.env[key];
  });

  afterEach(() => {
    process.env = originalEnv;
    jest.restoreAllMocks();
  });

  it('skips manual sync when BigQuery config is missing', async () => {
    const prisma = {
      salesReport: { findMany: jest.fn() },
    };
    const service = new SalesReportsBigQuerySyncService(prisma as any);

    await expect(
      service.syncAll('manual', { force: true }),
    ).resolves.toMatchObject({
      skipped: true,
      reason: 'missing_config',
      reportRows: 0,
      itemRows: 0,
      paymentRows: 0,
    });
    expect(prisma.salesReport.findMany).not.toHaveBeenCalled();
  });

  it('maps sales-report facts and full-refreshes all BigQuery tables', async () => {
    process.env.SALES_REPORT_BIGQUERY_PROJECT_ID = 'opshub-project';
    process.env.SALES_REPORT_BIGQUERY_DATASET_ID = 'opshub_reporting';
    process.env.SALES_REPORT_BIGQUERY_TABLE_PREFIX = 'sales_report';
    const prisma = {
      salesReport: {
        findMany: jest.fn().mockResolvedValue([
          salesReportFixture(),
          {
            ...salesReportFixture(),
            id: 'report-2',
            orderCode: '2607010002',
            customerType: 'PERSONAL',
            installmentNeed: false,
            installmentNoInstallmentReason: null,
            storeCode: 'CP02',
            storeName: 'CP02',
            organizationNodeId: 'node-cp02',
            organizationNodeName: 'Showroom CP02',
            erpGrandTotal: 2160000,
            erpPaymentMethods: ['cash'],
            items: [
              {
                ...salesReportFixture().items[0],
                id: 'item-2',
                categoryType: 'monitor',
                quantity: 2,
                rowTotal: 2160000,
              },
            ],
            payments: [],
          },
        ]),
      },
    };
    const service = new SalesReportsBigQuerySyncService(prisma as any);
    const replaceTableRows = jest
      .spyOn(service as any, 'replaceTableRows')
      .mockResolvedValue(undefined);
    jest
      .spyOn(service as any, 'createBigQueryClient')
      .mockReturnValue({ fake: true });

    const result = await service.syncAll('manual', { force: true });

    expect(result).toMatchObject({
      skipped: false,
      reportRows: 2,
      revenueRows: 2,
      itemRows: 2,
      paymentRows: 1,
      tables: {
        reports: 'opshub-project.opshub_reporting.sales_report_reports',
        revenueByStore:
          'opshub-project.opshub_reporting.sales_report_revenue_by_store',
        items: 'opshub-project.opshub_reporting.sales_report_items',
        payments: 'opshub-project.opshub_reporting.sales_report_payments',
      },
    });
    expect(prisma.salesReport.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { erpExcludedAt: null },
        include: expect.objectContaining({
          categorySelections: expect.any(Object),
          items: expect.any(Object),
          payments: expect.any(Object),
        }),
      }),
    );
    expect(replaceTableRows).toHaveBeenCalledTimes(4);

    const reportRows = replaceTableRows.mock.calls[0][4] as Array<
      Record<string, unknown>
    >;
    const revenueRows = replaceTableRows.mock.calls[1][4] as Array<
      Record<string, unknown>
    >;
    const itemRows = replaceTableRows.mock.calls[2][4] as Array<
      Record<string, unknown>
    >;
    const paymentRows = replaceTableRows.mock.calls[3][4] as Array<
      Record<string, unknown>
    >;

    expect(reportRows[0]).toMatchObject({
      sales_report_id: 'report-1',
      report_type_label: 'Mua hàng',
      submitted_date: '2026-07-01',
      category_groups_vi: 'Laptop; Màn hình',
      consulted_solution_label: 'Có',
      customer_type_label: 'Doanh nghiệp',
      promotion_labels: 'Học sinh - Sinh viên',
      final_payment_method_label: 'Trả góp',
      erp_grand_total: 1080000,
      revenue_before_vat: 1000000,
    });
    expect(revenueRows).toHaveLength(2);
    expect(revenueRows[0]).toMatchObject({
      store_code: 'CP01',
      sales_report_count: 1,
      installment_need_total_count: 1,
      successful_installment_order_count: 1,
      order_count_unique: 1,
      business_revenue: 1080000,
      personal_revenue: 0,
    });
    expect(revenueRows[1]).toMatchObject({
      store_code: 'CP02',
      sales_report_count: 1,
      installment_need_total_count: 0,
      successful_installment_order_count: 0,
      order_count_unique: 1,
      business_revenue: 0,
      personal_revenue: 2160000,
      monitor_quantity: 2,
    });
    expect(itemRows[0]).toMatchObject({
      sales_report_item_id: 'item-1',
      sku: 'SKU-1',
      category_type: 'laptop',
      row_total: 108000,
      row_revenue_before_vat: 100000,
    });
    expect(paymentRows[0]).toMatchObject({
      sales_report_payment_id: 'payment-1',
      payment_method: 'installment',
      amount: 500000,
    });
  });
});

function salesReportFixture() {
  return {
    id: 'report-1',
    reportType: 'PURCHASED',
    submittedAt: new Date('2026-07-01T01:30:00.000Z'),
    orderCode: '2607010001',
    customerName: 'Nguyen Van A',
    customerPhone: '0900000000',
    customerNeed: 'Laptop văn phòng',
    categoryGroupId: 'NH01',
    categoryGroupName: 'Laptop',
    categoryGroupNameVi: 'Laptop',
    categorySelections: [
      {
        categoryGroupId: 'NH01',
        categoryGroupName: 'Laptop',
        categoryGroupNameVi: 'Laptop',
      },
      {
        categoryGroupId: 'NH02',
        categoryGroupName: 'Monitor',
        categoryGroupNameVi: 'Màn hình',
      },
    ],
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
    promotionCodes: ['STUDENT'],
    installmentNeed: true,
    installmentApproved: true,
    installmentLoanAmount: 500000,
    installmentStatus: 'SUCCESS',
    installmentFailureReason: null,
    installmentPartnerCodes: ['VNPAY_POS'],
    installmentNoInstallmentReason: 'NORMAL_INSTALLMENT',
    createdByUserId: 'user-1',
    createdByEmail: 'sale@phongvu.vn',
    createdByName: 'Sale User',
    createdByPersonnelCode: 'SA001',
    storeCode: 'CP01',
    storeName: 'CP01',
    organizationNodeId: 'node-cp01',
    organizationNodeName: 'Showroom CP01',
    regionCode: 'MNA',
    areaCode: 'HCM',
    erpOrderId: 'erp-order-1',
    erpExternalOrderRef: 'external-1',
    erpOrderCreatedAt: new Date('2026-07-01T01:00:00.000Z'),
    erpPaymentStatus: 'PAID',
    erpConfirmationStatus: 'COMPLETED',
    erpFulfillmentStatus: 'COMPLETED',
    erpLifecycleStatus: 'COMPLETED',
    erpHasReturnedFullItems: false,
    erpReturnedAfterTaxAmount: 0,
    erpTerminalName: 'CP01',
    erpGrandTotal: 1080000,
    erpPaymentMethods: ['cash', 'installment'],
    erpCustomerType: 'BUSINESS',
    erpPlatformId: 3,
    erpConsultantCustomId: 'SA001',
    erpConsultantName: 'Sale User',
    erpFetchedAt: new Date('2026-07-01T01:05:00.000Z'),
    erpFetchStatus: 'FOUND',
    createdAt: new Date('2026-07-01T01:30:00.000Z'),
    updatedAt: new Date('2026-07-01T02:00:00.000Z'),
    items: [
      {
        id: 'item-1',
        sku: 'SKU-1',
        sellerSku: 'SELLER-SKU-1',
        name: 'Laptop A',
        brandCode: 'BRAND',
        brandName: 'Brand',
        productTypeCode: 'PT',
        productTypeName: 'Laptop',
        productGroupId: 'PG',
        productGroupCode: 'PG',
        productGroupName: 'Laptop',
        categoryType: 'laptop',
        quantity: 1,
        sellPrice: 108000,
        finalSellPrice: 108000,
        rowTotal: 108000,
        createdAt: new Date('2026-07-01T01:31:00.000Z'),
      },
    ],
    payments: [
      {
        id: 'payment-1',
        paymentMethod: 'installment',
        amount: 500000,
        paidAt: new Date('2026-07-01T01:20:00.000Z'),
        transactionCode: 'txn-1',
        partnerTransactionCode: 'partner-1',
        createdAt: new Date('2026-07-01T01:32:00.000Z'),
      },
    ],
  };
}
