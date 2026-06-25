import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import * as XLSX from 'xlsx';

type Row = Array<string | number | boolean | Date | null | undefined>;

export type AdminUserImportRow = {
  rowNumber: number;
  email: string;
  fullName: string;
  role: string;
  levelCodes: string[];
};

export type AdminUserImportParseResult = {
  rows: AdminUserImportRow[];
  totalRows: number;
  skippedRows: number;
};

const REQUIRED_HEADERS = [
  'email',
  'full_name',
  'system_role',
  'lv0',
  'lv1',
  'lv2',
  'lv3',
  'lv4',
  'lv5',
] as const;

@Injectable()
export class UserImportParserService {
  private readonly logger = new Logger(UserImportParserService.name);

  parse(file: Express.Multer.File): AdminUserImportParseResult {
    if (!file?.buffer?.length) {
      throw new BadRequestException('Vui lòng chọn file nhân sự');
    }

    const workbook = XLSX.read(file.buffer, { cellDates: true });
    const sheetName = workbook.SheetNames[0];
    const sheet = sheetName ? workbook.Sheets[sheetName] : null;
    if (!sheet) {
      throw new BadRequestException('File nhân sự không có sheet dữ liệu');
    }

    const rows = XLSX.utils.sheet_to_json<Row>(sheet, {
      header: 1,
      defval: '',
      raw: false,
      blankrows: false,
    });
    if (rows.length === 0) {
      throw new BadRequestException('File nhân sự không có dữ liệu');
    }

    this.assertHeader(rows[0]);

    const parsed: AdminUserImportRow[] = [];
    const errors: string[] = [];
    const seenEmails = new Set<string>();
    let skippedRows = 0;

    for (let index = 1; index < rows.length; index += 1) {
      const rowNumber = index + 1;
      const row = rows[index];
      if (isBlankRow(row)) {
        skippedRows += 1;
        continue;
      }
      const email = toText(row[0]).toLowerCase();
      const fullName = toText(row[1]);
      const role = toText(row[2]).toUpperCase();
      const levelCodes = row.slice(3, 9).map(toText);
      const rowErrors = this.validateRow({
        rowNumber,
        email,
        fullName,
        role,
        levelCodes,
        seenEmails,
      });
      if (rowErrors.length > 0) {
        errors.push(...rowErrors);
        continue;
      }
      seenEmails.add(email);
      parsed.push({ rowNumber, email, fullName, role, levelCodes });
    }

    if (parsed.length === 0 && errors.length === 0) {
      throw new BadRequestException('File nhân sự không có dòng dữ liệu');
    }
    if (errors.length > 0) {
      throw new BadRequestException(this.errorMessage(errors));
    }

    this.logger.log(
      `Parsed user import file: totalRows=${rows.length - 1} valid=${parsed.length} skipped=${skippedRows}`,
    );
    return { rows: parsed, totalRows: rows.length - 1, skippedRows };
  }

  private assertHeader(row: Row) {
    const headers = row.map((value) => toText(value).toLowerCase());
    const matches =
      headers.length >= REQUIRED_HEADERS.length &&
      REQUIRED_HEADERS.every((header, index) => headers[index] === header);
    if (!matches) {
      throw new BadRequestException(
        'File nhân sự không đúng mẫu: cần header email, full_name, system_role, lv0, lv1, lv2, lv3, lv4, lv5',
      );
    }
  }

  private validateRow(input: {
    rowNumber: number;
    email: string;
    fullName: string;
    role: string;
    levelCodes: string[];
    seenEmails: Set<string>;
  }) {
    const errors: string[] = [];
    if (!input.email) errors.push(`dòng ${input.rowNumber}: thiếu email`);
    if (
      input.email &&
      !/^[^\s@]+@[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$/.test(input.email)
    ) {
      errors.push(`dòng ${input.rowNumber}: email không hợp lệ`);
    }
    if (!input.fullName)
      errors.push(`dòng ${input.rowNumber}: thiếu full_name`);
    if (!input.role) errors.push(`dòng ${input.rowNumber}: thiếu system_role`);
    if (!input.levelCodes.some((value) => value.length > 0)) {
      errors.push(`dòng ${input.rowNumber}: thiếu lv0-lv5`);
    }
    if (input.email && input.seenEmails.has(input.email)) {
      errors.push(`dòng ${input.rowNumber}: email bị trùng trong file`);
    }
    return errors;
  }

  private errorMessage(errors: string[]) {
    const preview = errors.slice(0, 8).join('; ');
    const suffix =
      errors.length > 8 ? `; và ${errors.length - 8} lỗi khác` : '';
    return `File nhân sự chưa hợp lệ: ${preview}${suffix}`;
  }
}

function isBlankRow(row: Row) {
  return row.every((value) => toText(value).length === 0);
}

function toText(value: Row[number]) {
  if (value === null || value === undefined) return '';
  if (value instanceof Date) return value.toISOString();
  return String(value).trim();
}
