import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import * as XLSX from 'xlsx';
import {
  ManualInventoryItem,
  rowToCanonicalItem,
} from './opshub-fifo-inventory.service';

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
      byId.set(item.itemKey, item);
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
    const canonicalRow = {
      SKU: this.get(row, headerMap, 'Mã sản phẩm'),
      SKU_name: this.get(row, headerMap, 'Tên sản phẩm'),
      Serial: this.get(row, headerMap, 'Số Serial'),
      Branch_ID: this.get(row, headerMap, 'Mã chi nhánh'),
      Branch_name: this.get(row, headerMap, 'Tên chi nhánh'),
      Brand: this.get(row, headerMap, 'Thương hiệu'),
      Category_ID: this.get(row, headerMap, 'Mã ngành hàng'),
      Category_name: this.get(row, headerMap, 'Tên ngành hàng'),
      SubCategory_ID: this.get(row, headerMap, 'Mã nhóm sản phẩm'),
      SubCategory_name: this.get(row, headerMap, 'Tên nhóm sản phẩm'),
      Location: this.get(row, headerMap, 'Mã Bin'),
      BIN_type: this.get(row, headerMap, 'Loại hàng'),
      BIN_zone: this.get(row, headerMap, 'Zone'),
      Date_import_site: this.get(row, headerMap, 'Ngày nhập kho'),
      Inventory: this.get(row, headerMap, 'Số lượng'),
      'Part number': this.get(row, headerMap, 'Part number'),
      'ĐVT': this.get(row, headerMap, 'ĐVT'),
      'Loại Serial': this.get(row, headerMap, 'Loại Serial'),
      'Ngày đánh dấu chuyển loại Serial': this.get(
        row,
        headerMap,
        'Ngày đánh dấu chuyển loại Serial',
      ),
      'Tên Bin': this.get(row, headerMap, 'Tên Bin'),
      'Tổng thể tích sản phẩm': this.get(
        row,
        headerMap,
        'Tổng thể tích sản phẩm',
      ),
      'Thể tích Bin': this.get(row, headerMap, 'Thể tích Bin'),
    };
    return rowToCanonicalItem(canonicalRow, rowNumber, 'manual');
  }

  private get(row: Row, headerMap: Map<string, number>, header: string) {
    const index = headerMap.get(header);
    return index === undefined ? '' : toText(row[index]);
  }
}

function toText(value: Row[number]) {
  if (value === null || value === undefined) return '';
  if (value instanceof Date) return value.toISOString();
  return String(value).trim();
}
