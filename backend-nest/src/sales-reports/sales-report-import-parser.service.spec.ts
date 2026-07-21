import * as XLSX from 'xlsx';
import { SalesReportImportParserService } from './sales-report-import-parser.service';

describe('SalesReportImportParserService', () => {
  const parser = new SalesReportImportParserService();

  it('normalizes the historical template without inventing missing answers', () => {
    const result = parser.parse(
      workbookFile([
        [
          'Timestamp',
          'Email Address',
          'MSNV bán hàng',
          'Họ & Tên Khách Hàng',
          'SDT Khách Hàng',
          'Ngành hàng',
          'Khách hàng tìm sản phẩm gì (loại SP và thương hiệu)?',
          'Chốt đơn thành công?',
          'Lí do không mua',
          '',
          'SR ID',
          'Kênh liên lạc',
        ],
        [
          '20/07/2026 10:15',
          'SA@EXAMPLE.COM',
          'NV001',
          'Khách A',
          '+84 912-345-678',
          'Laptop',
          'MacBook Air',
          'Không',
          'Khách tham khảo',
          '',
          'cp02',
          'Điện thoại; Zalo',
        ],
        [
          '20/07/2026 11:00',
          '',
          'NV002',
          'Khách B',
          '0zalo',
          'Phụ kiện',
          'Chuột không dây',
          'Không',
          'Chờ người nhà quyết định',
          '',
          'CP02',
          'Zalo cá nhân | kênh lạ',
        ],
      ]),
    );

    expect(result.totalRows).toBe(2);
    expect(result.fileHash).toMatch(/^[a-f0-9]{64}$/);
    expect(result.rows[0]).toMatchObject({
      rowNumber: 2,
      salespersonEmail: 'sa@example.com',
      sourceSalespersonCode: 'NV001',
      customerPhone: '0912345678',
      storeCode: 'CP02',
      purchased: false,
      notPurchasedReason: 'CUSTOMER_BROWSING',
      customerContactChannels: ['PHONE', 'ZALO_PERSONAL'],
      errors: [],
    });
    expect(result.rows[0].submittedAt?.toISOString()).toBe(
      '2026-07-20T03:15:00.000Z',
    );
    expect(result.rows[1]).toMatchObject({
      customerPhone: null,
      notPurchasedReason: 'OTHER',
      notPurchasedOtherReason: 'Chờ người nhà quyết định',
      customerContactChannels: ['ZALO_PERSONAL'],
      errors: [],
    });
    expect(result.rows[1].warnings).toContain(
      'Kênh liên lạc “kênh lạ” chưa được hỗ trợ.',
    );
  });

  it('rejects workbooks that do not follow the required template', () => {
    expect(() =>
      parser.parse(workbookFile([['Timestamp'], ['20/07/2026']])),
    ).toThrow('File Excel chưa đúng mẫu');
  });

  it('accepts the short product header and keeps missing product detail as a warning', () => {
    const result = parser.parse(
      workbookFile([
        [
          'Timestamp',
          'Email Address',
          'MSNV bán hàng',
          'Họ & Tên Khách Hàng',
          'SDT Khách Hàng',
          'Ngành hàng',
          'sản phẩm khách tìm',
          'Chốt đơn thành công?',
          'Lí do không mua',
          'SR ID',
          'Kênh liên lạc',
        ],
        [
          '20/07/2026 10:15',
          'sa@example.com',
          'NV001',
          'Khách A',
          '0zalo',
          'Laptop',
          '',
          'Không',
          'Khách tham khảo',
          'CP02',
          'ZALO_PERSONAL',
        ],
      ]),
    );

    expect(result.rows[0]).toMatchObject({
      customerNeed: '',
      customerContactChannels: ['ZALO_PERSONAL'],
      errors: [],
    });
    expect(result.rows[0].warnings).toContain(
      'Thiếu sản phẩm khách hàng đang tìm; dữ liệu sẽ được lưu trống để bổ sung sau.',
    );
  });
});

function workbookFile(rows: unknown[][]): Express.Multer.File {
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, XLSX.utils.aoa_to_sheet(rows), 'Data');
  const buffer = XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' });
  return {
    fieldname: 'file',
    originalname: 'khach-chua-mua.xlsx',
    encoding: '7bit',
    mimetype:
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    size: buffer.length,
    buffer,
    destination: '',
    filename: '',
    path: '',
    stream: null as never,
  };
}
