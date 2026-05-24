import * as XLSX from 'xlsx';
import { ManualInventoryParserService } from './manual-inventory-parser.service';

describe('ManualInventoryParserService', () => {
  const service = new ManualInventoryParserService();

  it('maps the manual inventory Excel columns to the canonical FIFO schema', () => {
    const file = workbookFile([
      ['Tồn kho vật lý theo bin'],
      ['Thời điểm xuất: 16:18:25 ngày 24-05-2026'],
      [
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
      ],
      [
        1,
        251010231,
        'MacBook Pro',
        'MDE14SA/A',
        'Cái',
        1,
        'SMYXFX06J76',
        'Thông thường',
        '',
        'Apple',
        'NH05',
        'Apple',
        'NH05-01-01-01',
        'Macbook',
        '= 46113.3117257735 + TIME(7,0,0)',
        'CP62',
        'PHAN DANG LUU',
        'Trưng bày hàng bán mới',
        '01-VHH.01-01-a',
        '01-VHH.01-01-a',
        'Hàng bán',
      ],
    ]);

    const result = service.parse(file);

    expect(result).toMatchObject({
      totalRows: 1,
      skippedRows: 0,
      items: [
        {
          id: 'CP62:SMYXFX06J76',
          srCode: 'CP62',
          srName: 'PHAN DANG LUU',
          sku: '251010231',
          skuName: 'MacBook Pro',
          serialNumber: 'SMYXFX06J76',
          serialType: 'Thông thường',
          brand: 'Apple',
          categoryId: 'NH05',
          categoryName: 'Apple',
          subcategoryId: 'NH05-01-01-01',
          subcategoryName: 'Macbook',
          partNumber: 'MDE14SA/A',
          unit: 'Cái',
          bin: '01-VHH.01-01-a',
          binName: '01-VHH.01-01-a',
          zone: 'Trưng bày hàng bán mới',
          stockType: 'Hàng bán',
          count: 1,
        },
      ],
    });
    expect(result.items[0].manualImportDate?.toISOString()).toBe(
      '2026-04-01T00:00:00.000Z',
    );
  });
});

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
