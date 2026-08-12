import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SalesHistoryImportParserService } from './sales-history-import-parser.service';
import { SalesReportCategoriesService } from './sales-report-categories.service';

describe('SalesHistoryImportParserService', () => {
  const prisma = {
    salesReportCategoryGroup: {
      upsert: jest.fn(({ create }: any) => Promise.resolve(create)),
    },
    $transaction: jest.fn((items: Array<Promise<unknown>>) =>
      Promise.all(items),
    ),
  };
  const categories = new SalesReportCategoriesService(prisma as any);
  const parser = new SalesHistoryImportParserService(categories);
  const wideMetricHeader =
    'Extended insurance,Laptop,PC,Assembled PC,Apple,Monitor,Printer,Accessories';
  let directory: string;

  beforeEach(async () => {
    directory = await mkdtemp(join(tmpdir(), 'opshub-history-parser-'));
  });

  afterEach(async () => {
    await rm(directory, { recursive: true, force: true });
  });

  it('autodetects BOM CSV and streams signed canonical rows', async () => {
    const path = join(directory, 'history.csv');
    await writeFile(
      path,
      `\uFEFFReport date,Branch code,Order code,Net VAT revenue,Email,${wideMetricHeader}\r\n` +
        '31/07/2025,cp01,ORDER-1,12500000,sale@phongvu.vn,0,1,0,0,0,0,0,2\r\n' +
        '31/07/2025,CP01,ORDER-1,-500000,sale@phongvu.vn,0,-1,0,0,0,0,0,0\r\n',
      'utf8',
    );
    const rows: any[] = [];

    const metadata = await parser.parse(path, async (chunk) => {
      rows.push(...chunk);
    });

    expect(metadata).toMatchObject({
      encoding: 'utf-8',
      delimiter: ',',
      totalRows: 2,
      sourceFormat: 'legacy-wide',
      mappedCategoryRows: 0,
      unmappedCategoryRows: 0,
    });
    expect(metadata.sourceHash).toMatch(/^[a-f0-9]{64}$/);
    expect(rows).toEqual([
      expect.objectContaining({
        date: '2025-07-31',
        storeCode: 'CP01',
        orderCode: 'ORDER-1',
        salespersonEmail: 'sale@phongvu.vn',
        signedRevenue: 12500000,
        quantities: expect.objectContaining({
          laptopQuantity: 1,
          accessoriesQuantity: 2,
        }),
        errorCodes: [],
      }),
      expect.objectContaining({
        signedRevenue: -500000,
        quantities: expect.objectContaining({ laptopQuantity: -1 }),
      }),
    ]);
  });

  it('autodetects TSV and accepts exact HRM identity', async () => {
    const path = join(directory, 'history.tsv');
    await writeFile(
      path,
      'Ngày báo cáo\tMã SR\tMã đơn hàng\tDoanh thu đã gồm VAT\tHRM\tNgành hàng\tSố lượng\n' +
        '2025-07-01\tCP02\tORDER-2\t1000\tNV002\tPhụ kiện\t3\n',
      'utf8',
    );
    const rows: any[] = [];

    const metadata = await parser.parse(path, async (chunk) =>
      rows.push(...chunk),
    );

    expect(metadata.delimiter).toBe('\t');
    expect(metadata.sourceFormat).toBe('legacy-category');
    expect(rows[0]).toMatchObject({
      salespersonCode: 'NV002',
      quantities: expect.objectContaining({ accessoriesQuantity: 3 }),
      errorCodes: [],
    });
  });

  it('blocks the whole batch when a row cannot be routed to date and showroom', async () => {
    const path = join(directory, 'bad.csv');
    await writeFile(
      path,
      'Report date,Branch code,Order code,Net VAT revenue,Email,Category,Quantity\n' +
        'not-a-date,CP01,ORDER-1,1000,sale@phongvu.vn,Laptop,1\n',
      'utf8',
    );

    await expect(parser.parse(path, async () => undefined)).rejects.toThrow(
      'thiếu hoặc không đọc được Ngày báo cáo/Mã showroom',
    );
  });

  it('validates UTF-8 across the whole stream instead of only the preview', async () => {
    const path = join(directory, 'late-invalid.csv');
    const header =
      'Report date,Branch code,Order code,Net VAT revenue,Email,Category,Quantity\n';
    const validRows =
      '2025-07-01,CP01,ORDER-1,1000,sale@phongvu.vn,Laptop,1\n'.repeat(1500);
    await writeFile(
      path,
      Buffer.concat([
        Buffer.from(
          header + validRows + '2025-07-01,CP01,ORDER-2,1000,',
          'utf8',
        ),
        Buffer.from([0x96]),
        Buffer.from('@phongvu.vn,Laptop,1\n', 'ascii'),
      ]),
    );

    const rows: any[] = [];
    const metadata = await parser.parse(path, async (chunk) =>
      rows.push(...chunk),
    );

    expect(metadata.encoding).toBe('windows-1258');
    expect(rows.length).toBe(1501);
  });

  it('rejects a partial wide metric header instead of authorizing missing metrics as zero', async () => {
    const path = join(directory, 'partial-wide.csv');
    await writeFile(
      path,
      'Report date,Branch code,Order code,Net VAT revenue,Email,Laptop,Accessories\n' +
        '2025-07-01,CP01,ORDER-1,1000,sale@phongvu.vn,1,2\n',
      'utf8',
    );

    await expect(parser.parse(path, async () => undefined)).rejects.toThrow(
      'dùng đủ 8 cột số lượng',
    );
  });

  it('quarantines a wide row with an absent metric value', async () => {
    const path = join(directory, 'partial-wide-row.csv');
    await writeFile(
      path,
      `Report date,Branch code,Order code,Net VAT revenue,Email,${wideMetricHeader}\n` +
        '2025-07-01,CP01,ORDER-1,1000,sale@phongvu.vn,0,1,0,0,0,,0,2\n',
      'utf8',
    );
    const rows: any[] = [];

    await parser.parse(path, async (chunk) => rows.push(...chunk));

    expect(rows[0].quantities.monitorQuantity).toBeNull();
    expect(rows[0].errorCodes).toContain('INVALID_monitorQuantity');
  });

  it('quarantines a category row without a recognized category', async () => {
    const path = join(directory, 'unknown-category.tsv');
    await writeFile(
      path,
      'Report date\tBranch code\tOrder code\tNet VAT revenue\tEmail\tCategory\tQuantity\n' +
        '2025-07-01\tCP01\tORDER-1\t1000\tsale@phongvu.vn\tUnknown\t1\n',
      'utf8',
    );
    const rows: any[] = [];

    await parser.parse(path, async (chunk) => rows.push(...chunk));

    expect(rows[0].errorCodes).toContain('INVALID_CATEGORY');
  });

  it('accepts strict Vietnamese and international grouped integer formats', async () => {
    const path = join(directory, 'grouped-numbers.tsv');
    await writeFile(
      path,
      'Report date\tBranch code\tOrder code\tNet VAT revenue\tEmail\tCategory\tQuantity\n' +
        '2025-07-01\tCP01\tORDER-1\t12.345.000,00\tsale@phongvu.vn\tLaptop\t1.000\n' +
        '2025-07-01\tCP01\tORDER-2\t12,345,000.00\tsale@phongvu.vn\tAccessories\t(1.000)\n',
      'utf8',
    );
    const rows: any[] = [];

    await parser.parse(path, async (chunk) => rows.push(...chunk));

    expect(rows).toEqual([
      expect.objectContaining({
        signedRevenue: 12345000,
        quantities: expect.objectContaining({ laptopQuantity: 1000 }),
        errorCodes: [],
      }),
      expect.objectContaining({
        signedRevenue: 12345000,
        quantities: expect.objectContaining({ accessoriesQuantity: -1000 }),
        errorCodes: [],
      }),
    ]);
  });

  it('quarantines scientific notation, embedded text, and malformed grouping or decimals', async () => {
    const path = join(directory, 'invalid-numbers.tsv');
    await writeFile(
      path,
      'Report date\tBranch code\tOrder code\tNet VAT revenue\tEmail\tCategory\tQuantity\n' +
        '2025-07-01\tCP01\tORDER-1\t1e3\tsale@phongvu.vn\tLaptop\t1\n' +
        '2025-07-01\tCP01\tORDER-2\tabc123\tsale@phongvu.vn\tLaptop\t1\n' +
        '2025-07-01\tCP01\tORDER-3\t12,34,567\tsale@phongvu.vn\tLaptop\t1\n' +
        '2025-07-01\tCP01\tORDER-4\t1.2.3\tsale@phongvu.vn\tLaptop\t1\n' +
        '2025-07-01\tCP01\tORDER-5\t1.000,25\tsale@phongvu.vn\tLaptop\tabc123\n',
      'utf8',
    );
    const rows: any[] = [];

    await parser.parse(path, async (chunk) => rows.push(...chunk));

    expect(rows).toHaveLength(5);
    for (const finalRow of rows.slice(0, 4)) {
      expect(finalRow.signedRevenue).toBeNull();
      expect(finalRow.errorCodes).toContain('INVALID_REVENUE');
    }
    expect(rows[4].signedRevenue).toBeNull();
    expect(rows[4].quantities.laptopQuantity).toBeNull();
    expect(rows[4].errorCodes).toEqual(
      expect.arrayContaining(['INVALID_REVENUE', 'INVALID_QUANTITY']),
    );
  });

  it('parses the exact 34-column historical export with VAT revenue, HRM ID, canonical order code, and PC component facts', async () => {
    const snapshotSpy = jest.spyOn(categories, 'exactCategoryTypeSnapshot');
    const path = join(directory, 'historical-export.csv');
    await writeFile(
      path,
      [
        historicalExportHeader,
        historicalExportRow({
          orderCode: '25070134938050-01',
          hrmId: 'nv002',
          quantity: '2',
          revenue: '9999999',
          revenueWithVat: '1.25E+7',
          subcatLowestLevelId: 'NH03-01-01-01',
          subcat2Id: 'NH03-01-01',
          skuName: 'CPU AMD Ryzen 5',
        }),
        historicalExportRow({
          orderCode: '25070134938050-02',
          quantity: '3',
          subcatLowestLevelId: '',
          subcat2Id: 'NH03-01-02',
          skuName: 'Mainboard MSI',
        }),
        historicalExportRow({
          orderCode: '25070134938050-03',
          quantity: '4',
          subcatLowestLevelId: 'NH03-01-04-01',
          subcat2Id: 'NH03-01-04',
          skuName: 'RAM Kingston',
        }),
        historicalExportRow({
          orderCode: '25070134938050-04',
          quantity: '5',
          subcatLowestLevelId: 'NH03-01-05-01',
          subcat2Id: 'NH03-01-05',
          skuName: 'SSD Kingston',
        }),
        historicalExportRow({
          orderCode: '25070134938050-05',
          quantity: '6',
          subcatLowestLevelId: 'NH03-01-06-01',
          subcat2Id: 'NH03-01-06',
          skuName: 'Case Corsair',
        }),
        historicalExportRow({
          orderCode: '25070134938050-06',
          quantity: '7',
          subcatLowestLevelId: 'NH03-01-07-01',
          subcat2Id: 'NH03-01-07',
          skuName: 'PSU Corsair',
        }),
      ].join('\n') + '\n',
      'utf8',
    );
    const rows: any[] = [];

    const metadata = await parser.parse(path, async (chunk) =>
      rows.push(...chunk),
    );

    expect(metadata).toMatchObject({
      sourceFormat: 'historical-export',
      mappedCategoryRows: 6,
      unmappedCategoryRows: 0,
    });
    expect(snapshotSpy).toHaveBeenCalledTimes(1);
    snapshotSpy.mockRestore();

    expect(rows).toEqual([
      expect.objectContaining({
        orderCode: '25070134938050',
        salespersonCode: 'NV002',
        signedRevenue: 12_500_000,
        quantities: expect.objectContaining({
          cpuQuantity: 2,
          mainboardQuantity: 0,
        }),
        errorCodes: [],
      }),
      expect.objectContaining({
        orderCode: '25070134938050',
        quantities: expect.objectContaining({
          cpuQuantity: 0,
          mainboardQuantity: 3,
        }),
        errorCodes: [],
      }),
      expect.objectContaining({
        quantities: expect.objectContaining({ memoryQuantity: 4 }),
        errorCodes: [],
      }),
      expect.objectContaining({
        quantities: expect.objectContaining({ storageQuantity: 5 }),
        errorCodes: [],
      }),
      expect.objectContaining({
        quantities: expect.objectContaining({ caseQuantity: 6 }),
        errorCodes: [],
      }),
      expect.objectContaining({
        quantities: expect.objectContaining({ psuQuantity: 7 }),
        errorCodes: [],
      }),
    ]);
  });

  it('handles target, non-target, and unmapped taxonomy rows from the exact historical export', async () => {
    const path = join(directory, 'historical-taxonomy.csv');
    await writeFile(
      path,
      [
        historicalExportHeader,
        historicalExportRow({
          orderCode: '25070134938051-01',
          quantity: '2',
          subcatLowestLevelId: 'NH05-02-01-01',
          subcat2Id: 'NH05-02-01',
          skuName: 'iPhone 16 Pro',
        }),
        historicalExportRow({
          orderCode: '25070134938052-01',
          quantity: '3',
          subcatLowestLevelId: 'NH05-02-01-01',
          subcat2Id: 'NH05-02-01',
          skuName: 'Apple Watch Series 10',
        }),
        historicalExportRow({
          orderCode: '25070134938053-01',
          quantity: '4',
          subcatLowestLevelId: 'NH03-01-08-02',
          subcat2Id: 'NH03-01-08',
          skuName: 'Tản nhiệt khí',
        }),
        historicalExportRow({
          orderCode: '25070134938054-01',
          quantity: '5',
          subcatLowestLevelId: 'NH03-01-98-05',
          subcat2Id: 'NH03-01-98',
          skuName: 'Quà tặng linh kiện',
        }),
        historicalExportRow({
          orderCode: '25070134938055-01',
          quantity: '1',
          subcatLowestLevelId: 'NOT-MAPPED',
          subcat2Id: 'NOT-MAPPED-EITHER',
          skuName: 'Sản phẩm chưa phân loại',
        }),
      ].join('\n') + '\n',
      'utf8',
    );
    const rows: any[] = [];

    const metadata = await parser.parse(path, async (chunk) =>
      rows.push(...chunk),
    );

    expect(metadata).toMatchObject({
      sourceFormat: 'historical-export',
      mappedCategoryRows: 4,
      unmappedCategoryRows: 1,
    });

    expect(rows[0]).toMatchObject({
      signedRevenue: 1_000,
      quantities: expect.objectContaining({ appleQuantity: 2 }),
      errorCodes: [],
    });
    for (const row of rows.slice(1, 4)) {
      expect(row).toMatchObject({
        signedRevenue: 1_000,
        quantities: expect.objectContaining({
          appleQuantity: 0,
          cpuQuantity: 0,
          mainboardQuantity: 0,
          memoryQuantity: 0,
          storageQuantity: 0,
          caseQuantity: 0,
          psuQuantity: 0,
        }),
        errorCodes: [],
      });
    }
    expect(rows[4]).toMatchObject({
      signedRevenue: 1_000,
      errorCodes: expect.arrayContaining(['INVALID_CATEGORY']),
    });
  });

  it('maps every direct export KPI type while preserving non-target rows as zero KPI facts', async () => {
    const path = join(directory, 'historical-direct-kpis.csv');
    const cases = [
      [
        'NH94-01-01',
        'NH94-01',
        'Dịch vụ bảo hiểm rơi vỡ',
        'extendedInsuranceQuantity',
      ],
      ['NH01-01-01-02', 'NH01-01-01', 'Laptop gaming', 'laptopQuantity'],
      ['NH02-01-01-01', 'NH02-01-01', 'Máy tính bộ', 'pcQuantity'],
      ['NH06-01-01-02', 'NH06-01-01', 'Màn hình', 'monitorQuantity'],
      ['NH07-01-01-02-02', 'NH07-01-01', 'Máy in', 'printerQuantity'],
      ['NH05-03-01-01', 'NH05-03-01', 'Chuột Apple', 'accessoriesQuantity'],
    ] as const;
    await writeFile(
      path,
      [
        historicalExportHeader,
        ...cases.map(([lowestId, subcat2Id, skuName], index) =>
          historicalExportRow({
            orderCode: `2507013493810${index}-01`,
            quantity: String(index + 1),
            subcatLowestLevelId: lowestId,
            subcat2Id,
            skuName,
          }),
        ),
      ].join('\n') + '\n',
      'utf8',
    );
    const rows: any[] = [];

    const metadata = await parser.parse(path, async (chunk) =>
      rows.push(...chunk),
    );

    expect(metadata).toMatchObject({
      mappedCategoryRows: cases.length,
      unmappedCategoryRows: 0,
    });
    cases.forEach(([, , , metric], index) => {
      expect(rows[index]).toMatchObject({
        quantities: expect.objectContaining({ [metric]: index + 1 }),
        errorCodes: [],
      });
    });
  });

  it('accepts safe scientific integers only for the exact export and requires 14 contiguous leading order digits', async () => {
    const path = join(directory, 'historical-numeric-boundaries.csv');
    await writeFile(
      path,
      [
        historicalExportHeader,
        historicalExportRow({
          orderCode: '25070134938056-01',
          quantity: '2E+0',
          revenueWithVat: '3.263636E+6',
          subcatLowestLevelId: 'NH03-01-01-01',
          subcat2Id: 'NH03-01-01',
          skuName: 'CPU',
        }),
        historicalExportRow({
          orderCode: '2507013 4938057-01',
          revenueWithVat: '9.007199254740992E+15',
          subcatLowestLevelId: 'NH03-01-01-01',
          subcat2Id: 'NH03-01-01',
          skuName: 'CPU',
        }),
      ].join('\n') + '\n',
      'utf8',
    );
    const rows: any[] = [];

    await parser.parse(path, async (chunk) => rows.push(...chunk));

    expect(rows[0]).toMatchObject({
      orderCode: '25070134938056',
      signedRevenue: 3_263_636,
      quantities: expect.objectContaining({ cpuQuantity: 2 }),
      errorCodes: [],
    });
    expect(rows[1]).toMatchObject({
      orderCode: '',
      signedRevenue: null,
      errorCodes: expect.arrayContaining([
        'MISSING_ORDER_CODE',
        'INVALID_REVENUE',
      ]),
    });

    const maxSafePath = join(directory, 'historical-max-safe.csv');
    await writeFile(
      maxSafePath,
      [
        historicalExportHeader,
        historicalExportRow({
          orderCode: '25070134938058-01',
          revenueWithVat: '9.007199254740991E+15',
          subcatLowestLevelId: 'NH03-01-01-01',
          subcat2Id: 'NH03-01-01',
          skuName: 'CPU',
        }),
      ].join('\n') + '\n',
      'utf8',
    );
    const maxSafeRows: any[] = [];
    await parser.parse(maxSafePath, async (chunk) =>
      maxSafeRows.push(...chunk),
    );
    expect(maxSafeRows[0].signedRevenue).toBe(Number.MAX_SAFE_INTEGER);
  });

  it('rejects excessively precise scientific coefficients before they collapse into valid revenue or quantities', async () => {
    const path = join(directory, 'historical-excessive-scientific.csv');
    await writeFile(
      path,
      [
        historicalExportHeader,
        historicalExportRow({
          orderCode: '25070134938059-01',
          quantity: '2E+0',
          revenueWithVat: '3.263636E+6',
          subcatLowestLevelId: 'NH03-01-01-01',
          subcat2Id: 'NH03-01-01',
          skuName: 'CPU hop le',
        }),
        historicalExportRow({
          orderCode: '25070134938060-01',
          quantity: '2.0000000000000000E+0',
          revenueWithVat: '1.0000000000000000E+0',
          subcatLowestLevelId: 'NH03-01-01-01',
          subcat2Id: 'NH03-01-01',
          skuName: 'CPU coefficient qua dai',
        }),
        historicalExportRow({
          orderCode: '25070134938061-01',
          quantity: `${'0'.repeat(1_000)}2E+0`,
          revenueWithVat: `${'0'.repeat(1_000)}1E+0`,
          subcatLowestLevelId: 'NH03-01-01-01',
          subcat2Id: 'NH03-01-01',
          skuName: 'CPU coefficient nhieu so 0',
        }),
      ].join('\n') + '\n',
      'utf8',
    );
    const rows: any[] = [];

    await parser.parse(path, async (chunk) => rows.push(...chunk));

    expect(rows[0]).toMatchObject({
      signedRevenue: 3_263_636,
      quantities: expect.objectContaining({ cpuQuantity: 2 }),
      errorCodes: [],
    });
    expect(rows[1]).toMatchObject({
      signedRevenue: null,
      quantities: expect.objectContaining({ cpuQuantity: null }),
      errorCodes: expect.arrayContaining([
        'INVALID_REVENUE',
        'INVALID_QUANTITY',
      ]),
    });
    expect(rows[2]).toMatchObject({
      signedRevenue: null,
      quantities: expect.objectContaining({ cpuQuantity: null }),
      errorCodes: expect.arrayContaining([
        'INVALID_REVENUE',
        'INVALID_QUANTITY',
      ]),
    });
  });
});

const historicalExportHeader =
  'Report date,Channel,Store,Branch code,Customer full name,Order code,Export return branch ID,Order type,Email,HRM ID,Salesman,Customer ID,SKU,Doc ID,Sale point per item,SKU name,Dealer type,Brand name,Billing tax code,Cat group ID,Cat group name,Subcat 2 ID,Subcat 2 name,Subcat ID lowest level,Subcat name lowest level,Is delivery,Order note,Terminal code,Terminal name,Platform,Sale point,Quantity,Revenue,Revenue with VAT';

function historicalExportRow({
  orderCode,
  hrmId = 'NV001',
  quantity = '1',
  revenue = '900',
  revenueWithVat = '1000',
  subcatLowestLevelId,
  subcat2Id,
  skuName,
}: {
  orderCode: string;
  hrmId?: string;
  quantity?: string;
  revenue?: string;
  revenueWithVat?: string;
  subcatLowestLevelId: string;
  subcat2Id: string;
  skuName: string;
}) {
  return [
    '2025-07-01',
    'Offline',
    'HCM',
    'CP01',
    'Khach hang',
    orderCode,
    '',
    'SALE',
    'sale@phongvu.vn',
    hrmId,
    'Nhan vien',
    'CUSTOMER-1',
    'SKU-1',
    'DOC-1',
    '0',
    skuName,
    'RETAIL',
    'Brand',
    '',
    'NH03',
    'Computer components',
    subcat2Id,
    'Subcat 2',
    subcatLowestLevelId,
    'Subcat lowest',
    'No',
    '',
    'CP01',
    'Phong Vu',
    'POS',
    '0',
    quantity,
    revenue,
    revenueWithVat,
  ].join(',');
}
