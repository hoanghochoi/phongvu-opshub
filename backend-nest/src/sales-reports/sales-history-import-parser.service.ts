import { BadRequestException, Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { TextDecoder } from 'node:util';
import {
  SalesReportCategoriesService,
  SalesReportExactCategoryTypeSnapshot,
} from './sales-report-categories.service';

export const SALES_HISTORY_IMPORT_MAX_ROWS = 1_000_000;
const PARSER_CHUNK_ROWS = 1_000;
const MAX_RECORD_CHARACTERS = 1_048_576;
const MAX_SAFE_SIGNIFICANT_DIGITS = 16;
const MAX_NUMERIC_TEXT_CHARACTERS = 64;
const POSTGRES_INTEGER_MIN = -2_147_483_648;
const POSTGRES_INTEGER_MAX = 2_147_483_647;

export type SalesHistoryMetricKey =
  | 'extendedInsuranceQuantity'
  | 'laptopQuantity'
  | 'pcQuantity'
  | 'assembledPcQuantity'
  | 'appleQuantity'
  | 'monitorQuantity'
  | 'printerQuantity'
  | 'accessoriesQuantity';

export type SalesHistoryComponentMetricKey =
  | 'cpuQuantity'
  | 'mainboardQuantity'
  | 'memoryQuantity'
  | 'storageQuantity'
  | 'caseQuantity'
  | 'psuQuantity';

export type SalesHistoryQuantityKey =
  | SalesHistoryMetricKey
  | SalesHistoryComponentMetricKey;

export type SalesHistoryParsedRow = {
  rowNumber: number;
  date: string;
  storeCode: string;
  orderCode: string;
  salespersonEmail: string;
  salespersonCode: string;
  signedRevenue: number | null;
  quantities: Record<SalesHistoryQuantityKey, number | null>;
  errorCodes: string[];
};

export type SalesHistoryParseMetadata = {
  sourceHash: string;
  encoding: 'utf-8' | 'windows-1258';
  delimiter: ',' | '\t';
  totalRows: number;
  sourceFormat: 'legacy-wide' | 'legacy-category' | 'historical-export';
  mappedCategoryRows: number;
  unmappedCategoryRows: number;
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
  metricRepresentation: 'wide' | 'category' | 'historical-export';
  categorySnapshot: SalesReportExactCategoryTypeSnapshot | null;
};

type HistoricalExportColumnKey =
  | 'skuName'
  | 'subcat2Id'
  | 'subcatLowestLevelId';

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

const COMPONENT_METRIC_KEYS: SalesHistoryComponentMetricKey[] = [
  'cpuQuantity',
  'mainboardQuantity',
  'memoryQuantity',
  'storageQuantity',
  'caseQuantity',
  'psuQuantity',
];

const HISTORICAL_EXPORT_HEADERS = [
  'Report date',
  'Channel',
  'Store',
  'Branch code',
  'Customer full name',
  'Order code',
  'Export return branch ID',
  'Order type',
  'Email',
  'HRM ID',
  'Salesman',
  'Customer ID',
  'SKU',
  'Doc ID',
  'Sale point per item',
  'SKU name',
  'Dealer type',
  'Brand name',
  'Billing tax code',
  'Cat group ID',
  'Cat group name',
  'Subcat 2 ID',
  'Subcat 2 name',
  'Subcat ID lowest level',
  'Subcat name lowest level',
  'Is delivery',
  'Order note',
  'Terminal code',
  'Terminal name',
  'Platform',
  'Sale point',
  'Quantity',
  'Revenue',
  'Revenue with VAT',
] as const;

const HISTORICAL_EXPORT_COLUMNS: Record<
  ColumnKey | HistoricalExportColumnKey,
  number
> = {
  date: 0,
  storeCode: 3,
  orderCode: 5,
  email: 8,
  personnelCode: 9,
  salesman: 10,
  revenue: 33,
  category: 23,
  quantity: 31,
  extendedInsuranceQuantity: -1,
  laptopQuantity: -1,
  pcQuantity: -1,
  assembledPcQuantity: -1,
  appleQuantity: -1,
  monitorQuantity: -1,
  printerQuantity: -1,
  accessoriesQuantity: -1,
  skuName: 15,
  subcat2Id: 21,
  subcatLowestLevelId: 23,
};

const EXPORT_TYPE_METRICS: Record<string, SalesHistoryQuantityKey> = {
  extendedInsurance: 'extendedInsuranceQuantity',
  extendedinsurance: 'extendedInsuranceQuantity',
  laptop: 'laptopQuantity',
  pc: 'pcQuantity',
  apple: 'appleQuantity',
  monitor: 'monitorQuantity',
  printer: 'printerQuantity',
  accessories: 'accessoriesQuantity',
  cpu: 'cpuQuantity',
  mainboard: 'mainboardQuantity',
  memory: 'memoryQuantity',
  storage: 'storageQuantity',
  case: 'caseQuantity',
  psu: 'psuQuantity',
};

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
  constructor(private readonly categories: SalesReportCategoriesService) {}

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
    let mappedCategoryRows = 0;
    let unmappedCategoryRows = 0;
    let pending: SalesHistoryParsedRow[] = [];

    const consume = async (record: string[]) => {
      rowNumber += 1;
      if (record.every((value) => value.trim() === '')) return;
      if (!columns) {
        columns = await this.resolveColumns(record);
        return;
      }
      totalRows += 1;
      if (totalRows > SALES_HISTORY_IMPORT_MAX_ROWS) {
        throw new BadRequestException(
          'Mỗi lần chỉ nhập tối đa 1.000.000 dòng dữ liệu.',
        );
      }
      const parsed = this.parseRow(record, rowNumber, columns);
      if (columns.metricRepresentation === 'historical-export') {
        if (parsed.errorCodes.includes('INVALID_CATEGORY')) {
          unmappedCategoryRows += 1;
        } else {
          mappedCategoryRows += 1;
        }
      }
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
    const finalColumns = columns as ResolvedColumns | null;
    if (!finalColumns)
      throw new BadRequestException('Tệp CSV/TSV chưa có header.');
    if (pending.length > 0) {
      if (await isCancelled()) throw new ImportCancelledError();
      await onRows(pending);
    }
    if (totalRows === 0) {
      throw new BadRequestException('Tệp CSV/TSV chưa có dòng dữ liệu.');
    }
    return {
      ...detected,
      totalRows,
      sourceFormat:
        finalColumns.metricRepresentation === 'historical-export'
          ? 'historical-export'
          : finalColumns.metricRepresentation === 'wide'
            ? 'legacy-wide'
            : 'legacy-category',
      mappedCategoryRows,
      unmappedCategoryRows,
    };
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

  private async resolveColumns(header: string[]): Promise<ResolvedColumns> {
    if (this.isHistoricalExportHeader(header)) {
      const columns = new Map<ColumnKey, number>();
      for (const [key, index] of Object.entries(HISTORICAL_EXPORT_COLUMNS)) {
        if (index >= 0) columns.set(key as ColumnKey, index);
      }
      return {
        columns,
        metricRepresentation: 'historical-export',
        categorySnapshot: await this.categories.exactCategoryTypeSnapshot(),
      };
    }
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
      categorySnapshot: null,
    };
  }

  private isHistoricalExportHeader(header: string[]) {
    return (
      header.length === HISTORICAL_EXPORT_HEADERS.length &&
      HISTORICAL_EXPORT_HEADERS.every(
        (expected, index) => header[index]?.trim() === expected,
      )
    );
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
    const rawOrderCode = value('orderCode').replace(/\s+/g, '').slice(0, 120);
    const orderCode =
      metricRepresentation === 'historical-export'
        ? (value('orderCode').match(/^(\d{14})/)?.[1] ?? '')
        : rawOrderCode;
    const salespersonEmail = value('email').toLowerCase().slice(0, 200);
    const salespersonCode = value('personnelCode').toUpperCase().slice(0, 80);
    const signedRevenue = parseSignedInteger(
      value('revenue'),
      metricRepresentation === 'historical-export',
    );
    const quantities = Object.fromEntries([
      ...METRIC_KEYS.map((key) => [
        key,
        metricRepresentation === 'wide' ? parseStageQuantity(value(key)) : 0,
      ]),
      ...COMPONENT_METRIC_KEYS.map((key) => [key, 0]),
    ]) as Record<SalesHistoryQuantityKey, number | null>;
    const errorCodes: string[] = [];
    if (metricRepresentation === 'category') {
      const category = CATEGORY_METRICS[normalizeKey(value('category'))];
      const quantity = parseStageQuantity(value('quantity'));
      if (!category) errorCodes.push('INVALID_CATEGORY');
      if (quantity === null) errorCodes.push('INVALID_QUANTITY');
      if (category) quantities[category] = quantity;
    }
    if (metricRepresentation === 'historical-export') {
      const exportValue = (key: HistoricalExportColumnKey) =>
        String(record[HISTORICAL_EXPORT_COLUMNS[key]] ?? '').trim();
      const categoryType = resolved.categorySnapshot?.lookup(
        exportValue('subcatLowestLevelId'),
        exportValue('subcat2Id'),
      );
      const quantity = parseStageQuantity(value('quantity'), true);
      if (!categoryType) errorCodes.push('INVALID_CATEGORY');
      if (quantity === null) errorCodes.push('INVALID_QUANTITY');
      const metric = categoryType ? EXPORT_TYPE_METRICS[categoryType] : null;
      if (
        metric &&
        (metric !== 'appleQuantity' ||
          this.isTargetAppleSku(exportValue('skuName')))
      ) {
        quantities[metric] = quantity;
      }
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

  private isTargetAppleSku(value: string) {
    const skuName = normalizeKey(value);
    return ['iphone', 'macbook', 'ipad'].some((target) =>
      skuName.includes(target),
    );
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

function parseSignedInteger(value: string, allowScientific = false) {
  const text = value.trim();
  if (!text || text.length > MAX_NUMERIC_TEXT_CHARACTERS) return null;
  const parenthesized = text.match(/^\(([^()]+)\)$/);
  const body = parenthesized ? parenthesized[1] : text;
  if (parenthesized && /^[+-]/.test(body)) return null;
  if (allowScientific) {
    const scientific = body.match(/^([+-]?)(\d+(?:[.,]\d+)?)[eE]([+-]?\d+)$/);
    if (scientific) {
      const sign = scientific[1] === '-' || parenthesized ? -1 : 1;
      const coefficient = scientific[2].replace(',', '.');
      const decimalIndex = coefficient.indexOf('.');
      const decimalPlaces =
        decimalIndex === -1 ? 0 : coefficient.length - decimalIndex - 1;
      const digits = coefficient.replace('.', '');
      const exponent = Number(scientific[3]);
      if (!Number.isSafeInteger(exponent) || Math.abs(exponent) > 100) {
        return null;
      }
      const scale = exponent - decimalPlaces;
      const significantLength = digits.replace(/^0+/, '').length;
      if (significantLength === 0) return 0;
      if (
        significantLength > MAX_SAFE_SIGNIFICANT_DIGITS ||
        (scale >= 0 && significantLength + scale > MAX_SAFE_SIGNIFICANT_DIGITS)
      ) {
        return null;
      }
      let integer = BigInt(digits);
      if (scale >= 0) {
        integer *= 10n ** BigInt(scale);
      } else {
        const divisor = 10n ** BigInt(-scale);
        if (integer % divisor !== 0n) return null;
        integer /= divisor;
      }
      if (sign < 0) integer = -integer;
      if (
        integer > BigInt(Number.MAX_SAFE_INTEGER) ||
        integer < BigInt(Number.MIN_SAFE_INTEGER)
      ) {
        return null;
      }
      return Number(integer);
    }
  }
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

function parseStageQuantity(value: string, allowScientific = false) {
  const quantity = parseSignedInteger(value, allowScientific);
  if (
    quantity === null ||
    quantity < POSTGRES_INTEGER_MIN ||
    quantity > POSTGRES_INTEGER_MAX
  ) {
    return null;
  }
  return quantity;
}
