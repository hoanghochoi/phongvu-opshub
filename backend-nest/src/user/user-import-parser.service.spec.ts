import * as XLSX from 'xlsx';
import { BadRequestException } from '@nestjs/common';
import { UserImportParserService } from './user-import-parser.service';

describe('UserImportParserService', () => {
  const service = new UserImportParserService();

  it('parses user import rows with the required template headers', () => {
    const result = service.parse(
      excelFile([
        [
          'email',
          'full_name',
          'system_role',
          'lv0',
          'lv1',
          'lv2',
          'lv3',
          'lv4',
          'lv5',
        ],
        [
          'staff@phongvu.vn',
          'Nguyen Van A',
          'USER',
          'DOMAIN_PHONGVU_VN',
          '',
          '',
          '',
          'CP62',
          'SA',
        ],
      ]),
    );

    expect(result.totalRows).toBe(1);
    expect(result.skippedRows).toBe(0);
    expect(result.rows[0]).toMatchObject({
      rowNumber: 2,
      email: 'staff@phongvu.vn',
      fullName: 'Nguyen Van A',
      role: 'USER',
      levelCodes: ['DOMAIN_PHONGVU_VN', '', '', '', 'CP62', 'SA'],
    });
  });

  it('rejects a template with no data rows', () => {
    expect(() =>
      service.parse(
        excelFile([
          [
            'email',
            'full_name',
            'system_role',
            'lv0',
            'lv1',
            'lv2',
            'lv3',
            'lv4',
            'lv5',
          ],
        ]),
      ),
    ).toThrow(BadRequestException);
  });

  it('rejects files with missing required headers', () => {
    expect(() =>
      service.parse(excelFile([['email', 'full_name', 'lv0']])),
    ).toThrow('File nhân sự không đúng mẫu');
  });

  it('rejects duplicate emails in the same file', () => {
    expect(() =>
      service.parse(
        excelFile([
          [
            'email',
            'full_name',
            'system_role',
            'lv0',
            'lv1',
            'lv2',
            'lv3',
            'lv4',
            'lv5',
          ],
          ['dup@phongvu.vn', 'A', 'USER', 'DOMAIN_PHONGVU_VN'],
          ['dup@phongvu.vn', 'B', 'USER', 'DOMAIN_PHONGVU_VN'],
        ]),
      ),
    ).toThrow('email bị trùng trong file');
  });
});

function excelFile(rows: unknown[][]) {
  const workbook = XLSX.utils.book_new();
  const sheet = XLSX.utils.aoa_to_sheet(rows);
  XLSX.utils.book_append_sheet(workbook, sheet, 'Sheet1');
  const buffer = XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' });
  return {
    buffer,
    originalname: 'users.xlsx',
    mimetype:
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  } as Express.Multer.File;
}
