import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import * as XLSX from 'xlsx';
import { ManualInventoryItem } from './opshub-fifo-inventory.service';

type Row = Array<string | number | boolean | Date | null | undefined>;

type ParseResult = {
  items: ManualInventoryItem[];
  skippedRows: number;
  totalRows: number;
};

const REQUIRED_HEADERS = ['Mã sản phẩm', 'Số Serial', 'Mã chi nhánh'];

@Injectable()
export class ManualInventoryParserService {
  private readonly logger = new Logger(ManualInventoryParserService.name);

  parse(file: Express.Multer.File): ParseResult {
    if (!file?.buffer?.length) {
      throw new BadRequestException('Vui lòng chọn file tồn kho');
    }

    const workbook = XLSX.read(file.buffer, { cellDates: true });
    const sheetName = workbook.SheetNames[0];
    const sheet = sheetName ? workbook.Sheets[sheetName] : null;
    if (!sheet) {
      throw new BadRequestException('File tồn kho không có sheet dữ liệu');
    }

    const rows = XLSX.utils.sheet_to_json<Row>(sheet, {
      header: 1,
      defval: '',
      raw: false,
      blankrows: false,
    });
    const headerIndex = rows.findIndex((row) =>
      REQUIRED_HEADERS.every((header) => row.map(toText).includes(header)),
    );
    if (headerIndex < 0) {
      throw new BadRequestException(
        'File tồn kho không đúng mẫu: thiếu header Mã sản phẩm / Số Serial / Mã chi nhánh',
      );
    }

    const headerMap = this.buildHeaderMap(rows[headerIndex]);
    const byId = new Map<string, ManualInventoryItem>();
    let skippedRows = 0;

    for (let index = headerIndex + 1; index < rows.length; index += 1) {
      const item = this.parseRow(rows[index], headerMap, index + 1);
      if (!item) {
        skippedRows += 1;
        continue;
      }
      byId.set(item.id, item);
    }

    const items = Array.from(byId.values());
    if (items.length === 0) {
      throw new BadRequestException('File tồn kho không có dòng hợp lệ');
    }

    this.logger.log(
      `Parsed manual inventory file: rows=${rows.length - headerIndex - 1} valid=${items.length} skipped=${skippedRows}`,
    );
    return { items, skippedRows, totalRows: rows.length - headerIndex - 1 };
  }

  private buildHeaderMap(headerRow: Row) {
    return new Map(headerRow.map((value, index) => [toText(value), index]));
  }

  private parseRow(
    row: Row,
    headerMap: Map<string, number>,
    rowNumber: number,
  ): ManualInventoryItem | null {
    const sku = this.get(row, headerMap, 'Mã sản phẩm');
    const srCode = this.get(row, headerMap, 'Mã chi nhánh').toUpperCase();
    if (!sku || !srCode) return null;

    const serialNumber = this.get(row, headerMap, 'Số Serial') || null;
    const bin =
      this.get(row, headerMap, 'Mã Bin') ||
      this.get(row, headerMap, 'Tên Bin') ||
      null;
    const id = serialNumber
      ? `${srCode}:${serialNumber.toUpperCase()}`
      : `${srCode}:${sku}:${bin ?? 'NO_BIN'}:${rowNumber}`;

    return {
      id,
      srCode,
      srName: this.get(row, headerMap, 'Tên chi nhánh') || null,
      sku,
      skuName: this.get(row, headerMap, 'Tên sản phẩm'),
      serialNumber,
      serialType: this.get(row, headerMap, 'Loại Serial') || null,
      serialTypeChangedAt: this.parseImportDate(
        this.get(row, headerMap, 'Ngày đánh dấu chuyển loại Serial'),
      ),
      brand: this.get(row, headerMap, 'Thương hiệu') || null,
      categoryId: this.get(row, headerMap, 'Mã ngành hàng') || null,
      categoryName: this.get(row, headerMap, 'Tên ngành hàng') || null,
      subcategoryId: this.get(row, headerMap, 'Mã nhóm sản phẩm') || null,
      subcategoryName: this.get(row, headerMap, 'Tên nhóm sản phẩm') || null,
      partNumber: this.get(row, headerMap, 'Part number') || null,
      unit: this.get(row, headerMap, 'ĐVT') || null,
      bin,
      binName: this.get(row, headerMap, 'Tên Bin') || null,
      zone: this.get(row, headerMap, 'Zone') || null,
      binType: null,
      importDate: this.parseImportDate(
        this.get(row, headerMap, 'Ngày nhập kho'),
      ),
      count: this.parseCount(this.get(row, headerMap, 'Số lượng')),
      stockType: this.get(row, headerMap, 'Loại hàng') || null,
      purchaseStatus: null,
    };
  }

  private get(row: Row, headerMap: Map<string, number>, header: string) {
    const index = headerMap.get(header);
    return index === undefined ? '' : toText(row[index]);
  }

  private parseCount(value: string) {
    const count = Number(value.replace(',', '.'));
    return Number.isFinite(count) && count > 0 ? Math.round(count) : 1;
  }

  private parseImportDate(value: string) {
    if (!value) return null;
    const formulaNumber = /^=\s*([0-9]+(?:\.[0-9]+)?)/.exec(value);
    if (formulaNumber) {
      return excelSerialToDate(Number(formulaNumber[1]));
    }

    const numeric = Number(value);
    if (Number.isFinite(numeric) && numeric > 20_000 && numeric < 80_000) {
      return excelSerialToDate(numeric);
    }

    const ddmmyyyy = /^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/.exec(value);
    if (ddmmyyyy) {
      const day = Number(ddmmyyyy[1]);
      const month = Number(ddmmyyyy[2]) - 1;
      const year =
        ddmmyyyy[3].length === 2
          ? 2000 + Number(ddmmyyyy[3])
          : Number(ddmmyyyy[3]);
      return new Date(Date.UTC(year, month, day));
    }

    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
}

function toText(value: Row[number]) {
  if (value === null || value === undefined) return '';
  if (value instanceof Date) return value.toISOString();
  return String(value).trim();
}

function excelSerialToDate(serial: number) {
  const parsed = XLSX.SSF.parse_date_code(serial);
  if (!parsed) return null;
  return new Date(Date.UTC(parsed.y, parsed.m - 1, parsed.d));
}
