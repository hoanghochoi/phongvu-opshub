import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SalesHistoryImportParserService } from './sales-history-import-parser.service';

describe('SalesHistoryImportParserService', () => {
  const parser = new SalesHistoryImportParserService();
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
});
