import { BadRequestException, Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { TextDecoder } from 'node:util';

export const SALES_HISTORY_IMPORT_MAX_ROWS = 1_000_000;
const PARSER_CHUNK_ROWS = 1_000;
const MAX_RECORD_CHARACTERS = 1_048_576;

export type SalesHistoryMetricKey =
  | 'extendedInsuranceQuantity'
  | 'laptopQuantity'
  | 'pcQuantity'
  | 'assembledPcQuantity'
  | 'appleQuantity'
  | 'monitorQuantity'
  | 'printerQuantity'
  | 'accessoriesQuantity';

export type SalesHistoryParsedRow = {
  rowNumber: number;
  date: string;
  storeCode: string;
  orderCode: string;
  salespersonEmail: string;
  salespersonCode: string;
  signedRevenue: number | null;
  quantities: Record<SalesHistoryMetricKey, number | null>;
  errorCodes: string[];
};

export type SalesHistoryParseMetadata = {
  sourceHash: string;
  encoding: 'utf-8' | 'windows-1258';
  delimiter: ',' | '\t';
  totalRows: number;
};

type ColumnKey =
  | 'date'
  | 'storeCode'
  | 'orderCode'
  | 'email'
  | 'personnelCode'
  | 'salesman'
  | 'revenue'
  | 'category'
  | 'quantity'
  | SalesHistoryMetricKey;

type ResolvedColumns = {
  columns: Map<ColumnKey, number>;
  metricRepresentation: 'wide' | 'category';
};

const METRIC_KEYS: SalesHistoryMetricKey[] = [
  'extendedInsuranceQuantity',
  'laptopQuantity',
  'pcQuantity',
  'assembledPcQuantity',
  'appleQuantity',
  'monitorQuantity',
  'printerQuantity',
  'accessoriesQuantity',
];

const HEADER_ALIASES: Record<string, ColumnKey> = {
  reportdate: 'date',
  orderdate: 'date',
  saledate: 'date',
  ngaybaocao: 'date',
  ngayban: 'date',
  ngay: 'date',
  branchcode: 'storeCode',
  storecode: 'storeCode',
  showroom: 'storeCode',
  showroomcode: 'storeCode',
  masr: 'storeCode',
  macuahang: 'storeCode',
  ordercode: 'orderCode',
  billno: 'orderCode',
  invoiceno: 'orderCode',
  madonhang: 'orderCode',
  sohoadon: 'orderCode',
  email: 'email',
  salespersonemail: 'email',
  hremail: 'email',
  hrm: 'personnelCode',
  employeecode: 'personnelCode',
  personnelcode: 'personnelCode',
  msnv: 'personnelCode',
  manhanvien: 'personnelCode',
  salesman: 'salesman',
  salesperson: 'salesman',
  nhanvienbanhang: 'salesman',
  netvatrevenue: 'revenue',
  netrevenueincludingvat: 'revenue',
  revenueincludingvat: 'revenue',
  totalrevenue: 'revenue',
  doanhthudagomvat: 'revenue',
  doanhthugomvat: 'revenue',
  category: 'category',
  categorytype: 'category',
  productcategory: 'category',
  nganhhang: 'category',
  quantity: 'quantity',
  qty: 'quantity',
  soluong: 'quantity',
  extendedinsurance: 'extendedInsuranceQuantity',
  extendedinsurancequantity: 'extendedInsuranceQuantity',
  baohiemborong: 'extendedInsuranceQuantity',
  laptop: 'laptopQuantity',
  laptopquantity: 'laptopQuantity',
  pc: 'pcQuantity',
  pcquantity: 'pcQuantity',
  assembledpc: 'assembledPcQuantity',
  assembledpcquantity: 'assembledPcQuantity',
  pcrap: 'assembledPcQuantity',
  apple: 'appleQuantity',
  applequantity: 'appleQuantity',
  monitor: 'monitorQuantity',
  monitorquantity: 'monitorQuantity',
  manhinh: 'monitorQuantity',
  printer: 'printerQuantity',
  printerquantity: 'printerQuantity',
  mayin: 'printerQuantity',
  accessories: 'accessoriesQuantity',
  accessoriesquantity: 'accessoriesQuantity',
  phukien: 'accessoriesQuantity',
};

const CATEGORY_METRICS: Record<string, SalesHistoryMetricKey> = {
  extendedinsurance: 'extendedInsuranceQuantity',
  baohiemborong: 'extendedInsuranceQuantity',
  laptop: 'laptopQuantity',
  pc: 'pcQuantity',
  pcbo: 'pcQuantity',
  assembledpc: 'assembledPcQuantity',
  pcrap: 'assembledPcQuantity',
  apple: 'appleQuantity',
  monitor: 'monitorQuantity',
  manhinh: 'monitorQuantity',
  printer: 'printerQuantity',
  mayin: 'printerQuantity',
  accessories: 'accessoriesQuantity',
  phukien: 'accessoriesQuantity',
};

@Injectable()
export class SalesHistoryImportParserService {
  async parse(
    filePath: string,
    onRows: (rows: SalesHistoryParsedRow[]) => Promise<void>,
    isCancelled: () => Promise<boolean> = async () => false,
  ): Promise<SalesHistoryParseMetadata> {
    const detected = await this.detect(filePath);
    const records = new DelimitedRecordDecoder(detected.delimiter);
    let columns: ResolvedColumns | null = null;
    let rowNumber = 0;
    let totalRows = 0;
    let pending: SalesHistoryParsedRow[] = [];

    const consume = async (record: string[]) => {
      rowNumber += 1;
      if (record.every((value) => value.trim() === '')) return;
      if (!columns) {
        columns = this.resolveColumns(record);
        return;
      }
      totalRows += 1;
      if (totalRows > SALES_HISTORY_IMPORT_MAX_ROWS) {
        throw new BadRequestException(
          'Mỗi lần chỉ nhập tối đa 1.000.000 dòng dữ liệu.',
        );
      }
      const parsed = this.parseRow(record, rowNumber, columns);
      if (!parsed.date || !parsed.storeCode) {
        throw new BadRequestException(
          `Dòng ${rowNumber} thiếu hoặc không đọc được Ngày báo cáo/Mã showroom. Tệp chưa được nhập để tránh sai phạm vi.`,
        );
      }
      pending.push(parsed);
      if (pending.length >= PARSER_CHUNK_ROWS) {
        if (await isCancelled()) throw new ImportCancelledError();
        const chunk = pending;
        pending = [];
        await onRows(chunk);
      }
    };

    for await (const text of decodedChunks(filePath, detected.encoding)) {
      for (const record of records.push(text)) await consume(record);
    }
    for (const record of records.finish()) await consume(record);
    if (!columns) throw new BadRequestException('Tệp CSV/TSV chưa có header.');
    if (pending.length > 0) {
      if (await isCancelled()) throw new ImportCancelledError();
      await onRows(pending);
    }
    if (totalRows === 0) {
      throw new BadRequestException('Tệp CSV/TSV chưa có dòng dữ liệu.');
    }
    return { ...detected, totalRows };
  }

  private async detect(filePath: string) {
    const hash = createHash('sha256');
    const utf8 = new TextDecoder('utf-8', { fatal: true });
    let validUtf8 = true;
    let preview = '';
    for await (const chunk of createReadStream(filePath)) {
      const bytes = chunk as Buffer;
      hash.update(bytes);
      if (validUtf8) {
        try {
          const decoded = utf8.decode(bytes, { stream: true });
          if (preview.length < 64 * 1024) {
            preview += decoded.slice(0, 64 * 1024 - preview.length);
          }
        } catch {
          validUtf8 = false;
          preview = '';
        }
      }
    }
    if (validUtf8) {
      try {
        preview += utf8.decode();
      } catch {
        validUtf8 = false;
      }
    }
    const encoding = validUtf8 ? 'utf-8' : 'windows-1258';
    if (!validUtf8) {
      const decoder = new TextDecoder('windows-1258');
      const stream = createReadStream(filePath, { start: 0, end: 64 * 1024 });
      for await (const chunk of stream) {
        preview += decoder.decode(chunk as Buffer, { stream: true });
      }
      preview += decoder.decode();
    }
    preview = preview.replace(/^\uFEFF/, '');
    const firstRecord = preview.split(/\r?\n/, 1)[0] ?? '';
    const delimiter =
      countOutsideQuotes(firstRecord, '\t') >
      countOutsideQuotes(firstRecord, ',')
        ? '\t'
        : ',';
    return {
      sourceHash: hash.digest('hex'),
      encoding: encoding as 'utf-8' | 'windows-1258',
      delimiter: delimiter as ',' | '\t',
    };
  }

  private resolveColumns(header: string[]): ResolvedColumns {
    const columns = new Map<ColumnKey, number>();
    header.forEach((value, index) => {
      const alias = HEADER_ALIASES[normalizeKey(value.replace(/^\uFEFF/, ''))];
      if (alias && !columns.has(alias)) columns.set(alias, index);
    });
    const required: ColumnKey[] = ['date', 'storeCode', 'orderCode', 'revenue'];
    const missing = required.filter((key) => !columns.has(key));
    if (!columns.has('email') && !columns.has('personnelCode')) {
      missing.push('email');
    }
    if (missing.length > 0) {
      throw new BadRequestException(
        'Tệp chưa đúng mẫu. Cần có Ngày báo cáo, Mã showroom, Mã đơn hàng, Doanh thu đã gồm VAT và Email hoặc HRM.',
      );
    }
    const wideMetricCount = METRIC_KEYS.filter((key) =>
      columns.has(key),
    ).length;
    const hasCategory = columns.has('category');
    const hasQuantity = columns.has('quantity');
    const hasCompleteWideMetrics = wideMetricCount === METRIC_KEYS.length;
    const hasCategoryMetrics = hasCategory && hasQuantity;
    if (
      (wideMetricCount > 0 && !hasCompleteWideMetrics) ||
      hasCategory !== hasQuantity ||
      hasCompleteWideMetrics === hasCategoryMetrics
    ) {
      throw new BadRequestException(
        'Tệp chưa đúng mẫu sản phẩm. Hãy dùng đủ 8 cột số lượng hoặc dùng đúng cặp cột Ngành hàng và Số lượng.',
      );
    }
    return {
      columns,
      metricRepresentation: hasCompleteWideMetrics ? 'wide' : 'category',
    };
  }

  private parseRow(
    record: string[],
    rowNumber: number,
    resolved: ResolvedColumns,
  ): SalesHistoryParsedRow {
    const { columns, metricRepresentation } = resolved;
    const value = (key: ColumnKey) =>
      columns.has(key) ? String(record[columns.get(key)!] ?? '').trim() : '';
    const date = parseDateOnly(value('date'));
    const storeCode = normalizeStoreCode(value('storeCode'));
    const orderCode = value('orderCode').replace(/\s+/g, '').slice(0, 120);
    const salespersonEmail = value('email').toLowerCase().slice(0, 200);
    const salespersonCode = value('personnelCode').toUpperCase().slice(0, 80);
    const signedRevenue = parseSignedInteger(value('revenue'));
    const quantities = Object.fromEntries(
      METRIC_KEYS.map((key) => [
        key,
        metricRepresentation === 'wide' ? parseSignedInteger(value(key)) : 0,
      ]),
    ) as Record<SalesHistoryMetricKey, number | null>;
    const errorCodes: string[] = [];
    if (metricRepresentation === 'category') {
      const category = CATEGORY_METRICS[normalizeKey(value('category'))];
      const quantity = parseSignedInteger(value('quantity'));
      if (!category) errorCodes.push('INVALID_CATEGORY');
      if (quantity === null) errorCodes.push('INVALID_QUANTITY');
      if (category) quantities[category] = quantity;
    }
    if (!orderCode) errorCodes.push('MISSING_ORDER_CODE');
    if (!salespersonEmail && !salespersonCode) {
      errorCodes.push('MISSING_SALESPERSON_IDENTITY');
    }
    if (signedRevenue === null) errorCodes.push('INVALID_REVENUE');
    for (const key of METRIC_KEYS) {
      if (quantities[key] === null) errorCodes.push(`INVALID_${key}`);
    }
    return {
      rowNumber,
      date,
      storeCode,
      orderCode,
      salespersonEmail,
      salespersonCode,
      signedRevenue,
      quantities,
      errorCodes,
    };
  }
}

export class ImportCancelledError extends Error {
  constructor() {
    super('Sales history import cancelled');
    this.name = 'ImportCancelledError';
  }
}

class DelimitedRecordDecoder {
  private readonly row: string[] = [];
  private field = '';
  private inQuotes = false;
  private pendingQuote = false;
  private recordCharacters = 0;

  constructor(private readonly delimiter: ',' | '\t') {}

  push(text: string) {
    const records: string[][] = [];
    for (const char of text.replace(/^\uFEFF/, '')) {
      this.recordCharacters += 1;
      if (this.recordCharacters > MAX_RECORD_CHARACTERS) {
        throw new BadRequestException('Một dòng CSV/TSV dài quá giới hạn.');
      }
      if (this.pendingQuote) {
        if (char === '"') {
          this.field += '"';
          this.pendingQuote = false;
          continue;
        }
        this.pendingQuote = false;
        this.inQuotes = false;
      }
      if (this.inQuotes) {
        if (char === '"') this.pendingQuote = true;
        else this.field += char;
        continue;
      }
      if (char === '"' && this.field.length === 0) {
        this.inQuotes = true;
      } else if (char === this.delimiter) {
        this.row.push(this.field);
        this.field = '';
      } else if (char === '\n') {
        if (this.field.endsWith('\r')) this.field = this.field.slice(0, -1);
        this.row.push(this.field);
        records.push(this.row.splice(0));
        this.field = '';
        this.recordCharacters = 0;
      } else {
        this.field += char;
      }
    }
    return records;
  }

  finish() {
    if (this.pendingQuote) {
      this.pendingQuote = false;
      this.inQuotes = false;
    }
    if (this.inQuotes) {
      throw new BadRequestException(
        'Tệp có ô dữ liệu chưa đóng dấu ngoặc kép.',
      );
    }
    if (this.field.length === 0 && this.row.length === 0) return [];
    if (this.field.endsWith('\r')) this.field = this.field.slice(0, -1);
    this.row.push(this.field);
    return [this.row.splice(0)];
  }
}

async function* decodedChunks(
  filePath: string,
  encoding: 'utf-8' | 'windows-1258',
) {
  const decoder = new TextDecoder(encoding);
  for await (const chunk of createReadStream(filePath)) {
    yield decoder.decode(chunk as Buffer, { stream: true });
  }
  const tail = decoder.decode();
  if (tail) yield tail;
}

function countOutsideQuotes(value: string, character: string) {
  let count = 0;
  let quoted = false;
  for (let index = 0; index < value.length; index += 1) {
    if (value[index] === '"') {
      if (quoted && value[index + 1] === '"') index += 1;
      else quoted = !quoted;
    } else if (!quoted && value[index] === character) count += 1;
  }
  return count;
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

function normalizeStoreCode(value: string) {
  return value.trim().toUpperCase().replace(/\s+/g, '').slice(0, 80);
}

function parseDateOnly(value: string) {
  const text = value.trim();
  const iso = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  const local = text.match(/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})/);
  const parts = iso
    ? { year: +iso[1], month: +iso[2], day: +iso[3] }
    : local
      ? { year: +local[3], month: +local[2], day: +local[1] }
      : null;
  if (!parts) return '';
  const days = new Date(Date.UTC(parts.year, parts.month, 0)).getUTCDate();
  if (
    parts.year < 2000 ||
    parts.year > 2100 ||
    parts.month < 1 ||
    parts.month > 12 ||
    parts.day < 1 ||
    parts.day > days
  )
    return '';
  return `${parts.year}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')}`;
}

function parseSignedInteger(value: string) {
  const text = value.trim();
  if (!text) return null;
  const parenthesized = text.match(/^\(([^()]+)\)$/);
  const body = parenthesized ? parenthesized[1] : text;
  if (parenthesized && /^[+-]/.test(body)) return null;
  const signed = body.match(/^([+-]?)(\d[\d.,]*)$/);
  if (!signed) return null;

  const sign = signed[1] === '-' || parenthesized ? -1 : 1;
  const numeric = signed[2];
  let integerDigits: string;
  let decimalDigits = '';
  if (/^\d+$/.test(numeric)) {
    integerDigits = numeric;
  } else {
    const vietnameseGrouped = numeric.match(
      /^(\d{1,3}(?:\.\d{3})+)(?:,(\d{1,2}))?$/,
    );
    const internationalGrouped = numeric.match(
      /^(\d{1,3}(?:,\d{3})+)(?:\.(\d{1,2}))?$/,
    );
    const ungroupedDecimal = numeric.match(/^(\d+)([.,])(\d{1,2})$/);
    if (vietnameseGrouped) {
      integerDigits = vietnameseGrouped[1].replace(/\./g, '');
      decimalDigits = vietnameseGrouped[2] ?? '';
    } else if (internationalGrouped) {
      integerDigits = internationalGrouped[1].replace(/,/g, '');
      decimalDigits = internationalGrouped[2] ?? '';
    } else if (ungroupedDecimal) {
      integerDigits = ungroupedDecimal[1];
      decimalDigits = ungroupedDecimal[3];
    } else {
      return null;
    }
  }
  if (decimalDigits && !/^0+$/.test(decimalDigits)) return null;
  const number = Number(integerDigits) * sign;
  if (!Number.isSafeInteger(number)) return null;
  return number;
}
