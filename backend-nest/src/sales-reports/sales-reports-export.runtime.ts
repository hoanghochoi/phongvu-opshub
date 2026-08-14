import * as XLSX from 'xlsx';

import {
  ExportSalesReportsDto,
  SALES_REPORT_EXPORT_TYPES,
} from './sales-reports.dto';
import {
  buildCanonicalRevenueLookup,
  canonicalRevenueForOrder,
  CanonicalRevenueLookup,
  normalizeRevenueOrderCode,
} from './sales-report-revenue';
import { SalesReportsRevenueAggregationSummary } from './sales-reports-revenue-aggregation.runtime';

export type SalesReportsExportType = (typeof SALES_REPORT_EXPORT_TYPES)[number];

export type SalesReportsExportRuntimeDependencies = {
  normalizeExportType: (value: unknown) => SalesReportsExportType;
  loadRows: (
    user: any,
    query: ExportSalesReportsDto,
    exportType: SalesReportsExportType,
  ) => Promise<any[]>;
  loadCanonicalRevenue: (
    orderCodes: string[],
  ) => Promise<CanonicalRevenueLookup>;
  summarizeSalesRevenueRows: (
    rows: any[],
    canonicalRevenue: CanonicalRevenueLookup,
  ) => SalesReportsRevenueAggregationSummary;
  safeUserLabel: (user: any) => string;
  safeLogError: (error: unknown) => string;
  csvText: (value: unknown) => string;
  cleanCustomerContactChannelCodes: (value: unknown) => string[];
  cleanInstallmentPartnerCodes: (value: unknown) => string[];
  customerContactChannelLabel: (code: string) => string;
  answerLabel: (code: string) => string;
  reportTypeLabel: (code: string) => string;
  notPurchasedLabel: (code: string) => string;
  installmentApprovedCsvLabel: (value: unknown) => string;
  finalPaymentMethodLabel: (row: any) => string;
  installmentNoInstallmentReasonLabel: (code: string) => string;
  log: (message: string) => void;
  warn: (message: string) => void;
  error: (message: string) => void;
};

/**
 * Owns admin Sales Reports export orchestration and XLSX rendering while the
 * service facade retains query/scope, persistence and public API ownership.
 */
export class SalesReportsExportRuntime {
  constructor(private readonly deps: SalesReportsExportRuntimeDependencies) {}

  async exportWorkbook(user: any, query: ExportSalesReportsDto) {
    const startedAt = Date.now();
    const exportType = this.deps.normalizeExportType(query.exportType);
    this.deps.log(
      `Sales reports export started: user=${this.deps.safeUserLabel(user)} type=${exportType}`,
    );
    try {
      const rows = await this.deps.loadRows(user, query, exportType);
      const canonicalRevenue =
        exportType === 'REVENUE' || exportType === 'INSTALLMENT'
          ? await this.deps.loadCanonicalRevenue(
              this.uniqueRevenueOrderCodes(rows),
            )
          : buildCanonicalRevenueLookup([]);
      if (exportType === 'REVENUE' || exportType === 'INSTALLMENT') {
        const requestedCodes = this.uniqueRevenueOrderCodes(rows);
        const missingCount = requestedCodes.filter(
          (code) => !canonicalRevenue.presentCodes.has(code),
        ).length;
        const invalidCount = requestedCodes.filter((code) =>
          canonicalRevenue.invalidCodes.has(code),
        ).length;
        if (missingCount > 0 || invalidCount > 0) {
          this.deps.warn(
            `Sales revenue quality warning: source=export type=${exportType} reports=${rows.length} requestedOrders=${requestedCodes.length} validOrders=${canonicalRevenue.values.size} missingOrders=${missingCount} invalidOrders=${invalidCount}`,
          );
        }
      }

      const workbook =
        exportType === 'REVENUE'
          ? this.buildRevenueWorkbook(rows, canonicalRevenue)
          : exportType === 'INSTALLMENT'
            ? this.buildInstallmentWorkbook(rows, canonicalRevenue)
            : this.buildHvtcWorkbook(rows);
      this.deps.log(
        `Sales reports export completed: user=${this.deps.safeUserLabel(user)} type=${exportType} count=${rows.length} durationMs=${Date.now() - startedAt}`,
      );
      return workbook;
    } catch (error) {
      this.deps.error(
        `Sales reports export failed: user=${this.deps.safeUserLabel(user)} type=${exportType} durationMs=${Date.now() - startedAt} error=${this.deps.safeLogError(error)}`,
      );
      throw error;
    }
  }

  private uniqueRevenueOrderCodes(rows: any[]) {
    return Array.from(
      new Set(
        rows
          .map((row) => normalizeRevenueOrderCode(row?.orderCode))
          .filter((code): code is string => Boolean(code)),
      ),
    );
  }

  private buildHvtcWorkbook(rows: any[]) {
    const headers = [
      'Ngày báo cáo',
      'Email người báo cáo',
      'Mã nhân viên tư vấn ERP',
      'Tên khách hàng',
      'Số điện thoại khách hàng',
      'Kênh liên hệ khách hàng',
      'Nhu cầu khách hàng',
      'Kết quả tư vấn giải pháp',
      'Lý do khác khi không tư vấn',
      'Kết quả trải nghiệm sản phẩm',
      'Lý do khác khi không trải nghiệm',
      'Kết quả quét Zalo',
      'Lý do khác khi không quét Zalo',
      'Kết quả tải App PV',
      'Lý do khác khi không tải App PV',
      'Loại báo cáo',
      'Lý do khách chưa mua',
      'Lý do khác khi khách chưa mua',
      'Mã showroom',
    ];
    const data: Array<Array<string | number>> = [headers];
    for (const row of rows) {
      data.push([
        this.workbookText(this.csvVietnamDateTime(row.submittedAt)),
        this.workbookText(row.createdByEmail),
        this.workbookText(
          row.erpConsultantCustomId ?? row.createdByPersonnelCode,
        ),
        this.workbookText(row.customerName),
        this.workbookText(row.customerPhone),
        this.workbookText(
          this.deps
            .cleanCustomerContactChannelCodes(row.customerContactChannels)
            .map((code) => this.deps.customerContactChannelLabel(code))
            .join('; '),
        ),
        this.workbookText(row.customerNeed),
        this.workbookText(this.deps.answerLabel(row.consultedSolutionAnswer)),
        this.workbookText(row.consultedSolutionOtherReason),
        this.workbookText(this.deps.answerLabel(row.experiencedAnswer)),
        this.workbookText(row.experiencedOtherReason),
        this.workbookText(this.deps.answerLabel(row.zaloAnswer)),
        this.workbookText(row.zaloOtherReason),
        this.workbookText(this.deps.answerLabel(row.appDownloadAnswer)),
        this.workbookText(row.appDownloadOtherReason),
        this.workbookText(this.deps.reportTypeLabel(row.reportType)),
        this.workbookText(
          row.notPurchasedReason
            ? this.deps.notPurchasedLabel(row.notPurchasedReason)
            : '',
        ),
        this.workbookText(row.notPurchasedOtherReason),
        this.workbookText(row.storeCode),
      ]);
    }
    return this.workbookBuffer('HVTC', data);
  }

  private buildRevenueWorkbook(
    rows: any[],
    canonicalRevenue: CanonicalRevenueLookup,
  ) {
    const summary = this.deps.summarizeSalesRevenueRows(rows, canonicalRevenue);
    const headers = [
      'Số đơn hàng duy nhất',
      'Tổng doanh thu khách hàng doanh nghiệp (đã bao gồm VAT)',
      'Tổng doanh thu khách hàng cá nhân (đã bao gồm VAT)',
      'Báo cáo có nhu cầu trả góp',
      'Trả góp thành công (theo báo cáo bán hàng)',
      'Số lượng laptop',
      'Số lượng PC',
      'Số lượng PC ráp',
      'Số lượng Apple',
      'Số lượng màn hình',
      'Số lượng máy in',
      'Số lượng phụ kiện',
      'Số lượng dịch vụ bảo hiểm',
      'Các lý do khách không trả góp',
    ];
    const values: Array<string | number> = [
      summary.orderCountUnique,
      summary.businessRevenue,
      summary.personalRevenue,
      summary.installmentNeedTotalCount,
      summary.successfulInstallmentOrderCount,
      summary.laptopQuantity,
      summary.pcQuantity,
      summary.assembledPcQuantity,
      summary.appleQuantity,
      summary.monitorQuantity,
      summary.printerQuantity,
      summary.accessoriesQuantity,
      summary.extendedInsuranceQuantity,
      this.workbookText(
        this.csvCompactList(
          Array.from(summary.noInstallmentReasons.entries()).map(
            ([reason, count]) => `${reason}: ${count}`,
          ),
        ),
      ),
    ];
    return this.workbookBuffer('Doanh so', [headers, values]);
  }

  private buildInstallmentWorkbook(
    rows: any[],
    canonicalRevenue: CanonicalRevenueLookup,
  ) {
    const headers = [
      'Ngày báo cáo',
      'Email người báo cáo',
      'Đơn hàng',
      'Giá trị đơn hàng (đã bao gồm VAT)',
      'Số tiền vay trả góp',
      'Đối tác trả góp',
      'Kết quả duyệt hồ sơ',
      'Loại báo cáo',
      'Phương thức thanh toán cuối cùng',
      'Lý do không trả góp',
    ];
    const data: Array<Array<string | number>> = [headers];
    for (const row of rows.filter((item) => item.installmentNeed === true)) {
      const partnerCodes = this.deps.cleanInstallmentPartnerCodes(
        row.installmentPartnerCodes,
      );
      data.push([
        this.workbookText(this.csvVietnamDateTime(row.submittedAt)),
        this.workbookText(row.createdByEmail),
        this.workbookText(row.orderCode),
        this.workbookNumber(
          canonicalRevenueForOrder(canonicalRevenue, row.orderCode),
        ),
        this.workbookNumber(row.installmentLoanAmount),
        this.workbookText(partnerCodes.join('; ')),
        this.workbookText(
          this.deps.installmentApprovedCsvLabel(row.installmentApproved),
        ),
        this.workbookText(this.deps.reportTypeLabel(row.reportType)),
        this.workbookText(this.deps.finalPaymentMethodLabel(row)),
        this.workbookText(
          row.installmentNoInstallmentReason
            ? this.deps.installmentNoInstallmentReasonLabel(
                row.installmentNoInstallmentReason,
              )
            : '',
        ),
      ]);
    }
    return this.workbookBuffer('Tra gop', data);
  }

  private workbookBuffer(
    sheetName: string,
    data: Array<Array<string | number>>,
  ) {
    const sheet = XLSX.utils.aoa_to_sheet(data);
    sheet['!cols'] = this.workbookColumns(data);
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, sheet, sheetName);
    return XLSX.write(workbook, { bookType: 'xlsx', type: 'buffer' }) as Buffer;
  }

  private workbookColumns(data: Array<Array<string | number>>) {
    const columnCount = Math.max(...data.map((row) => row.length), 0);
    return Array.from({ length: columnCount }, (_, index) => {
      const maxLength = Math.max(
        ...data.map((row) => String(row[index] ?? '').length),
        8,
      );
      return { wch: Math.min(Math.max(maxLength + 2, 10), 42) };
    });
  }

  private workbookText(value: unknown) {
    return this.deps
      .csvText(value)
      .replace(/[\r\n]+/g, ' ')
      .trim();
  }

  private workbookNumber(value: unknown): string | number {
    if (value === undefined || value === null || value === '') return '';
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : this.workbookText(value);
  }

  private csvVietnamDateTime(value: unknown) {
    const date = value instanceof Date ? value : new Date(String(value || ''));
    if (Number.isNaN(date.getTime())) return '';
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Ho_Chi_Minh',
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    })
      .formatToParts(date)
      .reduce<Record<string, string>>((acc, part) => {
        if (part.type !== 'literal') acc[part.type] = part.value;
        return acc;
      }, {});
    return `${parts.day}/${parts.month}/${parts.year} ${parts.hour}:${parts.minute}:${parts.second}`;
  }

  private csvCompactList(values: unknown[]) {
    return Array.from(
      new Set(
        values.map((value) => this.deps.csvText(value).trim()).filter(Boolean),
      ),
    ).join('; ');
  }
}
