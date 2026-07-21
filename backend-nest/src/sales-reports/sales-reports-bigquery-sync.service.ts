import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { BigQuery } from '@google-cloud/bigquery';
import { Cron } from '@nestjs/schedule';
import { promises as fs } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PrismaService } from '../prisma/prisma.service';

const DEFAULT_TABLE_PREFIX = 'opshub_sales_report';
const DEFAULT_MAX_ROWS = 100_000;
const INSTALLMENT_SUCCESS = 'SUCCESS';
const INSTALLMENT_FAILED = 'FAILED';

const ANSWER_LABELS: Record<string, string> = {
  NOT_CAPTURED: 'Không có dữ liệu lịch sử',
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

const CUSTOMER_CONTACT_CHANNEL_LABELS: Record<string, string> = {
  PHONE: 'Điện thoại',
  ZALO_PERSONAL: 'Zalo cá nhân',
  ZALO_OA: 'Zalo OA',
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
  fields?: BigQueryField[];
};

type SalesReportBigQueryConfig = {
  projectId: string;
  datasetId: string;
  keyFilename?: string;
  reportTableId: string;
  revenueTableId: string;
  itemTableId: string;
  paymentTableId: string;
  followUpTableId: string;
  maxRows: number;
};

export type SalesReportBigQuerySyncResult = {
  skipped: boolean;
  reason?: string;
  reportRows: number;
  revenueRows: number;
  itemRows: number;
  paymentRows: number;
  followUpRows: number;
  tables: {
    reports: string;
    revenueByStore: string;
    items: string;
    payments: string;
    followUps: string;
  } | null;
  durationMs: number;
};

type RevenueByStoreSummary = {
  storeCode: string;
  storeName: string;
  organizationNodeId: string;
  organizationNodeName: string;
  regionCode: string;
  areaCode: string;
  reportCount: number;
  installmentNeedTotalCount: number;
  successfulInstallmentOrderKeys: Set<string>;
  orderKeys: Set<string>;
  businessRevenue: number;
  personalRevenue: number;
  noInstallmentReasons: Map<string, number>;
  laptopQuantity: number;
  pcQuantity: number;
  assembledPcQuantity: number;
  appleQuantity: number;
  monitorQuantity: number;
  printerQuantity: number;
  accessoriesQuantity: number;
  extendedInsuranceQuantity: number;
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
      `Sales report BigQuery sync started: source=${source} dataset=${config.projectId}.${config.datasetId} reportTable=${config.reportTableId} revenueTable=${config.revenueTableId} itemTable=${config.itemTableId} paymentTable=${config.paymentTableId} followUpTable=${config.followUpTableId}`,
    );

    try {
      const client = this.createBigQueryClient(config);
      const [reports, followUpCases] = await Promise.all([
        this.prisma.salesReport.findMany({
          where: { erpExcludedAt: null },
          orderBy: [{ submittedAt: 'asc' }, { id: 'asc' }],
          take: config.maxRows,
          include: {
            categorySelections: { orderBy: { sortOrder: 'asc' } },
            items: { orderBy: { createdAt: 'asc' } },
            payments: { orderBy: { createdAt: 'asc' } },
          },
        }),
        this.prisma.salesReportFollowUpCase.findMany({
          where: { followUpCount: { gt: 0 } },
          orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
          take: config.maxRows,
          include: {
            sourceReport: {
              include: {
                categorySelections: { orderBy: { sortOrder: 'asc' } },
              },
            },
            entries: { orderBy: { sequenceNumber: 'asc' } },
          },
        }),
      ]);
      if (reports.length >= config.maxRows) {
        this.logger.warn(
          `Sales report BigQuery sync reached maxRows=${config.maxRows}; increase SALES_REPORT_BIGQUERY_MAX_ROWS if older rows are missing`,
        );
      }
      if (followUpCases.length >= config.maxRows) {
        this.logger.warn(
          `Sales report follow-up BigQuery sync reached maxRows=${config.maxRows}; increase SALES_REPORT_BIGQUERY_MAX_ROWS if older rows are missing`,
        );
      }

      const syncedAt = new Date();
      const reportRows = reports.map((row) => this.toReportRow(row, syncedAt));
      const revenueRows = this.toRevenueByStoreRows(reports, syncedAt);
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
      const followUpRows = followUpCases.map((row) =>
        this.toFollowUpRow(row, syncedAt),
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
        config.revenueTableId,
        REVENUE_BY_STORE_SCHEMA,
        revenueRows,
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
      await this.replaceTableRows(
        client,
        config,
        config.followUpTableId,
        this.followUpSchema(followUpCases),
        followUpRows,
      );

      const result: SalesReportBigQuerySyncResult = {
        skipped: false,
        reportRows: reportRows.length,
        revenueRows: revenueRows.length,
        itemRows: itemRows.length,
        paymentRows: paymentRows.length,
        followUpRows: followUpRows.length,
        tables: {
          reports: this.tablePath(config, config.reportTableId),
          revenueByStore: this.tablePath(config, config.revenueTableId),
          items: this.tablePath(config, config.itemTableId),
          payments: this.tablePath(config, config.paymentTableId),
          followUps: this.tablePath(config, config.followUpTableId),
        },
        durationMs: Date.now() - startedAt,
      };
      this.logger.log(
        `Sales report BigQuery sync succeeded: source=${source} reports=${result.reportRows} revenueByStore=${result.revenueRows} items=${result.itemRows} payments=${result.paymentRows} followUps=${result.followUpRows} durationMs=${result.durationMs}`,
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
      await this.waitForBigQueryJob(job);
    } finally {
      await fs.rm(tempDir, { recursive: true, force: true });
    }
  }

  private async waitForBigQueryJob(job: any) {
    if (!job) return;
    if (typeof job.promise === 'function') {
      await job.promise();
      return;
    }
    if (typeof job.getMetadata === 'function') {
      const [metadata] = await job.getMetadata();
      const error = metadata?.status?.errorResult;
      if (error) {
        throw new Error(error.message || JSON.stringify(error));
      }
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
    const contactChannelCodes = this.arrayText(row.customerContactChannels);
    return {
      sales_report_id: this.text(row.id),
      report_type: this.text(row.reportType),
      report_type_label: this.reportTypeLabel(row.reportType),
      entry_source: this.text(row.entrySource),
      submitted_at: this.timestamp(submittedAt),
      submitted_date: this.vietnamDate(submittedAt),
      order_code: this.text(row.orderCode),
      customer_name: this.text(row.customerName),
      customer_phone: this.text(row.customerPhone),
      customer_zalo_contact: this.text(row.customerZaloContact),
      customer_contact_channel_codes: contactChannelCodes.join('; '),
      customer_contact_channel_labels: contactChannelCodes
        .map((code) => this.customerContactChannelLabel(code))
        .join('; '),
      has_phone_contact: contactChannelCodes.includes('PHONE'),
      has_zalo_personal_contact: contactChannelCodes.includes('ZALO_PERSONAL'),
      has_zalo_oa_contact: contactChannelCodes.includes('ZALO_OA'),
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
      submitted_by_user_id: this.text(row.submittedByUserId),
      submitted_by_email: this.text(row.submittedByEmail),
      submitted_by_name: this.text(row.submittedByName),
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

  private toRevenueByStoreRows(reports: any[], syncedAt: Date) {
    const summaries = new Map<string, RevenueByStoreSummary>();
    for (const row of reports) {
      const summary = this.revenueSummaryForStore(summaries, row);
      summary.reportCount += 1;
      const hasInstallmentNeed = row.installmentNeed === true;
      if (hasInstallmentNeed) {
        summary.installmentNeedTotalCount += 1;
      }

      if (hasInstallmentNeed && row.installmentNoInstallmentReason) {
        const reasonCode = this.text(row.installmentNoInstallmentReason);
        if (reasonCode && reasonCode !== 'NORMAL_INSTALLMENT') {
          const label = this.installmentNoInstallmentReasonLabel(reasonCode);
          summary.noInstallmentReasons.set(
            label,
            (summary.noInstallmentReasons.get(label) ?? 0) + 1,
          );
        }
      }

      if (this.text(row.reportType) !== 'PURCHASED') continue;
      const orderKey = this.text(row.orderCode || row.erpOrderId || row.id);
      if (
        hasInstallmentNeed &&
        orderKey &&
        this.isReportedInstallmentSuccess(row)
      ) {
        summary.successfulInstallmentOrderKeys.add(orderKey);
      }
      if (!orderKey || summary.orderKeys.has(orderKey)) continue;
      summary.orderKeys.add(orderKey);

      const revenue = this.orderRevenue(row);
      if (this.text(row.customerType) === 'BUSINESS') {
        summary.businessRevenue += revenue;
      } else {
        summary.personalRevenue += revenue;
      }
      const componentQuantities = new Map<string, number>();
      for (const item of Array.isArray(row.items) ? row.items : []) {
        const type = this.normalizeSalesCategoryType(item?.categoryType);
        if (!type) continue;
        const quantity = this.salesItemQuantity(item);
        componentQuantities.set(
          type,
          (componentQuantities.get(type) ?? 0) + quantity,
        );
        if (type === 'laptop') summary.laptopQuantity += quantity;
        if (type === 'pc') summary.pcQuantity += quantity;
        if (type === 'apple' && this.isTargetAppleItem(item)) {
          summary.appleQuantity += quantity;
        }
        if (type === 'monitor') summary.monitorQuantity += quantity;
        if (type === 'printer') summary.printerQuantity += quantity;
        if (type === 'accessories') summary.accessoriesQuantity += quantity;
        if (type === 'extendedinsurance') {
          summary.extendedInsuranceQuantity += quantity;
        }
      }
      summary.assembledPcQuantity +=
        this.assembledPcQuantity(componentQuantities);
    }

    return Array.from(summaries.values())
      .sort((left, right) =>
        (left.storeCode || left.organizationNodeId).localeCompare(
          right.storeCode || right.organizationNodeId,
        ),
      )
      .map((summary) => ({
        store_code: summary.storeCode,
        store_name: summary.storeName,
        organization_node_id: summary.organizationNodeId,
        organization_node_name: summary.organizationNodeName,
        region_code: summary.regionCode,
        area_code: summary.areaCode,
        sales_report_count: summary.reportCount,
        installment_need_total_count: summary.installmentNeedTotalCount,
        successful_installment_order_count:
          summary.successfulInstallmentOrderKeys.size,
        order_count_unique: summary.orderKeys.size,
        business_revenue: summary.businessRevenue,
        personal_revenue: summary.personalRevenue,
        no_installment_reasons: Array.from(
          summary.noInstallmentReasons.entries(),
        )
          .map(([reason, count]) => `${reason}: ${count}`)
          .join('; '),
        laptop_quantity: summary.laptopQuantity,
        pc_quantity: summary.pcQuantity,
        assembled_pc_quantity: summary.assembledPcQuantity,
        apple_quantity: summary.appleQuantity,
        monitor_quantity: summary.monitorQuantity,
        printer_quantity: summary.printerQuantity,
        accessories_quantity: summary.accessoriesQuantity,
        extended_insurance_quantity: summary.extendedInsuranceQuantity,
        synced_at: this.timestamp(syncedAt),
      }));
  }

  private revenueSummaryForStore(
    summaries: Map<string, RevenueByStoreSummary>,
    row: any,
  ) {
    const key =
      this.text(row.storeCode) ||
      this.text(row.organizationNodeId) ||
      'UNKNOWN';
    let summary = summaries.get(key);
    if (!summary) {
      summary = {
        storeCode: this.text(row.storeCode),
        storeName: this.text(row.storeName),
        organizationNodeId: this.text(row.organizationNodeId),
        organizationNodeName: this.text(row.organizationNodeName),
        regionCode: this.text(row.regionCode),
        areaCode: this.text(row.areaCode),
        reportCount: 0,
        installmentNeedTotalCount: 0,
        successfulInstallmentOrderKeys: new Set<string>(),
        orderKeys: new Set<string>(),
        businessRevenue: 0,
        personalRevenue: 0,
        noInstallmentReasons: new Map<string, number>(),
        laptopQuantity: 0,
        pcQuantity: 0,
        assembledPcQuantity: 0,
        appleQuantity: 0,
        monitorQuantity: 0,
        printerQuantity: 0,
        accessoriesQuantity: 0,
        extendedInsuranceQuantity: 0,
      };
      summaries.set(key, summary);
    }
    summary.storeName ||= this.text(row.storeName);
    summary.organizationNodeId ||= this.text(row.organizationNodeId);
    summary.organizationNodeName ||= this.text(row.organizationNodeName);
    summary.regionCode ||= this.text(row.regionCode);
    summary.areaCode ||= this.text(row.areaCode);
    return summary;
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

  private toFollowUpRow(row: any, syncedAt: Date) {
    const report = row.sourceReport ?? {};
    const contactChannelCodes = this.arrayText(report.customerContactChannels);
    const result: Record<string, unknown> = {
      follow_up_case_id: this.text(row.id),
      source_report_id: this.text(row.sourceReportId || report.id),
      status: this.text(row.status),
      customer_name: this.text(report.customerName),
      customer_phone: this.text(report.customerPhone),
      customer_zalo_contact: this.text(report.customerZaloContact),
      customer_contact_channel_codes: contactChannelCodes.join('; '),
      customer_need: this.text(report.customerNeed),
      category_group_id: this.text(report.categoryGroupId),
      category_group_name_vi: this.text(report.categoryGroupNameVi),
      category_groups_vi: this.categoryGroups(report)
        .map((category: any) => category.categoryGroupNameVi)
        .filter(Boolean)
        .join('; '),
      store_code: this.text(report.storeCode),
      store_name: this.text(report.storeName),
      organization_node_id: this.text(report.organizationNodeId),
      organization_node_name: this.text(report.organizationNodeName),
      region_code: this.text(report.regionCode),
      area_code: this.text(report.areaCode),
      first_contact_at: this.timestamp(this.dateValue(report.submittedAt)),
      first_contact_by_user_id: this.text(report.createdByUserId),
      first_contact_by_email: this.text(report.createdByEmail),
      first_contact_by_name: this.text(report.createdByName),
      first_not_purchased_reason: this.text(report.notPurchasedReason),
      first_not_purchased_reason_label: report.notPurchasedReason
        ? this.notPurchasedLabel(report.notPurchasedReason)
        : '',
      first_not_purchased_other_reason: this.text(
        report.notPurchasedOtherReason,
      ),
      assignee_user_id: this.text(row.assigneeUserId),
      assignee_email: this.text(row.assigneeEmail),
      assignee_name: this.text(row.assigneeName),
      follow_up_count: this.integer(row.followUpCount) ?? 0,
      last_follow_up_at: this.timestamp(this.dateValue(row.lastFollowUpAt)),
      last_follow_up_by_user_id: this.text(row.lastFollowUpByUserId),
      last_follow_up_by_email: this.text(row.lastFollowUpByEmail),
      last_follow_up_by_name: this.text(row.lastFollowUpByName),
      closed_at: this.timestamp(this.dateValue(row.closedAt)),
      created_at: this.timestamp(this.dateValue(row.createdAt)),
      updated_at: this.timestamp(this.dateValue(row.updatedAt)),
      synced_at: this.timestamp(syncedAt),
    };
    for (const entry of Array.isArray(row.entries) ? row.entries : []) {
      const sequenceNumber = this.integer(entry?.sequenceNumber);
      if (sequenceNumber === null || sequenceNumber < 1) continue;
      result[`follow_up_${sequenceNumber}`] = {
        sequence_number: sequenceNumber,
        outcome: this.text(entry.outcome),
        outcome_label: this.followUpOutcomeLabel(entry.outcome),
        not_purchased_reason: this.text(entry.notPurchasedReason),
        not_purchased_reason_label: entry.notPurchasedReason
          ? this.notPurchasedLabel(entry.notPurchasedReason)
          : '',
        not_purchased_other_reason: this.text(entry.notPurchasedOtherReason),
        actor_user_id: this.text(entry.actorUserId),
        actor_email: this.text(entry.actorEmail),
        actor_name: this.text(entry.actorName),
        purchased_report_id: this.text(entry.purchasedReportId),
        contacted_at: this.timestamp(this.dateValue(entry.contactedAt)),
      };
    }
    return result;
  }

  private followUpSchema(rows: any[]) {
    const maxSequence = rows.reduce((max, row) => {
      const entries = Array.isArray(row?.entries) ? row.entries : [];
      return entries.reduce((entryMax: number, entry: any) => {
        const sequence = this.integer(entry?.sequenceNumber) ?? 0;
        return Math.max(entryMax, sequence);
      }, max);
    }, 0);
    return [
      ...FOLLOW_UP_BASE_SCHEMA,
      ...Array.from({ length: maxSequence }, (_, index) => ({
        name: `follow_up_${index + 1}`,
        type: 'RECORD',
        mode: 'NULLABLE',
        fields: FOLLOW_UP_ENTRY_SCHEMA,
      })),
    ];
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
      revenueTableId:
        this.firstEnv(['SALES_REPORT_BIGQUERY_REVENUE_TABLE_ID']) ??
        `${prefix}_revenue_by_store`,
      itemTableId:
        this.firstEnv(['SALES_REPORT_BIGQUERY_ITEM_TABLE_ID']) ??
        `${prefix}_items`,
      paymentTableId:
        this.firstEnv(['SALES_REPORT_BIGQUERY_PAYMENT_TABLE_ID']) ??
        `${prefix}_payments`,
      followUpTableId:
        this.firstEnv(['SALES_REPORT_BIGQUERY_FOLLOW_UP_TABLE_ID']) ??
        `${prefix}_follow_up_history`,
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
      revenueRows: 0,
      itemRows: 0,
      paymentRows: 0,
      followUpRows: 0,
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

  private followUpOutcomeLabel(code: unknown) {
    const text = this.text(code);
    return (
      {
        PURCHASED: 'Mua hàng',
        NOT_PURCHASED: 'Chưa mua',
        PURCHASED_ELSEWHERE: 'Đã mua nơi khác',
        NO_LONGER_INTERESTED: 'Hết nhu cầu',
      }[text] ?? text
    );
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
    if (this.text(row?.reportType) === 'NOT_PURCHASED') {
      return 'Chưa mua hàng';
    }
    return this.hasInstallmentPayment(row) ? 'Trả góp' : 'Trả thẳng';
  }

  private customerContactChannelLabel(code: unknown) {
    const text = this.text(code);
    return text ? (CUSTOMER_CONTACT_CHANNEL_LABELS[text] ?? text) : '';
  }

  private isReportedInstallmentSuccess(row: any) {
    const status = this.text(row?.installmentStatus).toUpperCase();
    if (status === INSTALLMENT_SUCCESS) return true;
    if (status === INSTALLMENT_FAILED) return false;
    return (
      this.text(row?.installmentNoInstallmentReason).toUpperCase() ===
      'NORMAL_INSTALLMENT'
    );
  }

  private hasInstallmentPayment(row: any) {
    const paymentText = this.arrayText(row?.erpPaymentMethods)
      .join(' ')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase();
    return (
      paymentText.includes('installment') ||
      paymentText.includes('tra gop') ||
      paymentText.includes('tragop')
    );
  }

  private orderRevenue(row: any) {
    const grandTotal = this.integer(row.erpGrandTotal);
    if (grandTotal !== null) return grandTotal;
    return (Array.isArray(row.items) ? row.items : []).reduce(
      (total: number, item: any) => {
        const rowTotal = this.integer(item?.rowTotal);
        if (rowTotal !== null) return total + rowTotal;
        const price = this.integer(item?.finalSellPrice);
        return price === null
          ? total
          : total + price * this.salesItemQuantity(item);
      },
      0,
    );
  }

  private salesItemQuantity(item: any) {
    const quantity = this.integer(item?.quantity);
    return quantity !== null && quantity > 0 ? quantity : 1;
  }

  private assembledPcQuantity(componentQuantities: Map<string, number>) {
    const requiredTypes = [
      'cpu',
      'mainboard',
      'memory',
      'storage',
      'case',
      'psu',
    ];
    const quantities = requiredTypes.map(
      (type) => componentQuantities.get(type) ?? 0,
    );
    const minQuantity = Math.min(...quantities);
    return Number.isFinite(minQuantity) && minQuantity > 0 ? minQuantity : 0;
  }

  private normalizeSalesCategoryType(value: unknown) {
    return this.text(value).replace(/\s+/g, '').toLowerCase();
  }

  private isTargetAppleItem(item: any) {
    const text = this.normalizeComparable(
      [item?.name, item?.productTypeName, item?.productGroupName]
        .filter(Boolean)
        .join(' '),
    );
    return ['macbook', 'iphone', 'ipad'].some((keyword) =>
      text.includes(keyword),
    );
  }

  private normalizeComparable(value: unknown) {
    return this.text(value)
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase();
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

const FOLLOW_UP_ENTRY_SCHEMA: BigQueryField[] = [
  { name: 'sequence_number', type: 'INTEGER' },
  { name: 'outcome', type: 'STRING' },
  { name: 'outcome_label', type: 'STRING' },
  { name: 'not_purchased_reason', type: 'STRING' },
  { name: 'not_purchased_reason_label', type: 'STRING' },
  { name: 'not_purchased_other_reason', type: 'STRING' },
  { name: 'actor_user_id', type: 'STRING' },
  { name: 'actor_email', type: 'STRING' },
  { name: 'actor_name', type: 'STRING' },
  { name: 'purchased_report_id', type: 'STRING' },
  { name: 'contacted_at', type: 'TIMESTAMP' },
];

const FOLLOW_UP_BASE_SCHEMA: BigQueryField[] = [
  { name: 'follow_up_case_id', type: 'STRING' },
  { name: 'source_report_id', type: 'STRING' },
  { name: 'status', type: 'STRING' },
  { name: 'customer_name', type: 'STRING' },
  { name: 'customer_phone', type: 'STRING' },
  { name: 'customer_zalo_contact', type: 'STRING' },
  { name: 'customer_contact_channel_codes', type: 'STRING' },
  { name: 'customer_need', type: 'STRING' },
  { name: 'category_group_id', type: 'STRING' },
  { name: 'category_group_name_vi', type: 'STRING' },
  { name: 'category_groups_vi', type: 'STRING' },
  { name: 'store_code', type: 'STRING' },
  { name: 'store_name', type: 'STRING' },
  { name: 'organization_node_id', type: 'STRING' },
  { name: 'organization_node_name', type: 'STRING' },
  { name: 'region_code', type: 'STRING' },
  { name: 'area_code', type: 'STRING' },
  { name: 'first_contact_at', type: 'TIMESTAMP' },
  { name: 'first_contact_by_user_id', type: 'STRING' },
  { name: 'first_contact_by_email', type: 'STRING' },
  { name: 'first_contact_by_name', type: 'STRING' },
  { name: 'first_not_purchased_reason', type: 'STRING' },
  { name: 'first_not_purchased_reason_label', type: 'STRING' },
  { name: 'first_not_purchased_other_reason', type: 'STRING' },
  { name: 'assignee_user_id', type: 'STRING' },
  { name: 'assignee_email', type: 'STRING' },
  { name: 'assignee_name', type: 'STRING' },
  { name: 'follow_up_count', type: 'INTEGER' },
  { name: 'last_follow_up_at', type: 'TIMESTAMP' },
  { name: 'last_follow_up_by_user_id', type: 'STRING' },
  { name: 'last_follow_up_by_email', type: 'STRING' },
  { name: 'last_follow_up_by_name', type: 'STRING' },
  { name: 'closed_at', type: 'TIMESTAMP' },
  { name: 'created_at', type: 'TIMESTAMP' },
  { name: 'updated_at', type: 'TIMESTAMP' },
  { name: 'synced_at', type: 'TIMESTAMP' },
];

const REPORT_SCHEMA: BigQueryField[] = [
  { name: 'sales_report_id', type: 'STRING' },
  { name: 'report_type', type: 'STRING' },
  { name: 'report_type_label', type: 'STRING' },
  { name: 'entry_source', type: 'STRING' },
  { name: 'submitted_at', type: 'TIMESTAMP' },
  { name: 'submitted_date', type: 'DATE' },
  { name: 'order_code', type: 'STRING' },
  { name: 'customer_name', type: 'STRING' },
  { name: 'customer_phone', type: 'STRING' },
  { name: 'customer_zalo_contact', type: 'STRING' },
  { name: 'customer_contact_channel_codes', type: 'STRING' },
  { name: 'customer_contact_channel_labels', type: 'STRING' },
  { name: 'has_phone_contact', type: 'BOOLEAN' },
  { name: 'has_zalo_personal_contact', type: 'BOOLEAN' },
  { name: 'has_zalo_oa_contact', type: 'BOOLEAN' },
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
  { name: 'submitted_by_user_id', type: 'STRING' },
  { name: 'submitted_by_email', type: 'STRING' },
  { name: 'submitted_by_name', type: 'STRING' },
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

const REVENUE_BY_STORE_SCHEMA: BigQueryField[] = [
  { name: 'store_code', type: 'STRING' },
  { name: 'store_name', type: 'STRING' },
  { name: 'organization_node_id', type: 'STRING' },
  { name: 'organization_node_name', type: 'STRING' },
  { name: 'region_code', type: 'STRING' },
  { name: 'area_code', type: 'STRING' },
  { name: 'sales_report_count', type: 'INTEGER' },
  { name: 'installment_need_total_count', type: 'INTEGER' },
  { name: 'successful_installment_order_count', type: 'INTEGER' },
  { name: 'order_count_unique', type: 'INTEGER' },
  { name: 'business_revenue', type: 'INTEGER' },
  { name: 'personal_revenue', type: 'INTEGER' },
  { name: 'no_installment_reasons', type: 'STRING' },
  { name: 'laptop_quantity', type: 'INTEGER' },
  { name: 'pc_quantity', type: 'INTEGER' },
  { name: 'assembled_pc_quantity', type: 'INTEGER' },
  { name: 'apple_quantity', type: 'INTEGER' },
  { name: 'monitor_quantity', type: 'INTEGER' },
  { name: 'printer_quantity', type: 'INTEGER' },
  { name: 'accessories_quantity', type: 'INTEGER' },
  { name: 'extended_insurance_quantity', type: 'INTEGER' },
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
