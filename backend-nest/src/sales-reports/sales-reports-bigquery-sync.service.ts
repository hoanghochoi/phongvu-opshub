import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { BigQuery } from '@google-cloud/bigquery';
import { Cron } from '@nestjs/schedule';
import { promises as fs } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PrismaService } from '../prisma/prisma.service';

const DEFAULT_TABLE_PREFIX = 'opshub_sales_report';
const DEFAULT_MAX_ROWS = 100_000;

const ANSWER_LABELS: Record<string, string> = {
  YES: 'Có',
  CUSTOMER_BUSY_OR_NO_NEED:
    'Không - KH vội/không có nhu cầu/không muốn tư vấn/chỉ tham quan',
  OUT_OF_STOCK_OR_NO_EQUIVALENT: 'Không - Hết hàng/không có SP tương đương',
  PRODUCT_NOT_SOLD_OR_NOT_IN_STORE:
    'Không - SP KH cần không kinh doanh/không có tại CH',
  PRICE_HIGH: 'Không - SP giá cao',
  SALES_FORGOT: 'Không - Nhân viên bán hàng quên tư vấn',
  OTHER: 'Không - Lý do khác',
  ALREADY_FOLLOWED_ZALO: 'Không - KH đã quét Zalo OA rồi',
  NO_SMARTPHONE_OR_NO_ZALO:
    'Không - KH không dùng smartphone/không mang điện thoại/không dùng Zalo',
  ALREADY_INSTALLED_APP: 'Không - KH đã tải App rồi',
  NO_SMARTPHONE_OR_NO_APP:
    'Không - KH không dùng smartphone/không mang điện thoại/không dùng App',
};

const NOT_PURCHASED_LABELS: Record<string, string> = {
  NOT_SOLD: 'Chưa kinh doanh',
  SERVICE: 'Dịch vụ',
  CUSTOMER_BROWSING: 'KH tham khảo',
  NO_DEMO_STOCK: 'Không có hàng trải nghiệm',
  NO_AVAILABLE_STOCK: 'Không có sẵn hàng',
  PRICE_HESITATION: 'Phân vân giá',
  COMPARE_COMPETITOR: 'So sánh đối thủ',
  SPEC_NOT_COMPATIBLE: 'Thông số kỹ thuật chưa tương thích',
  OTHER: 'Khác',
};

const CUSTOMER_TYPE_LABELS: Record<string, string> = {
  BUSINESS: 'Doanh nghiệp',
  PERSONAL: 'Cá nhân',
};

const PROMOTION_LABELS: Record<string, string> = {
  EXAM_SCORE_EXCHANGE: 'Đổi điểm thi',
  STUDENT: 'Học sinh - Sinh viên',
  OTHER: 'CTKM khác',
};

const INSTALLMENT_NO_INSTALLMENT_REASON_LABELS: Record<string, string> = {
  NORMAL_INSTALLMENT: 'Khách chốt trả góp bình thường (Không có lý do)',
  BAD_CREDIT_HISTORY: 'Rớt hồ sơ: Tín dụng xấu (Nợ cũ, CIC...)',
  APPRAISAL_OR_INFO_ERROR: 'Rớt hồ sơ: Lỗi thẩm định/Thông tin',
  HIGH_INTEREST_OR_FEE: 'Khách từ chối: Lãi suất/Phí trả góp cao',
  MISSING_DOCUMENT_OR_CARD: 'Khách từ chối: Không đủ điều kiện giấy tờ/thẻ',
  PRICE_COMPETITOR_COMPARISON:
    'Khách từ chối: Giá cao/So sánh đối thủ (TGDĐ, FPT, CPS...)',
  BROWSING_OR_COME_BACK_LATER: 'Khách từ chối: Chỉ tham khảo/Hẹn quay lại',
};

type BigQueryField = {
  name: string;
  type: string;
  mode?: string;
};

type SalesReportBigQueryConfig = {
  projectId: string;
  datasetId: string;
  keyFilename?: string;
  reportTableId: string;
  itemTableId: string;
  paymentTableId: string;
  maxRows: number;
};

export type SalesReportBigQuerySyncResult = {
  skipped: boolean;
  reason?: string;
  reportRows: number;
  itemRows: number;
  paymentRows: number;
  tables: {
    reports: string;
    items: string;
    payments: string;
  } | null;
  durationMs: number;
};

@Injectable()
export class SalesReportsBigQuerySyncService implements OnApplicationBootstrap {
  private readonly logger = new Logger(SalesReportsBigQuerySyncService.name);
  private syncRunning = false;

  constructor(private readonly prisma: PrismaService) {}

  onApplicationBootstrap() {
    if (!this.syncOnStartup()) return;
    void this.syncAll('startup').catch((error) => {
      this.logger.error(
        `Sales report BigQuery startup sync failed: error=${this.safeError(error)}`,
      );
    });
  }

  @Cron('0 7 * * *', { timeZone: 'Asia/Ho_Chi_Minh' })
  async scheduledSync() {
    if (!this.syncEnabled()) return;
    await this.syncAll('daily_07_vietnam');
  }

  async syncAll(
    source = 'manual',
    options: { force?: boolean } = {},
  ): Promise<SalesReportBigQuerySyncResult> {
    const startedAt = Date.now();
    if (!options.force && !this.syncEnabled()) {
      return this.skipped('disabled', startedAt);
    }
    const config = this.resolveConfig();
    if (!config) return this.skipped('missing_config', startedAt);
    if (this.syncRunning) return this.skipped('already_running', startedAt);

    this.syncRunning = true;
    this.logger.log(
      `Sales report BigQuery sync started: source=${source} dataset=${config.projectId}.${config.datasetId} reportTable=${config.reportTableId} itemTable=${config.itemTableId} paymentTable=${config.paymentTableId}`,
    );

    try {
      const client = this.createBigQueryClient(config);
      const reports = await this.prisma.salesReport.findMany({
        where: { erpExcludedAt: null },
        orderBy: [{ submittedAt: 'asc' }, { id: 'asc' }],
        take: config.maxRows,
        include: {
          categorySelections: { orderBy: { sortOrder: 'asc' } },
          items: { orderBy: { createdAt: 'asc' } },
          payments: { orderBy: { createdAt: 'asc' } },
        },
      });
      if (reports.length >= config.maxRows) {
        this.logger.warn(
          `Sales report BigQuery sync reached maxRows=${config.maxRows}; increase SALES_REPORT_BIGQUERY_MAX_ROWS if older rows are missing`,
        );
      }

      const syncedAt = new Date();
      const reportRows = reports.map((row) => this.toReportRow(row, syncedAt));
      const itemRows = reports.flatMap((row) =>
        (row.items ?? []).map((item: any) =>
          this.toItemRow(row, item, syncedAt),
        ),
      );
      const paymentRows = reports.flatMap((row) =>
        (row.payments ?? []).map((payment: any) =>
          this.toPaymentRow(row, payment, syncedAt),
        ),
      );

      await this.replaceTableRows(
        client,
        config,
        config.reportTableId,
        REPORT_SCHEMA,
        reportRows,
      );
      await this.replaceTableRows(
        client,
        config,
        config.itemTableId,
        ITEM_SCHEMA,
        itemRows,
      );
      await this.replaceTableRows(
        client,
        config,
        config.paymentTableId,
        PAYMENT_SCHEMA,
        paymentRows,
      );

      const result: SalesReportBigQuerySyncResult = {
        skipped: false,
        reportRows: reportRows.length,
        itemRows: itemRows.length,
        paymentRows: paymentRows.length,
        tables: {
          reports: this.tablePath(config, config.reportTableId),
          items: this.tablePath(config, config.itemTableId),
          payments: this.tablePath(config, config.paymentTableId),
        },
        durationMs: Date.now() - startedAt,
      };
      this.logger.log(
        `Sales report BigQuery sync succeeded: source=${source} reports=${result.reportRows} items=${result.itemRows} payments=${result.paymentRows} durationMs=${result.durationMs}`,
      );
      return result;
    } catch (error) {
      this.logger.error(
        `Sales report BigQuery sync failed: source=${source} durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      throw error;
    } finally {
      this.syncRunning = false;
    }
  }

  private async replaceTableRows(
    client: BigQuery,
    config: SalesReportBigQueryConfig,
    tableId: string,
    schema: BigQueryField[],
    rows: Array<Record<string, unknown>>,
  ) {
    const table = client.dataset(config.datasetId).table(tableId);
    if (rows.length === 0) {
      await this.ensureTable(table, schema);
      await client.query({
        query: `DELETE FROM \`${this.tablePath(config, tableId)}\` WHERE TRUE`,
      });
      return;
    }

    const tempDir = await fs.mkdtemp(
      join(tmpdir(), 'opshub-sales-report-bigquery-'),
    );
    const filePath = join(tempDir, `${tableId}.json`);
    try {
      await fs.writeFile(
        filePath,
        `${rows.map((row) => JSON.stringify(row)).join('\n')}\n`,
        'utf8',
      );
      const [job] = await table.load(filePath, {
        sourceFormat: 'NEWLINE_DELIMITED_JSON',
        writeDisposition: 'WRITE_TRUNCATE',
        schema: { fields: schema },
      } as any);
      await (job as any).promise();
    } finally {
      await fs.rm(tempDir, { recursive: true, force: true });
    }
  }

  private async ensureTable(table: any, schema: BigQueryField[]) {
    const [exists] = await table.exists();
    if (exists) return;
    await table.create({ schema: { fields: schema } });
  }

  private toReportRow(row: any, syncedAt: Date) {
    const submittedAt = this.dateValue(row.submittedAt);
    const categoryGroups = this.categoryGroups(row);
    const promotionCodes = this.arrayText(row.promotionCodes);
    const partnerCodes = this.arrayText(row.installmentPartnerCodes);
    return {
      sales_report_id: this.text(row.id),
      report_type: this.text(row.reportType),
      report_type_label: this.reportTypeLabel(row.reportType),
      submitted_at: this.timestamp(submittedAt),
      submitted_date: this.vietnamDate(submittedAt),
      order_code: this.text(row.orderCode),
      customer_name: this.text(row.customerName),
      customer_phone: this.text(row.customerPhone),
      customer_need: this.text(row.customerNeed),
      category_group_id: this.text(row.categoryGroupId),
      category_group_name: this.text(row.categoryGroupName),
      category_group_name_vi: this.text(row.categoryGroupNameVi),
      category_groups_vi: categoryGroups
        .map((category: any) => category.categoryGroupNameVi)
        .filter(Boolean)
        .join('; '),
      consulted_solution_answer: this.text(row.consultedSolutionAnswer),
      consulted_solution_label: this.answerLabel(row.consultedSolutionAnswer),
      consulted_solution_other_reason: this.text(
        row.consultedSolutionOtherReason,
      ),
      experienced_answer: this.text(row.experiencedAnswer),
      experienced_label: this.answerLabel(row.experiencedAnswer),
      experienced_other_reason: this.text(row.experiencedOtherReason),
      zalo_answer: this.text(row.zaloAnswer),
      zalo_label: this.answerLabel(row.zaloAnswer),
      zalo_other_reason: this.text(row.zaloOtherReason),
      app_download_answer: this.text(row.appDownloadAnswer),
      app_download_label: this.answerLabel(row.appDownloadAnswer),
      app_download_other_reason: this.text(row.appDownloadOtherReason),
      not_purchased_reason: this.text(row.notPurchasedReason),
      not_purchased_reason_label: row.notPurchasedReason
        ? this.notPurchasedLabel(row.notPurchasedReason)
        : '',
      not_purchased_other_reason: this.text(row.notPurchasedOtherReason),
      customer_type: this.text(row.customerType),
      customer_type_label: row.customerType
        ? this.customerTypeLabel(row.customerType)
        : '',
      customer_is_student: row.customerIsStudent === true,
      promotion_codes: promotionCodes.join('; '),
      promotion_labels: promotionCodes
        .map((code) => this.promotionLabel(code))
        .join('; '),
      installment_need: row.installmentNeed === true,
      installment_approved: this.booleanOrNull(row.installmentApproved),
      installment_approved_label: this.installmentApprovedLabel(
        row.installmentApproved,
      ),
      installment_loan_amount: this.integer(row.installmentLoanAmount),
      installment_status: this.text(row.installmentStatus),
      installment_failure_reason: this.text(row.installmentFailureReason),
      installment_partner_codes: partnerCodes.join('; '),
      installment_no_installment_reason: this.text(
        row.installmentNoInstallmentReason,
      ),
      installment_no_installment_reason_label:
        row.installmentNoInstallmentReason
          ? this.installmentNoInstallmentReasonLabel(
              row.installmentNoInstallmentReason,
            )
          : '',
      final_payment_method_label: this.finalPaymentMethodLabel(row),
      created_by_user_id: this.text(row.createdByUserId),
      created_by_email: this.text(row.createdByEmail),
      created_by_name: this.text(row.createdByName),
      created_by_personnel_code: this.text(row.createdByPersonnelCode),
      store_code: this.text(row.storeCode),
      store_name: this.text(row.storeName),
      organization_node_id: this.text(row.organizationNodeId),
      organization_node_name: this.text(row.organizationNodeName),
      region_code: this.text(row.regionCode),
      area_code: this.text(row.areaCode),
      erp_order_id: this.text(row.erpOrderId),
      erp_external_order_ref: this.text(row.erpExternalOrderRef),
      erp_order_created_at: this.timestamp(
        this.dateValue(row.erpOrderCreatedAt),
      ),
      erp_payment_status: this.text(row.erpPaymentStatus),
      erp_confirmation_status: this.text(row.erpConfirmationStatus),
      erp_fulfillment_status: this.text(row.erpFulfillmentStatus),
      erp_lifecycle_status: this.text(row.erpLifecycleStatus),
      erp_has_returned_full_items: row.erpHasReturnedFullItems === true,
      erp_returned_after_tax_amount: this.integer(
        row.erpReturnedAfterTaxAmount,
      ),
      erp_terminal_name: this.text(row.erpTerminalName),
      erp_grand_total: this.integer(row.erpGrandTotal),
      revenue_before_vat: this.revenueBeforeVat(row.erpGrandTotal),
      erp_payment_methods: this.arrayText(row.erpPaymentMethods).join('; '),
      erp_customer_type: this.text(row.erpCustomerType),
      erp_platform_id: this.integer(row.erpPlatformId),
      erp_consultant_custom_id: this.text(row.erpConsultantCustomId),
      erp_consultant_name: this.text(row.erpConsultantName),
      erp_fetched_at: this.timestamp(this.dateValue(row.erpFetchedAt)),
      erp_fetch_status: this.text(row.erpFetchStatus),
      created_at: this.timestamp(this.dateValue(row.createdAt)),
      updated_at: this.timestamp(this.dateValue(row.updatedAt)),
      synced_at: this.timestamp(syncedAt),
    };
  }

  private toItemRow(row: any, item: any, syncedAt: Date) {
    const submittedAt = this.dateValue(row.submittedAt);
    return {
      sales_report_id: this.text(row.id),
      sales_report_item_id: this.text(item.id),
      report_type: this.text(row.reportType),
      report_type_label: this.reportTypeLabel(row.reportType),
      submitted_at: this.timestamp(submittedAt),
      submitted_date: this.vietnamDate(submittedAt),
      order_code: this.text(row.orderCode),
      store_code: this.text(row.storeCode),
      store_name: this.text(row.storeName),
      created_by_email: this.text(row.createdByEmail),
      customer_type: this.text(row.customerType),
      customer_type_label: row.customerType
        ? this.customerTypeLabel(row.customerType)
        : '',
      sku: this.text(item.sku),
      seller_sku: this.text(item.sellerSku),
      product_name: this.text(item.name),
      brand_code: this.text(item.brandCode),
      brand_name: this.text(item.brandName),
      product_type_code: this.text(item.productTypeCode),
      product_type_name: this.text(item.productTypeName),
      product_group_id: this.text(item.productGroupId),
      product_group_code: this.text(item.productGroupCode),
      product_group_name: this.text(item.productGroupName),
      category_type: this.text(item.categoryType),
      quantity: this.integer(item.quantity),
      sell_price: this.integer(item.sellPrice),
      final_sell_price: this.integer(item.finalSellPrice),
      row_total: this.integer(item.rowTotal),
      row_revenue_before_vat: this.revenueBeforeVat(item.rowTotal),
      created_at: this.timestamp(this.dateValue(item.createdAt)),
      synced_at: this.timestamp(syncedAt),
    };
  }

  private toPaymentRow(row: any, payment: any, syncedAt: Date) {
    const submittedAt = this.dateValue(row.submittedAt);
    return {
      sales_report_id: this.text(row.id),
      sales_report_payment_id: this.text(payment.id),
      report_type: this.text(row.reportType),
      report_type_label: this.reportTypeLabel(row.reportType),
      submitted_at: this.timestamp(submittedAt),
      submitted_date: this.vietnamDate(submittedAt),
      order_code: this.text(row.orderCode),
      store_code: this.text(row.storeCode),
      store_name: this.text(row.storeName),
      created_by_email: this.text(row.createdByEmail),
      payment_method: this.text(payment.paymentMethod),
      amount: this.integer(payment.amount),
      paid_at: this.timestamp(this.dateValue(payment.paidAt)),
      transaction_code: this.text(payment.transactionCode),
      partner_transaction_code: this.text(payment.partnerTransactionCode),
      created_at: this.timestamp(this.dateValue(payment.createdAt)),
      synced_at: this.timestamp(syncedAt),
    };
  }

  private createBigQueryClient(config: SalesReportBigQueryConfig) {
    return new BigQuery({
      projectId: config.projectId,
      ...(config.keyFilename ? { keyFilename: config.keyFilename } : {}),
    });
  }

  private resolveConfig(): SalesReportBigQueryConfig | null {
    const projectId = this.firstEnv([
      'SALES_REPORT_BIGQUERY_PROJECT_ID',
      'BIGQUERY_PROJECT_ID',
    ]);
    const datasetId = this.firstEnv([
      'SALES_REPORT_BIGQUERY_DATASET_ID',
      'BIGQUERY_DATASET_ID',
    ]);
    if (!projectId || !datasetId) return null;
    const prefix =
      this.firstEnv(['SALES_REPORT_BIGQUERY_TABLE_PREFIX']) ??
      DEFAULT_TABLE_PREFIX;
    return {
      projectId,
      datasetId,
      keyFilename: this.firstEnv([
        'SALES_REPORT_BIGQUERY_KEY_FILE',
        'BIGQUERY_KEY_FILE',
        'GOOGLE_APPLICATION_CREDENTIALS',
      ]),
      reportTableId:
        this.firstEnv(['SALES_REPORT_BIGQUERY_REPORT_TABLE_ID']) ??
        `${prefix}_reports`,
      itemTableId:
        this.firstEnv(['SALES_REPORT_BIGQUERY_ITEM_TABLE_ID']) ??
        `${prefix}_items`,
      paymentTableId:
        this.firstEnv(['SALES_REPORT_BIGQUERY_PAYMENT_TABLE_ID']) ??
        `${prefix}_payments`,
      maxRows: this.envInt(
        'SALES_REPORT_BIGQUERY_MAX_ROWS',
        DEFAULT_MAX_ROWS,
        1,
        1_000_000,
      ),
    };
  }

  private skipped(
    reason: string,
    startedAt: number,
  ): SalesReportBigQuerySyncResult {
    return {
      skipped: true,
      reason,
      reportRows: 0,
      itemRows: 0,
      paymentRows: 0,
      tables: null,
      durationMs: Date.now() - startedAt,
    };
  }

  private tablePath(config: SalesReportBigQueryConfig, tableId: string) {
    return `${config.projectId}.${config.datasetId}.${tableId}`;
  }

  private categoryGroups(row: any) {
    const selections = Array.isArray(row.categorySelections)
      ? row.categorySelections
      : [];
    if (selections.length > 0) return selections;
    return [
      {
        categoryGroupId: row.categoryGroupId,
        categoryGroupName: row.categoryGroupName,
        categoryGroupNameVi: row.categoryGroupNameVi,
      },
    ].filter((category) => Boolean(category.categoryGroupId));
  }

  private answerLabel(code: unknown) {
    const text = this.text(code);
    return text ? (ANSWER_LABELS[text] ?? text) : '';
  }

  private reportTypeLabel(code: unknown) {
    return this.text(code) === 'PURCHASED' ? 'Mua hàng' : 'Chưa mua hàng';
  }

  private notPurchasedLabel(code: unknown) {
    const text = this.text(code);
    return text ? (NOT_PURCHASED_LABELS[text] ?? text) : '';
  }

  private customerTypeLabel(code: unknown) {
    const text = this.text(code);
    return text ? (CUSTOMER_TYPE_LABELS[text] ?? text) : '';
  }

  private promotionLabel(code: unknown) {
    const text = this.text(code);
    return text ? (PROMOTION_LABELS[text] ?? text) : '';
  }

  private installmentNoInstallmentReasonLabel(code: unknown) {
    const text = this.text(code);
    return text ? (INSTALLMENT_NO_INSTALLMENT_REASON_LABELS[text] ?? text) : '';
  }

  private installmentApprovedLabel(value: unknown) {
    if (value === true) return 'Đã duyệt';
    if (value === false) return 'Chưa duyệt';
    return '';
  }

  private finalPaymentMethodLabel(row: any) {
    const paymentText = this.arrayText(row?.erpPaymentMethods)
      .join(' ')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase();
    return paymentText.includes('installment') ||
      paymentText.includes('tra gop') ||
      paymentText.includes('tragop')
      ? 'Trả góp'
      : 'Trả thẳng';
  }

  private revenueBeforeVat(value: unknown) {
    const amount = this.integer(value);
    if (amount === null) return null;
    return Math.round(Math.max(amount, 0) / 1.08);
  }

  private text(value: unknown) {
    if (value === undefined || value === null) return '';
    return String(value).trim();
  }

  private arrayText(value: unknown) {
    return Array.isArray(value)
      ? value.map((item) => this.text(item)).filter(Boolean)
      : [];
  }

  private integer(value: unknown) {
    if (value === undefined || value === null || value === '') return null;
    const number = Number(value);
    return Number.isFinite(number) ? Math.trunc(number) : null;
  }

  private booleanOrNull(value: unknown) {
    if (value === true) return true;
    if (value === false) return false;
    return null;
  }

  private dateValue(value: unknown) {
    if (!value) return null;
    const date = value instanceof Date ? value : new Date(String(value));
    return Number.isNaN(date.getTime()) ? null : date;
  }

  private timestamp(value: Date | null) {
    return value ? value.toISOString() : null;
  }

  private vietnamDate(value: Date | null) {
    if (!value) return null;
    const vnDate = new Date(value.getTime() + 7 * 60 * 60 * 1000);
    const two = (part: number) => String(part).padStart(2, '0');
    return `${vnDate.getUTCFullYear()}-${two(vnDate.getUTCMonth() + 1)}-${two(vnDate.getUTCDate())}`;
  }

  private syncEnabled() {
    return this.envFlag('SALES_REPORT_BIGQUERY_SYNC_ENABLED', false);
  }

  private syncOnStartup() {
    return (
      this.syncEnabled() &&
      this.envFlag('SALES_REPORT_BIGQUERY_SYNC_ON_STARTUP', false)
    );
  }

  private envFlag(name: string, defaultValue: boolean) {
    const raw = process.env[name];
    if (raw === undefined) return defaultValue;
    const normalized = raw.trim().toLowerCase();
    if (!normalized) return defaultValue;
    return !['0', 'false', 'off', 'no'].includes(normalized);
  }

  private envInt(name: string, defaultValue: number, min: number, max: number) {
    const parsed = Number(process.env[name]);
    const value = Number.isFinite(parsed) ? Math.trunc(parsed) : defaultValue;
    return Math.max(min, Math.min(max, value));
  }

  private firstEnv(names: string[]) {
    return names
      .map((name) => process.env[name]?.trim())
      .find((value): value is string => Boolean(value));
  }

  private safeError(error: unknown) {
    if (error instanceof Error) return error.message;
    return String(error);
  }
}

const REPORT_SCHEMA: BigQueryField[] = [
  { name: 'sales_report_id', type: 'STRING' },
  { name: 'report_type', type: 'STRING' },
  { name: 'report_type_label', type: 'STRING' },
  { name: 'submitted_at', type: 'TIMESTAMP' },
  { name: 'submitted_date', type: 'DATE' },
  { name: 'order_code', type: 'STRING' },
  { name: 'customer_name', type: 'STRING' },
  { name: 'customer_phone', type: 'STRING' },
  { name: 'customer_need', type: 'STRING' },
  { name: 'category_group_id', type: 'STRING' },
  { name: 'category_group_name', type: 'STRING' },
  { name: 'category_group_name_vi', type: 'STRING' },
  { name: 'category_groups_vi', type: 'STRING' },
  { name: 'consulted_solution_answer', type: 'STRING' },
  { name: 'consulted_solution_label', type: 'STRING' },
  { name: 'consulted_solution_other_reason', type: 'STRING' },
  { name: 'experienced_answer', type: 'STRING' },
  { name: 'experienced_label', type: 'STRING' },
  { name: 'experienced_other_reason', type: 'STRING' },
  { name: 'zalo_answer', type: 'STRING' },
  { name: 'zalo_label', type: 'STRING' },
  { name: 'zalo_other_reason', type: 'STRING' },
  { name: 'app_download_answer', type: 'STRING' },
  { name: 'app_download_label', type: 'STRING' },
  { name: 'app_download_other_reason', type: 'STRING' },
  { name: 'not_purchased_reason', type: 'STRING' },
  { name: 'not_purchased_reason_label', type: 'STRING' },
  { name: 'not_purchased_other_reason', type: 'STRING' },
  { name: 'customer_type', type: 'STRING' },
  { name: 'customer_type_label', type: 'STRING' },
  { name: 'customer_is_student', type: 'BOOLEAN' },
  { name: 'promotion_codes', type: 'STRING' },
  { name: 'promotion_labels', type: 'STRING' },
  { name: 'installment_need', type: 'BOOLEAN' },
  { name: 'installment_approved', type: 'BOOLEAN' },
  { name: 'installment_approved_label', type: 'STRING' },
  { name: 'installment_loan_amount', type: 'INTEGER' },
  { name: 'installment_status', type: 'STRING' },
  { name: 'installment_failure_reason', type: 'STRING' },
  { name: 'installment_partner_codes', type: 'STRING' },
  { name: 'installment_no_installment_reason', type: 'STRING' },
  { name: 'installment_no_installment_reason_label', type: 'STRING' },
  { name: 'final_payment_method_label', type: 'STRING' },
  { name: 'created_by_user_id', type: 'STRING' },
  { name: 'created_by_email', type: 'STRING' },
  { name: 'created_by_name', type: 'STRING' },
  { name: 'created_by_personnel_code', type: 'STRING' },
  { name: 'store_code', type: 'STRING' },
  { name: 'store_name', type: 'STRING' },
  { name: 'organization_node_id', type: 'STRING' },
  { name: 'organization_node_name', type: 'STRING' },
  { name: 'region_code', type: 'STRING' },
  { name: 'area_code', type: 'STRING' },
  { name: 'erp_order_id', type: 'STRING' },
  { name: 'erp_external_order_ref', type: 'STRING' },
  { name: 'erp_order_created_at', type: 'TIMESTAMP' },
  { name: 'erp_payment_status', type: 'STRING' },
  { name: 'erp_confirmation_status', type: 'STRING' },
  { name: 'erp_fulfillment_status', type: 'STRING' },
  { name: 'erp_lifecycle_status', type: 'STRING' },
  { name: 'erp_has_returned_full_items', type: 'BOOLEAN' },
  { name: 'erp_returned_after_tax_amount', type: 'INTEGER' },
  { name: 'erp_terminal_name', type: 'STRING' },
  { name: 'erp_grand_total', type: 'INTEGER' },
  { name: 'revenue_before_vat', type: 'INTEGER' },
  { name: 'erp_payment_methods', type: 'STRING' },
  { name: 'erp_customer_type', type: 'STRING' },
  { name: 'erp_platform_id', type: 'INTEGER' },
  { name: 'erp_consultant_custom_id', type: 'STRING' },
  { name: 'erp_consultant_name', type: 'STRING' },
  { name: 'erp_fetched_at', type: 'TIMESTAMP' },
  { name: 'erp_fetch_status', type: 'STRING' },
  { name: 'created_at', type: 'TIMESTAMP' },
  { name: 'updated_at', type: 'TIMESTAMP' },
  { name: 'synced_at', type: 'TIMESTAMP' },
];

const ITEM_SCHEMA: BigQueryField[] = [
  { name: 'sales_report_id', type: 'STRING' },
  { name: 'sales_report_item_id', type: 'STRING' },
  { name: 'report_type', type: 'STRING' },
  { name: 'report_type_label', type: 'STRING' },
  { name: 'submitted_at', type: 'TIMESTAMP' },
  { name: 'submitted_date', type: 'DATE' },
  { name: 'order_code', type: 'STRING' },
  { name: 'store_code', type: 'STRING' },
  { name: 'store_name', type: 'STRING' },
  { name: 'created_by_email', type: 'STRING' },
  { name: 'customer_type', type: 'STRING' },
  { name: 'customer_type_label', type: 'STRING' },
  { name: 'sku', type: 'STRING' },
  { name: 'seller_sku', type: 'STRING' },
  { name: 'product_name', type: 'STRING' },
  { name: 'brand_code', type: 'STRING' },
  { name: 'brand_name', type: 'STRING' },
  { name: 'product_type_code', type: 'STRING' },
  { name: 'product_type_name', type: 'STRING' },
  { name: 'product_group_id', type: 'STRING' },
  { name: 'product_group_code', type: 'STRING' },
  { name: 'product_group_name', type: 'STRING' },
  { name: 'category_type', type: 'STRING' },
  { name: 'quantity', type: 'INTEGER' },
  { name: 'sell_price', type: 'INTEGER' },
  { name: 'final_sell_price', type: 'INTEGER' },
  { name: 'row_total', type: 'INTEGER' },
  { name: 'row_revenue_before_vat', type: 'INTEGER' },
  { name: 'created_at', type: 'TIMESTAMP' },
  { name: 'synced_at', type: 'TIMESTAMP' },
];

const PAYMENT_SCHEMA: BigQueryField[] = [
  { name: 'sales_report_id', type: 'STRING' },
  { name: 'sales_report_payment_id', type: 'STRING' },
  { name: 'report_type', type: 'STRING' },
  { name: 'report_type_label', type: 'STRING' },
  { name: 'submitted_at', type: 'TIMESTAMP' },
  { name: 'submitted_date', type: 'DATE' },
  { name: 'order_code', type: 'STRING' },
  { name: 'store_code', type: 'STRING' },
  { name: 'store_name', type: 'STRING' },
  { name: 'created_by_email', type: 'STRING' },
  { name: 'payment_method', type: 'STRING' },
  { name: 'amount', type: 'INTEGER' },
  { name: 'paid_at', type: 'TIMESTAMP' },
  { name: 'transaction_code', type: 'STRING' },
  { name: 'partner_transaction_code', type: 'STRING' },
  { name: 'created_at', type: 'TIMESTAMP' },
  { name: 'synced_at', type: 'TIMESTAMP' },
];
