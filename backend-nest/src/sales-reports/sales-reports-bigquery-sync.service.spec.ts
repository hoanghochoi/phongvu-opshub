import { SalesReportsBigQuerySyncService } from './sales-reports-bigquery-sync.service';
import { buildCanonicalRevenueLookup } from './sales-report-revenue';

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
  'SALES_REPORT_BIGQUERY_FOLLOW_UP_TABLE_ID',
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
      followUpRows: 0,
    });
    expect(prisma.salesReport.findMany).not.toHaveBeenCalled();
  });

  it('labels not-purchased reports separately from purchased payment methods', () => {
    const service = new SalesReportsBigQuerySyncService({} as any);
    const label = (row: any) => (service as any).finalPaymentMethodLabel(row);

    expect(label({ reportType: 'NOT_PURCHASED', erpPaymentMethods: [] })).toBe(
      'Chưa mua hàng',
    );
    expect(label({ reportType: 'PURCHASED', erpPaymentMethods: [] })).toBe(
      'Trả thẳng',
    );
    expect(
      label({ reportType: 'PURCHASED', erpPaymentMethods: ['installment'] }),
    ).toBe('Trả góp');
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
      salesReportErpOrderCache: {
        findMany: jest
          .fn()
          .mockResolvedValue([
            { orderCode: '2607010001', grandTotal: 5400000 },
          ]),
      },
      salesReportFollowUpCase: {
        findMany: jest.fn().mockResolvedValue([followUpCaseFixture()]),
      },
    };
    const service = new SalesReportsBigQuerySyncService(prisma as any);
    const stageAndPublishSnapshot = jest
      .spyOn(service as any, 'stageAndPublishSnapshot')
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
      followUpRows: 1,
      tables: {
        reports: 'opshub-project.opshub_reporting.sales_report_reports',
        revenueByStore:
          'opshub-project.opshub_reporting.sales_report_revenue_by_store',
        items: 'opshub-project.opshub_reporting.sales_report_items',
        payments: 'opshub-project.opshub_reporting.sales_report_payments',
        followUps:
          'opshub-project.opshub_reporting.sales_report_follow_up_history',
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
    expect(prisma.salesReportFollowUpCase.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { followUpCount: { gt: 0 } },
        include: expect.objectContaining({
          sourceReport: expect.any(Object),
          entries: expect.any(Object),
        }),
      }),
    );
    expect(stageAndPublishSnapshot).toHaveBeenCalledTimes(1);
    const tables = stageAndPublishSnapshot.mock.calls[0][3] as Array<{
      schema: Array<Record<string, unknown>>;
      rows: Array<Record<string, unknown>>;
    }>;
    const reportRows = tables[0].rows;
    const revenueRows = tables[1].rows;
    const revenueSchema = tables[1].schema;
    const itemRows = tables[2].rows;
    const itemSchema = tables[2].schema;
    const paymentRows = tables[3].rows;
    const followUpSchema = tables[4].schema;
    const followUpRows = tables[4].rows;

    expect(reportRows[0]).toMatchObject({
      sales_report_id: 'report-1',
      report_type_label: 'Mua hàng',
      entry_source: 'COMEBACK',
      submitted_date: '2026-07-01',
      category_groups_vi: 'Laptop; Màn hình',
      consulted_solution_label: 'Có',
      customer_type_label: 'Doanh nghiệp',
      customer_contact_channel_codes: 'PHONE; ZALO_PERSONAL; ZALO_OA',
      customer_contact_channel_labels: 'Điện thoại; Zalo cá nhân; Zalo OA',
      has_phone_contact: true,
      has_zalo_personal_contact: true,
      has_zalo_oa_contact: true,
      promotion_labels: 'Học sinh - Sinh viên',
      final_payment_method_label: 'Trả thẳng',
      erp_grand_total: 1080000,
      canonical_revenue_vat_inclusive: 5400000,
      canonical_revenue_source: 'ERP_ORDER_CACHE_GRAND_TOTAL',
      canonical_revenue_quality: 'VALID',
      revenue_before_vat: 5000000,
    });
    expect(tables[0].schema.map((field) => field.name)).toEqual(
      expect.arrayContaining([
        'canonical_revenue_vat_inclusive',
        'canonical_revenue_source',
        'canonical_revenue_quality',
      ]),
    );
    expect(revenueRows).toHaveLength(2);
    expect(revenueSchema.map((field) => field.name)).toEqual(
      expect.arrayContaining([
        'revenue_source',
        'revenue_vat_inclusive',
        'missing_revenue_order_count',
        'invalid_revenue_order_count',
      ]),
    );
    expect(revenueRows[0]).toMatchObject({
      store_code: 'CP01',
      sales_report_count: 1,
      installment_need_total_count: 1,
      successful_installment_order_count: 1,
      order_count_unique: 1,
      business_revenue: 5400000,
      personal_revenue: 0,
      revenue_source: 'ERP_ORDER_CACHE_GRAND_TOTAL',
      revenue_vat_inclusive: true,
      missing_revenue_order_count: 0,
      invalid_revenue_order_count: 0,
    });
    expect(revenueRows[1]).toMatchObject({
      store_code: 'CP02',
      sales_report_count: 1,
      installment_need_total_count: 0,
      successful_installment_order_count: 0,
      order_count_unique: 1,
      business_revenue: 0,
      personal_revenue: 0,
      missing_revenue_order_count: 1,
      invalid_revenue_order_count: 0,
      monitor_quantity: 2,
    });
    expect(itemRows[0]).toMatchObject({
      sales_report_item_id: 'item-1',
      sku: 'SKU-1',
      category_type: 'laptop',
      row_total: 108000,
      row_revenue_before_vat: 100000,
      item_price_source: 'ORDER_CAPTURE',
      row_revenue_before_vat_method: 'LEGACY_DIVIDE_BY_1_08',
    });
    expect(itemSchema.map((field) => field.name)).toEqual(
      expect.arrayContaining([
        'item_price_source',
        'row_revenue_before_vat_method',
      ]),
    );
    expect(paymentRows[0]).toMatchObject({
      sales_report_payment_id: 'payment-1',
      payment_method: 'installment',
      amount: 500000,
    });
    expect(followUpSchema.map((field) => field.name)).toContain('follow_up_2');
    expect(followUpRows).toHaveLength(1);
    expect(followUpRows[0]).toMatchObject({
      follow_up_case_id: 'case-1',
      source_report_id: 'report-1',
      customer_name: 'Nguyen Van A',
      follow_up_count: 2,
      follow_up_1: {
        sequence_number: 1,
        outcome: 'NOT_PURCHASED',
        outcome_label: 'Chưa mua',
        not_purchased_reason_label: 'Phân vân giá',
      },
      follow_up_2: {
        sequence_number: 2,
        outcome: 'PURCHASED',
        outcome_label: 'Mua hàng',
      },
    });
  });

  it('keeps unique order and item facts when canonical cache revenue is invalid', () => {
    const service = new SalesReportsBigQuerySyncService({} as any);
    const fixture = {
      ...salesReportFixture(),
      erpGrandTotal: 9999999,
      erpReturnedAfterTaxAmount: 500000,
    };
    const lookup = buildCanonicalRevenueLookup([
      { orderCode: fixture.orderCode, grandTotal: null },
    ]);

    const rows = (service as any).toRevenueByStoreRows(
      [fixture],
      new Date('2026-08-01T00:00:00Z'),
      lookup,
    );

    expect(rows[0]).toMatchObject({
      order_count_unique: 1,
      business_revenue: 0,
      invalid_revenue_order_count: 1,
      missing_revenue_order_count: 0,
      laptop_quantity: 1,
    });
  });

  it('loads 5,001 canonical order codes in batches of 5,000 and 1', async () => {
    const findMany = jest.fn().mockImplementation(async ({ where }) =>
      where.orderCode.in.map((orderCode: string) => ({
        orderCode,
        grandTotal: 1080000,
      })),
    );
    const service = new SalesReportsBigQuerySyncService({
      salesReportErpOrderCache: { findMany },
    } as any);
    const orderCodes = Array.from(
      { length: 5001 },
      (_, index) => `order-${index + 1}`,
    );

    const rows = await (service as any).loadCanonicalRevenueRows(orderCodes);

    expect(rows).toHaveLength(5001);
    expect(findMany).toHaveBeenCalledTimes(2);
    expect(findMany.mock.calls[0][0]).toMatchObject({
      where: { excludedAt: null },
      select: { orderCode: true, grandTotal: true },
    });
    expect(findMany.mock.calls[0][0].where.orderCode.in).toHaveLength(5000);
    expect(findMany.mock.calls[1][0].where.orderCode.in).toEqual([
      'order-5001',
    ]);
  });

  it('adds missing schema fields before clearing an existing empty table', async () => {
    const service = new SalesReportsBigQuerySyncService({} as any);
    const table = {
      exists: jest.fn().mockResolvedValue([true]),
      getMetadata: jest
        .fn()
        .mockResolvedValue([
          { schema: { fields: [{ name: 'store_code', type: 'STRING' }] } },
        ]),
      setMetadata: jest.fn().mockResolvedValue([{}]),
    };
    const client = {
      dataset: jest.fn().mockReturnValue({
        table: jest.fn().mockReturnValue(table),
      }),
      query: jest.fn().mockResolvedValue([{}]),
    };

    await (service as any).replaceTableRows(
      client,
      { projectId: 'project', datasetId: 'dataset' },
      'revenue',
      [
        { name: 'store_code', type: 'STRING' },
        { name: 'revenue_source', type: 'STRING' },
      ],
      [],
    );

    expect(table.setMetadata).toHaveBeenCalledWith({
      schema: {
        fields: [
          { name: 'store_code', type: 'STRING' },
          { name: 'revenue_source', type: 'STRING' },
        ],
      },
    });
    expect(client.query).toHaveBeenCalledWith({
      query: 'DELETE FROM `project.dataset.revenue` WHERE TRUE',
    });
  });

  it('fails closed before BigQuery writes when the report snapshot is empty', async () => {
    process.env.SALES_REPORT_BIGQUERY_PROJECT_ID = 'opshub-project';
    process.env.SALES_REPORT_BIGQUERY_DATASET_ID = 'opshub-reporting';
    const prisma = {
      salesReport: { findMany: jest.fn().mockResolvedValue([]) },
      salesReportFollowUpCase: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = new SalesReportsBigQuerySyncService(prisma as any);
    const stageAndPublish = jest.spyOn(
      service as any,
      'stageAndPublishSnapshot',
    );
    jest
      .spyOn(service as any, 'createBigQueryClient')
      .mockReturnValue({ fake: true });

    await expect(service.syncAll('manual', { force: true })).rejects.toThrow(
      'reason=empty_sales_reports',
    );
    expect(stageAndPublish).not.toHaveBeenCalled();
  });

  it('queries maxRows plus one and fails closed before writes when truncated', async () => {
    process.env.SALES_REPORT_BIGQUERY_PROJECT_ID = 'opshub-project';
    process.env.SALES_REPORT_BIGQUERY_DATASET_ID = 'opshub-reporting';
    process.env.SALES_REPORT_BIGQUERY_MAX_ROWS = '1';
    const prisma = {
      salesReport: {
        findMany: jest
          .fn()
          .mockResolvedValue([salesReportFixture(), salesReportFixture()]),
      },
      salesReportFollowUpCase: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = new SalesReportsBigQuerySyncService(prisma as any);
    const stageAndPublish = jest.spyOn(
      service as any,
      'stageAndPublishSnapshot',
    );
    jest
      .spyOn(service as any, 'createBigQueryClient')
      .mockReturnValue({ fake: true });

    await expect(service.syncAll('manual', { force: true })).rejects.toThrow(
      'reason=sales_report_limit_exceeded maxRows=1',
    );
    expect(prisma.salesReport.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ take: 2 }),
    );
    expect(stageAndPublish).not.toHaveBeenCalled();
  });

  it('stages every table before publishing and restores an earlier target when a later publish fails', async () => {
    const service = new SalesReportsBigQuerySyncService({} as any);
    const calls: string[] = [];
    const tables = new Map<string, any>();
    const tableFor = (id: string) => {
      if (tables.has(id)) return tables.get(id);
      const table = {
        id,
        exists: jest.fn().mockResolvedValue([!id.includes('__')]),
        delete: jest.fn().mockImplementation(async () => {
          calls.push(`delete:${id}`);
        }),
        createCopyJob: jest
          .fn()
          .mockImplementation(async (destination: any) => {
            calls.push(`copy:${id}->${destination.id}`);
            if (id.includes('second__stage_')) {
              throw new Error('publish failed after staging');
            }
            return [{ promise: jest.fn().mockResolvedValue(undefined) }];
          }),
      };
      tables.set(id, table);
      return table;
    };
    const client = {
      dataset: jest.fn().mockReturnValue({ table: tableFor }),
    };
    jest
      .spyOn(service as any, 'replaceTableRows')
      .mockImplementation(async (_client, _config, tableId) => {
        calls.push(`stage:${tableId}`);
      });

    await expect(
      (service as any).stageAndPublishSnapshot(
        client,
        { datasetId: 'dataset' },
        new Date('2026-08-01T00:00:00Z'),
        [
          { tableId: 'first', schema: [], rows: [{ id: 1 }] },
          { tableId: 'second', schema: [], rows: [{ id: 2 }] },
        ],
      ),
    ).rejects.toThrow('publish failed after staging');

    const firstPublish = calls.findIndex((call) =>
      call.startsWith('copy:first__stage_'),
    );
    expect(
      calls.slice(0, firstPublish).filter((call) => call.startsWith('stage:')),
    ).toHaveLength(2);
    expect(
      calls.some(
        (call) =>
          call.startsWith('copy:first__backup_') && call.endsWith('->first'),
      ),
    ).toBe(true);
  });

  it('cleans staging but preserves the recovery backup when rollback restoration fails', async () => {
    const service = new SalesReportsBigQuerySyncService({} as any);
    const tables = new Map<string, any>();
    const tableFor = (id: string) => {
      if (tables.has(id)) return tables.get(id);
      const table = {
        id,
        exists: jest.fn().mockResolvedValue([!id.includes('__')]),
        delete: jest.fn().mockResolvedValue(undefined),
        createCopyJob: jest
          .fn()
          .mockImplementation(async (destination: any) => {
            if (id.includes('second__stage_')) {
              throw new Error('publish failed after staging');
            }
            if (id.includes('first__backup_') && destination.id === 'first') {
              throw new Error('rollback restore failed');
            }
            return [{ promise: jest.fn().mockResolvedValue(undefined) }];
          }),
      };
      tables.set(id, table);
      return table;
    };
    const client = {
      dataset: jest.fn().mockReturnValue({ table: tableFor }),
    };
    jest.spyOn(service as any, 'replaceTableRows').mockResolvedValue(undefined);

    await expect(
      (service as any).stageAndPublishSnapshot(
        client,
        { datasetId: 'dataset' },
        new Date('2026-08-01T00:00:00Z'),
        [
          { tableId: 'first', schema: [], rows: [{ id: 1 }] },
          { tableId: 'second', schema: [], rows: [{ id: 2 }] },
        ],
      ),
    ).rejects.toThrow('rollbackIncomplete=1');

    const firstStage = Array.from(tables.keys()).find((id) =>
      id.startsWith('first__stage_'),
    )!;
    const secondStage = Array.from(tables.keys()).find((id) =>
      id.startsWith('second__stage_'),
    )!;
    const firstBackup = Array.from(tables.keys()).find((id) =>
      id.startsWith('first__backup_'),
    )!;

    expect(tables.get(firstStage).delete).toHaveBeenCalledWith({
      ignoreNotFound: true,
    });
    expect(tables.get(secondStage).delete).toHaveBeenCalledWith({
      ignoreNotFound: true,
    });
    expect(tables.get(firstBackup).delete).not.toHaveBeenCalled();
  });

  it('sanitizes BigQuery error name, code, credentials, and email context', () => {
    const service = new SalesReportsBigQuerySyncService({} as any);
    const error = Object.assign(
      new Error(
        'authorization=Bearer secret-token user@example.com\npayload follows',
      ),
      { code: '403 unsafe', name: 'BigQuery Error' },
    );

    const summary = (service as any).safeError(error);

    expect(summary).toContain('name=BigQueryError');
    expect(summary).toContain('code=403unsafe');
    expect(summary).toContain('[redacted]');
    expect(summary).toContain('[redacted-email]');
    expect(summary).not.toContain('secret-token');
    expect(summary).not.toContain('\n');
  });
});

function followUpCaseFixture() {
  const sourceReport = salesReportFixture();
  return {
    id: 'case-1',
    sourceReportId: sourceReport.id,
    sourceReport,
    status: 'PURCHASED',
    assigneeUserId: 'user-1',
    assigneeEmail: 'sale@phongvu.vn',
    assigneeName: 'Sale User',
    followUpCount: 2,
    lastFollowUpAt: new Date('2026-07-03T02:00:00.000Z'),
    lastFollowUpByUserId: 'user-1',
    lastFollowUpByEmail: 'sale@phongvu.vn',
    lastFollowUpByName: 'Sale User',
    closedAt: new Date('2026-07-03T02:00:00.000Z'),
    createdAt: new Date('2026-07-01T01:30:00.000Z'),
    updatedAt: new Date('2026-07-03T02:00:00.000Z'),
    entries: [
      {
        id: 'entry-1',
        sequenceNumber: 1,
        outcome: 'NOT_PURCHASED',
        notPurchasedReason: 'PRICE_HESITATION',
        notPurchasedOtherReason: null,
        actorUserId: 'user-1',
        actorEmail: 'sale@phongvu.vn',
        actorName: 'Sale User',
        purchasedReportId: null,
        contactedAt: new Date('2026-07-02T02:00:00.000Z'),
      },
      {
        id: 'entry-2',
        sequenceNumber: 2,
        outcome: 'PURCHASED',
        notPurchasedReason: null,
        notPurchasedOtherReason: null,
        actorUserId: 'user-1',
        actorEmail: 'sale@phongvu.vn',
        actorName: 'Sale User',
        purchasedReportId: 'report-purchased',
        contactedAt: new Date('2026-07-03T02:00:00.000Z'),
      },
    ],
  };
}

function salesReportFixture() {
  return {
    id: 'report-1',
    reportType: 'PURCHASED',
    entrySource: 'COMEBACK',
    submittedAt: new Date('2026-07-01T01:30:00.000Z'),
    orderCode: '2607010001',
    customerName: 'Nguyen Van A',
    customerPhone: '0900000000',
    customerContactChannels: ['PHONE', 'ZALO_PERSONAL', 'ZALO_OA'],
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
    erpLifecycleStatus: 'COMPLETED_PARTIAL_RETURN',
    erpHasReturnedFullItems: false,
    erpReturnedAfterTaxAmount: 108000,
    erpTerminalName: 'CP01',
    erpGrandTotal: 1080000,
    erpPaymentMethods: ['cash', 'bank_transfer'],
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
