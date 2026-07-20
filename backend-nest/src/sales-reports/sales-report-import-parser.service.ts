import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { createHash } from 'node:crypto';
import * as XLSX from 'xlsx';

type Cell = string | number | boolean | Date | null | undefined;
type SheetRow = Cell[];

export type SalesReportImportParsedRow = {
  rowNumber: number;
  submittedAt: Date | null;
  salespersonEmail: string;
  sourceSalespersonCode: string;
  customerName: string;
  customerPhone: string | null;
  customerNeed: string;
  categoryValue: string;
  purchased: boolean | null;
  notPurchasedReason: string | null;
  notPurchasedOtherReason: string | null;
  storeCode: string;
  customerContactChannels: string[];
  errors: string[];
  warnings: string[];
  fingerprint: string;
};

export type SalesReportImportParseResult = {
  fileName: string;
  fileHash: string;
  totalRows: number;
  rows: SalesReportImportParsedRow[];
};

const MAX_DATA_ROWS = 1000;
const REQUIRED_HEADERS = [
  'timestamp',
  'email',
  'salespersonCode',
  'customerName',
  'customerPhone',
  'category',
  'customerNeed',
  'purchased',
  'notPurchasedReason',
  'storeCode',
  'contactChannel',
] as const;

const HEADER_ALIASES: Record<string, (typeof REQUIRED_HEADERS)[number]> = {
  timestamp: 'timestamp',
  thoigian: 'timestamp',
  emailaddress: 'email',
  email: 'email',
  msnvbanhang: 'salespersonCode',
  msnv: 'salespersonCode',
  hovatenkhachhang: 'customerName',
  hotenkhachhang: 'customerName',
  sdtkhachhang: 'customerPhone',
  sodienthoaikhachhang: 'customerPhone',
  nganhhang: 'category',
  khachhangtimsanphamgiloaispvathuonghieu: 'customerNeed',
  khachhangtimsanphamgi: 'customerNeed',
  chotdonthanhcong: 'purchased',
  lidokhongmua: 'notPurchasedReason',
  lydokhongmua: 'notPurchasedReason',
  srid: 'storeCode',
  masr: 'storeCode',
  kenhlienlac: 'contactChannel',
};

const REASON_BY_KEY: Record<string, string> = {
  chuakinhdoanh: 'NOT_SOLD',
  khongkinhdoanh: 'NOT_SOLD',
  dichvu: 'SERVICE',
  khachthamkhao: 'CUSTOMER_BROWSING',
  khachhangthamkhao: 'CUSTOMER_BROWSING',
  thamkhao: 'CUSTOMER_BROWSING',
  khongcohangtrainghiem: 'NO_DEMO_STOCK',
  khongcosanhang: 'NO_AVAILABLE_STOCK',
  khongcohang: 'NO_AVAILABLE_STOCK',
  hethang: 'NO_AVAILABLE_STOCK',
  phanvangia: 'PRICE_HESITATION',
  giacao: 'PRICE_HESITATION',
  sosanhdoithu: 'COMPARE_COMPETITOR',
  sosanhvoigiahaydoithu: 'COMPARE_COMPETITOR',
  thongsokythuatchuatuongthich: 'SPEC_NOT_COMPATIBLE',
  khac: 'OTHER',
};

@Injectable()
export class SalesReportImportParserService {
  private readonly logger = new Logger(SalesReportImportParserService.name);

  parse(file: Express.Multer.File): SalesReportImportParseResult {
    if (!file?.buffer?.length) {
      throw new BadRequestException('Vui lòng chọn file Excel cần nhập.');
    }

    let workbook: XLSX.WorkBook;
    try {
      workbook = XLSX.read(file.buffer, { cellDates: true });
    } catch (error) {
      this.logger.warn(
        `Sales report import workbook read failed: ${String(error)}`,
      );
      throw new BadRequestException(
        'Không đọc được file Excel. Vui lòng kiểm tra lại file .xlsx hoặc .xls.',
      );
    }
    const sheetName = workbook.SheetNames[0];
    const sheet = sheetName ? workbook.Sheets[sheetName] : null;
    if (!sheet) {
      throw new BadRequestException('File Excel chưa có sheet dữ liệu.');
    }
    const sheetRows = XLSX.utils.sheet_to_json<SheetRow>(sheet, {
      header: 1,
      defval: '',
      raw: true,
      blankrows: false,
    });
    if (sheetRows.length === 0) {
      throw new BadRequestException('File Excel chưa có dữ liệu.');
    }

    const columns = this.resolveColumns(sheetRows[0]);
    const dataRows = sheetRows
      .slice(1)
      .map((row, index) => ({ row, rowNumber: index + 2 }))
      .filter(({ row }) => !isBlankRow(row));
    if (dataRows.length === 0) {
      throw new BadRequestException('File Excel chưa có dòng dữ liệu.');
    }
    if (dataRows.length > MAX_DATA_ROWS) {
      throw new BadRequestException(
        `Mỗi lần chỉ nhập tối đa ${MAX_DATA_ROWS} dòng dữ liệu.`,
      );
    }

    const rows = dataRows.map(({ row, rowNumber }) =>
      this.parseRow(row, rowNumber, columns),
    );
    const fileHash = createHash('sha256').update(file.buffer).digest('hex');
    this.logger.log(
      `Sales report import parsed: fileHash=${fileHash.slice(0, 12)} totalRows=${rows.length} invalidRows=${rows.filter((row) => row.errors.length > 0).length}`,
    );
    return {
      fileName: safeFileName(file.originalname),
      fileHash,
      totalRows: rows.length,
      rows,
    };
  }

  private resolveColumns(headerRow: SheetRow) {
    const columns = new Map<(typeof REQUIRED_HEADERS)[number], number>();
    headerRow.forEach((value, index) => {
      const alias = HEADER_ALIASES[normalizeKey(value)];
      if (alias && !columns.has(alias)) columns.set(alias, index);
    });
    const missing = REQUIRED_HEADERS.filter((header) => !columns.has(header));
    if (missing.length > 0) {
      throw new BadRequestException(
        'File Excel chưa đúng mẫu. Vui lòng giữ đủ các cột Timestamp, Email Address, MSNV bán hàng, Họ & Tên Khách Hàng, SDT Khách Hàng, Ngành hàng, sản phẩm khách tìm, Chốt đơn thành công?, Lí do không mua, SR ID và Kênh liên lạc.',
      );
    }
    return columns;
  }

  private parseRow(
    row: SheetRow,
    rowNumber: number,
    columns: Map<(typeof REQUIRED_HEADERS)[number], number>,
  ): SalesReportImportParsedRow {
    const value = (key: (typeof REQUIRED_HEADERS)[number]) =>
      row[columns.get(key)!];
    const errors: string[] = [];
    const warnings: string[] = [];
    const submittedAt = parseTimestamp(value('timestamp'));
    const salespersonEmail = toText(value('email')).toLowerCase();
    const sourceSalespersonCode = toText(value('salespersonCode')).slice(0, 80);
    const customerName = toText(value('customerName'));
    const rawPhone = toText(value('customerPhone'));
    const customerPhone = normalizePhone(rawPhone);
    const customerNeed = toText(value('customerNeed'));
    const categoryValue = toText(value('category'));
    const purchased = parseBoolean(value('purchased'));
    const rawReason = toText(value('notPurchasedReason'));
    const storeCode = toText(value('storeCode')).toUpperCase();
    const reason = mapReason(rawReason);
    const channels = parseContactChannels(
      value('contactChannel'),
      customerPhone,
      normalizeKey(rawPhone) === '0zalo',
    );

    if (!submittedAt) errors.push('Thời gian báo cáo không hợp lệ.');
    if (!customerName) errors.push('Thiếu họ tên khách hàng.');
    if (customerName.length > 120)
      errors.push('Họ tên khách hàng dài quá 120 ký tự.');
    if (rawPhone && !customerPhone && normalizeKey(rawPhone) !== '0zalo') {
      warnings.push('Số điện thoại không hợp lệ nên không được lưu.');
    }
    if (!categoryValue) errors.push('Thiếu ngành hàng.');
    if (!customerNeed) errors.push('Thiếu sản phẩm khách hàng đang tìm.');
    if (customerNeed.length > 1000)
      errors.push('Nhu cầu khách hàng dài quá 1.000 ký tự.');
    if (purchased === null)
      errors.push('Giá trị Chốt đơn thành công? không hợp lệ.');
    if (purchased === false && !rawReason)
      errors.push('Thiếu lý do không mua.');
    if (!storeCode) errors.push('Thiếu SR ID.');
    warnings.push(...channels.warnings);

    const notPurchasedReason = purchased === false ? reason.code : null;
    const notPurchasedOtherReason =
      purchased === false && reason.code === 'OTHER'
        ? rawReason.slice(0, 500)
        : null;
    const fingerprint = createHash('sha256')
      .update(
        JSON.stringify({
          submittedAt: submittedAt?.toISOString() ?? '',
          salespersonEmail,
          sourceSalespersonCode: normalizeKey(sourceSalespersonCode),
          customerName: normalizeKey(customerName),
          customerPhone: customerPhone ?? '',
          customerNeed: normalizeKey(customerNeed),
          categoryValue: normalizeKey(categoryValue),
          purchased,
          notPurchasedReason,
          notPurchasedOtherReason: normalizeKey(notPurchasedOtherReason),
          storeCode,
          channels: [...channels.codes].sort(),
        }),
      )
      .digest('hex');

    return {
      rowNumber,
      submittedAt,
      salespersonEmail,
      sourceSalespersonCode,
      customerName,
      customerPhone,
      customerNeed,
      categoryValue,
      purchased,
      notPurchasedReason,
      notPurchasedOtherReason,
      storeCode,
      customerContactChannels: channels.codes,
      errors,
      warnings,
      fingerprint,
    };
  }
}

function isBlankRow(row: SheetRow) {
  return row.every((value) => toText(value).length === 0);
}

function toText(value: Cell) {
  if (value === null || value === undefined) return '';
  if (value instanceof Date) return value.toISOString();
  return String(value).trim();
}

function normalizeKey(value: unknown) {
  return String(value ?? '')
    .trim()
    .toLowerCase()
    .replace(/đ/g, 'd')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '');
}

function normalizePhone(value: string) {
  if (!value || normalizeKey(value) === '0zalo') return null;
  let digits = value.replace(/\D/g, '');
  if (digits.startsWith('84') && digits.length === 11)
    digits = `0${digits.slice(2)}`;
  if (digits.length === 9) digits = `0${digits}`;
  return /^0\d{9}$/.test(digits) ? digits : null;
}

function parseBoolean(value: Cell) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number' && (value === 0 || value === 1))
    return value === 1;
  const key = normalizeKey(value);
  if (['co', 'yes', 'true', '1'].includes(key)) return true;
  if (['khong', 'no', 'false', '0'].includes(key)) return false;
  return null;
}

function parseTimestamp(value: Cell) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (typeof value === 'number' && Number.isFinite(value)) {
    const parsed = XLSX.SSF.parse_date_code(value);
    if (!parsed) return null;
    return new Date(
      Date.UTC(
        parsed.y,
        parsed.m - 1,
        parsed.d,
        parsed.H - 7,
        parsed.M,
        parsed.S,
      ),
    );
  }
  const text = toText(value);
  const local = text.match(
    /^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$/,
  );
  if (local) {
    const [, day, month, year, hour = '0', minute = '0', second = '0'] = local;
    const numeric = {
      day: +day,
      month: +month,
      year: +year,
      hour: +hour,
      minute: +minute,
      second: +second,
    };
    const daysInMonth =
      numeric.month >= 1 && numeric.month <= 12
        ? new Date(Date.UTC(numeric.year, numeric.month, 0)).getUTCDate()
        : 0;
    if (
      numeric.year < 1900 ||
      numeric.month < 1 ||
      numeric.month > 12 ||
      numeric.day < 1 ||
      numeric.day > daysInMonth ||
      numeric.hour < 0 ||
      numeric.hour > 23 ||
      numeric.minute < 0 ||
      numeric.minute > 59 ||
      numeric.second < 0 ||
      numeric.second > 59
    ) {
      return null;
    }
    const result = new Date(
      Date.UTC(
        numeric.year,
        numeric.month - 1,
        numeric.day,
        numeric.hour - 7,
        numeric.minute,
        numeric.second,
      ),
    );
    return Number.isNaN(result.getTime()) ? null : result;
  }
  const parsed = new Date(text);
  return text && !Number.isNaN(parsed.getTime()) ? parsed : null;
}

function mapReason(value: string) {
  if (!value) return { code: null };
  return { code: REASON_BY_KEY[normalizeKey(value)] ?? 'OTHER' };
}

function parseContactChannels(
  value: Cell,
  phone: string | null,
  legacyZalo: boolean,
) {
  const codes = new Set<string>();
  const warnings: string[] = [];
  if (phone) codes.add('PHONE');
  if (legacyZalo) codes.add('ZALO_PERSONAL');
  const items = toText(value)
    .split(/[;,|]/)
    .map((item) => item.trim())
    .filter(Boolean);
  for (const item of items) {
    const key = normalizeKey(item);
    if (['phone', 'sdt', 'sodienthoai', 'dienthoai'].includes(key)) {
      if (phone) codes.add('PHONE');
      else
        warnings.push(
          'Kênh điện thoại bị bỏ qua vì số điện thoại không hợp lệ.',
        );
    } else if (['zalo', 'zalocanhan'].includes(key)) {
      codes.add('ZALO_PERSONAL');
    } else if (['zalooa', 'oa'].includes(key)) {
      codes.add('ZALO_OA');
    } else {
      warnings.push(`Kênh liên lạc “${item.slice(0, 40)}” chưa được hỗ trợ.`);
    }
  }
  return { codes: Array.from(codes), warnings };
}

function safeFileName(value: string) {
  return String(value || 'du-lieu-khach-chua-mua.xlsx')
    .replace(/[\\/]/g, '_')
    .slice(0, 255);
}
