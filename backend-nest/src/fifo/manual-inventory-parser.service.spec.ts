import * as XLSX from 'xlsx';
import { ManualInventoryParserService } from './manual-inventory-parser.service';

describe('ManualInventoryParserService', () => {
  const service = new ManualInventoryParserService();

  it('maps the manual inventory Excel columns to the canonical BigQuery schema', () => {
    const file = workbookFile([
      ['Tồn kho vật lý theo bin'],
      ['Thời điểm xuất: 16:18:25 ngày 24-05-2026'],
      manualHeaders(),
      [
        1,
        250403171,
        'Product 250403171',
        'PART-1',
        'Cái',
        1,
        '225ABC967',
        'Thông thường',
        '',
        'Apple',
        'NH05',
        'Apple',
        'NH05-02-01-01',
        'Iphone',
        '= 45755.3117257735 + TIME(7,0,0)',
        'CP62',
        'ĐỊA ĐIỂM KINH DOANH 39',
        'Trưng bày hàng bán mới',
        '06-VK5.03-01-d',
        '06-VK5.03-01-d',
        'Hàng bán',
        '0.001',
        '0',
      ],
    ]);

    const result = service.parse(file);

    expect(result).toMatchObject({
      totalRows: 1,
      skippedRows: 0,
      items: [
        {
          itemKey: 'CP62:225ABC967',
          branchId: 'CP62',
          branchName: 'ĐỊA ĐIỂM KINH DOANH 39',
          sku: '250403171',
          skuName: 'Product 250403171',
          serial: '225ABC967',
          brand: 'Apple',
          categoryId: 'NH05',
          categoryName: 'Apple',
          subCategoryId: 'NH05-02-01-01',
          subCategoryName: 'Iphone',
          location: '06-VK5.03-01-d',
          binZone: 'Trưng bày hàng bán mới',
          binType: 'Hàng bán mới tại kho',
          inventory: 1,
          manualPayload: expect.objectContaining({
            part_number: 'PART-1',
            unit: 'Cái',
            serial_type: 'Thông thường',
            bin_name: '06-VK5.03-01-d',
          }),
        },
      ],
    });
    expect(result.items[0].dateImportCompany).toBeNull();
    expect(result.items[0].dateImportSite?.toISOString()).toBe(
      '2025-04-08T00:00:00.000Z',
    );
  });

  it('parses the CP62 SKU 250403171 manual shape as two rows', () => {
    const file = workbookFile([
      ['Tồn kho vật lý theo bin'],
      ['Thời điểm xuất: 16:18:25 ngày 24-05-2026'],
      manualHeaders(),
      manualCp62Row(1, '225AAA967'),
      manualCp62Row(2, '225AAA962'),
    ]);

    const result = service.parse(file);

    expect(result.items).toHaveLength(2);
    expect(result.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          branchId: 'CP62',
          sku: '250403171',
          location: '06-VK5.03-01-d',
          binType: 'Hàng bán mới tại kho',
        }),
      ]),
    );
    expect(result.items[0].dateImportSite?.toISOString()).toBe(
      '2026-03-04T00:00:00.000Z',
    );
  });
});

function manualHeaders() {
  return [
    'STT',
    'Mã sản phẩm',
    'Tên sản phẩm',
    'Part number',
    'ĐVT',
    'Số lượng',
    'Số Serial',
    'Loại Serial',
    'Ngày đánh dấu chuyển loại Serial',
    'Thương hiệu',
    'Mã ngành hàng',
    'Tên ngành hàng',
    'Mã nhóm sản phẩm',
    'Tên nhóm sản phẩm',
    'Ngày nhập kho',
    'Mã chi nhánh',
    'Tên chi nhánh',
    'Zone',
    'Mã Bin',
    'Tên Bin',
    'Loại hàng',
    'Tổng thể tích sản phẩm',
    'Thể tích Bin',
  ];
}

function manualCp62Row(index: number, serial: string) {
  return [
    index,
    250403171,
    'Product 250403171',
    '',
    'Cái',
    1,
    serial,
    'Thông thường',
    '',
    'Apple',
    'NH05',
    'Apple',
    'NH05-02-01-01',
    'Iphone',
    '= 46085.0000000000 + TIME(7,0,0)',
    'CP62',
    'ĐỊA ĐIỂM KINH DOANH 39',
    'Trưng bày hàng bán mới',
    '06-VK5.03-01-d',
    '06-VK5.03-01-d',
    'Hàng bán',
    '0.001',
    '0',
  ];
}

function workbookFile(rows: unknown[][]): Express.Multer.File {
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, XLSX.utils.aoa_to_sheet(rows), 'Main');
  const buffer = XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' });
  return {
    buffer,
    originalname: 'inventory.xlsx',
    mimetype:
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  } as Express.Multer.File;
}
