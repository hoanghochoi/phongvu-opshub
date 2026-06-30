import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { isSuperAdminRole } from '../common/system-role';
import { PrismaService } from '../prisma/prisma.service';
import { SalesReportCategoriesService } from './sales-report-categories.service';
import {
  SalesReportErpOrder,
  SalesReportErpService,
} from './sales-report-erp.service';
import {
  APP_DOWNLOAD_REASON_CODES,
  CreateSalesReportDto,
  CUSTOMER_TYPE_CODES,
  ExportSalesReportsDto,
  EXPERIENCE_REASON_CODES,
  INSTALLMENT_NO_INSTALLMENT_REASON_CODES,
  INSTALLMENT_PARTNER_CODES,
  INSTALLMENT_STATUSES,
  ListSalesReportsDto,
  NOT_PURCHASED_REASON_CODES,
  PROMOTION_CODES,
  SALES_REPORT_EXPORT_TYPES,
  SALES_REPORT_TYPES,
  YES_NO_REASON_CODES,
  ZALO_REASON_CODES,
} from './sales-reports.dto';

const REPORT_TYPE_PURCHASED = 'PURCHASED';
const REPORT_TYPE_NOT_PURCHASED = 'NOT_PURCHASED';
const EXPORT_TYPE_HVTC = 'HVTC';
const EXPORT_TYPE_REVENUE = 'REVENUE';
const DEFAULT_PAGE_SIZE = 20;
const INSTALLMENT_SUCCESS = 'SUCCESS';
const INSTALLMENT_FAILED = 'FAILED';

type SalesReportFilters = {
  reportType: string | null;
  orderCode: string | null;
  categoryGroupId: string | null;
  reporter: string | null;
  storeIds: string[];
  requestedAllStores: boolean;
  dateRange: { start: Date; end: Date } | null;
  page: number;
  limit: number;
};

const ANSWER_LABELS: Record<string, string> = {
  YES: 'Có',
  CUSTOMER_BUSY_OR_NO_NEED:
    'Không - KH vội/không có nhu cầu/không muốn tư vấn/chỉ tham quan',
  OUT_OF_STOCK_OR_NO_EQUIVALENT: 'Không - Hết hàng/không có SP tương đương',
  PRODUCT_NOT_SOLD_OR_NOT_IN_STORE:
    'Không - SP KH cần không kinh doanh/không có tại CH',
  PRICE_HIGH: 'Không - SP giá cao',
  SALES_FORGOT: 'Không - Sales quên tư vấn',
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

const INSTALLMENT_LABELS: Record<string, string> = {
  SUCCESS: 'Trả góp thành công',
  FAILED: 'Trả góp thất bại',
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

const INSTALLMENT_PARTNER_LABELS: Record<string, string> = {
  VNPAY_POS: 'VNPAY - POS',
  PAYOO_POS: 'PAYOO - POS',
  HOMECREDIT_CTTC: 'HomeCredit - CTTC',
  SHINHAN_CTTC: 'Shinhan - CTTC',
  HDSAISON_CTTC: 'HDSaison - CTTC',
  AEON_FINANCE_CTTC: 'AEON Finance - CTTC',
  MIRAE_ASSET: 'Mirae Asset',
  MPOS: 'MPOS',
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

@Injectable()
export class SalesReportsService {
  private readonly logger = new Logger(SalesReportsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly categories: SalesReportCategoriesService,
    private readonly erp: SalesReportErpService,
  ) {}

  async categoriesForReport() {
    return this.categories.listCategories();
  }

  async checkOrder(user: any, orderCodeInput: string) {
    const orderCode = this.normalizeOrderCode(orderCodeInput);
    await this.assertOrderNotReported(orderCode);
    const context = await this.resolveUserSnapshot(user);
    const erpOrder = await this.erp.lookupOrder(orderCode, context.storeCode);
    await this.attachCategoryTypes(erpOrder);
    const matchedCategories = await this.categories.matchCategoriesFromErp(
      erpOrder.categoryCandidates,
    );
    return {
      orderCode,
      customerName: erpOrder.customerName,
      customerNeed: erpOrder.customerNeed,
      customerType: erpOrder.customerType,
      customerTypeLabel: this.customerTypeLabel(erpOrder.customerType),
      categoryGroup: matchedCategories[0] ?? null,
      categoryGroups: matchedCategories,
      order: this.toOrderDto(erpOrder),
      items: erpOrder.items,
      payments: erpOrder.payments,
      paymentMethods: erpOrder.paymentMethods,
    };
  }

  async create(user: any, body: CreateSalesReportDto) {
    const startedAt = Date.now();
    const reportType = this.normalizeEnum(body.reportType, SALES_REPORT_TYPES);
    const orderCode =
      reportType === REPORT_TYPE_PURCHASED
        ? this.normalizeOrderCode(body.orderCode)
        : null;
    this.validateCreateBody(reportType, orderCode, body);
    const categoryIds = this.normalizeCategoryGroupIds(body);
    const promotionCodes = this.normalizePromotionCodes(body.promotionCodes);
    const categories = await this.categories.requireCategories(categoryIds);
    const primaryCategory = categories[0]!;
    const context = await this.resolveUserSnapshot(user);
    const customerName = this.requireCustomerName(body.customerName);
    let erpOrder: SalesReportErpOrder | null = null;
    if (reportType === REPORT_TYPE_PURCHASED) {
      await this.assertOrderNotReported(orderCode);
      erpOrder = await this.erp.lookupOrder(orderCode ?? '', context.storeCode);
      await this.attachCategoryTypes(erpOrder);
    }
    const customerType = this.normalizeCustomerType(
      erpOrder?.customerType ?? this.optionalText(body.customerType, 20),
    );
    const customerIsStudent = body.customerIsStudent === true;
    this.assertCustomerTypeStudentConsistency(customerType, customerIsStudent);
    const installment = this.normalizeInstallmentSelection(body);

    this.logger.log(
      `Sales report create started: user=${this.safeUserLabel(user)} type=${reportType} primaryCategory=${primaryCategory.id} categoryCount=${categories.length} hasOrder=${Boolean(orderCode)} hasCustomerName=${Boolean(customerName)} customerType=${customerType} hasInstallmentNeed=${installment.need} promotionCount=${promotionCodes.length}`,
    );
    try {
      const report = await this.prisma.salesReport.create({
        data: {
          reportType,
          orderCode,
          customerName,
          customerPhone: this.optionalText(body.customerPhone, 30),
          customerNeed:
            this.optionalText(body.customerNeed, 500) ??
            erpOrder?.customerNeed ??
            null,
          categoryGroupId: primaryCategory.id,
          categoryGroupName: primaryCategory.catGroupName,
          categoryGroupNameVi: primaryCategory.catGroupNameVi,
          consultedSolutionAnswer: body.consultedSolutionAnswer,
          consultedSolutionOtherReason: this.optionalText(
            body.consultedSolutionOtherReason,
            500,
          ),
          experiencedAnswer: body.experiencedAnswer,
          experiencedOtherReason: this.optionalText(
            body.experiencedOtherReason,
            500,
          ),
          zaloAnswer: body.zaloAnswer,
          zaloOtherReason: this.optionalText(body.zaloOtherReason, 500),
          appDownloadAnswer: body.appDownloadAnswer,
          appDownloadOtherReason: this.optionalText(
            body.appDownloadOtherReason,
            500,
          ),
          notPurchasedReason:
            reportType === REPORT_TYPE_NOT_PURCHASED
              ? this.normalizeEnum(
                  body.notPurchasedReason,
                  NOT_PURCHASED_REASON_CODES,
                )
              : null,
          notPurchasedOtherReason: this.optionalText(
            body.notPurchasedOtherReason,
            500,
          ),
          customerType,
          customerIsStudent,
          promotionCodes,
          installmentNeed: installment.need,
          installmentApproved: installment.approved,
          installmentLoanAmount: installment.loanAmount,
          installmentNoInstallmentReason: installment.noInstallmentReason,
          installmentStatus: installment.status,
          installmentFailureReason: installment.failureReason,
          installmentPartnerCodes: installment.partnerCodes,
          ...context,
          ...(erpOrder ? this.erpCreateData(erpOrder) : {}),
          rawResponses: {
            reportType,
            answerLabels: {
              consultedSolution: this.answerLabel(body.consultedSolutionAnswer),
              experienced: this.answerLabel(body.experiencedAnswer),
              zalo: this.answerLabel(body.zaloAnswer),
              appDownload: this.answerLabel(body.appDownloadAnswer),
              notPurchased: body.notPurchasedReason
                ? this.notPurchasedLabel(body.notPurchasedReason)
                : null,
              installment: installment.status
                ? this.installmentLabel(installment.status)
                : null,
              installmentPartners: installment.partnerCodes.map((code) =>
                this.installmentPartnerLabel(code),
              ),
              customerType: this.customerTypeLabel(customerType),
              customerIsStudent,
              promotions: promotionCodes.map((code) =>
                this.promotionLabel(code),
              ),
              installmentApproved: installment.approved,
              installmentNoInstallmentReason: installment.noInstallmentReason
                ? this.installmentNoInstallmentReasonLabel(
                    installment.noInstallmentReason,
                  )
                : null,
            },
          },
          categorySelections: {
            create: categories.map((category, index) => ({
              categoryGroupId: category.id,
              categoryGroupName: category.catGroupName,
              categoryGroupNameVi: category.catGroupNameVi,
              sortOrder: index,
            })),
          },
          items: erpOrder
            ? {
                create: erpOrder.items.map((item) => ({
                  sku: item.sku,
                  sellerSku: item.sellerSku,
                  name: item.name,
                  brandCode: item.brandCode,
                  brandName: item.brandName,
                  productTypeCode: item.productTypeCode,
                  productTypeName: item.productTypeName,
                  productGroupId: item.productGroupId,
                  productGroupCode: item.productGroupCode,
                  productGroupName: item.productGroupName,
                  categoryType: item.categoryType,
                  quantity: item.quantity,
                  sellPrice: item.sellPrice,
                  finalSellPrice: item.finalSellPrice,
                  rowTotal: item.rowTotal,
                  raw: item.raw as Prisma.InputJsonValue,
                })),
              }
            : undefined,
          payments: erpOrder
            ? {
                create: erpOrder.payments.map((payment) => ({
                  paymentMethod: payment.paymentMethod,
                  amount: payment.amount,
                  paidAt: payment.paidAt,
                  transactionCode: payment.transactionCode,
                  partnerTransactionCode: payment.partnerTransactionCode,
                  raw: payment.raw as Prisma.InputJsonValue,
                })),
              }
            : undefined,
        },
        include: {
          categorySelections: true,
          items: true,
          payments: true,
        },
      });
      this.logger.log(
        `Sales report create succeeded: id=${report.id} user=${this.safeUserLabel(user)} type=${reportType} durationMs=${Date.now() - startedAt}`,
      );
      return this.toReportDto(report);
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        throw new BadRequestException('Đơn hàng này đã được báo cáo mua hàng.');
      }
      this.logger.error(
        `Sales report create failed: user=${this.safeUserLabel(user)} type=${reportType} durationMs=${Date.now() - startedAt} error=${String(error)}`,
      );
      throw error;
    }
  }

  async list(user: any, query: ListSalesReportsDto) {
    const filters = this.normalizeFilters(query);
    const scopeWhere = await this.resolveAdminScopeWhere(user, {
      requestedAllStores: filters.requestedAllStores,
      storeIds: filters.storeIds,
    });
    const where = this.andWhere(scopeWhere, this.buildFilterWhere(filters));
    const [total, rows] = await this.prisma.$transaction([
      this.prisma.salesReport.count({ where }),
      this.prisma.salesReport.findMany({
        where,
        orderBy: { submittedAt: 'desc' },
        skip: filters.page * filters.limit,
        take: filters.limit,
        include: {
          categorySelections: { orderBy: { sortOrder: 'asc' } },
          items: { take: 20, orderBy: { createdAt: 'asc' } },
          payments: { take: 20, orderBy: { createdAt: 'asc' } },
        },
      }),
    ]);
    this.logger.log(
      `Sales reports list completed: user=${this.safeUserLabel(user)} count=${rows.length} total=${total} page=${filters.page}`,
    );
    return {
      items: rows.map((row) => this.toReportDto(row)),
      page: filters.page,
      limit: filters.limit,
      total,
      hasMore: (filters.page + 1) * filters.limit < total,
    };
  }

  async exportCsv(user: any, query: ExportSalesReportsDto) {
    const filters = this.normalizeFilters({ ...query, page: 0, limit: 100 });
    const exportType = this.normalizeExportType(query.exportType);
    const scopeWhere = await this.resolveAdminScopeWhere(user, {
      requestedAllStores: filters.requestedAllStores,
      storeIds: filters.storeIds,
    });
    const where = this.andWhere(scopeWhere, this.buildFilterWhere(filters));
    const rows = await this.prisma.salesReport.findMany({
      where,
      orderBy: { submittedAt: 'desc' },
      take: 10_000,
      include: {
        categorySelections: { orderBy: { sortOrder: 'asc' } },
        items: { orderBy: { createdAt: 'asc' } },
        payments: { orderBy: { createdAt: 'asc' } },
      },
    });
    this.logger.log(
      `Sales reports export completed: user=${this.safeUserLabel(user)} type=${exportType} count=${rows.length}`,
    );
    return exportType === EXPORT_TYPE_REVENUE
      ? this.buildRevenueCsv(rows)
      : this.buildHvtcCsv(rows);
  }

  private validateCreateBody(
    reportType: string,
    orderCode: string | null,
    body: CreateSalesReportDto,
  ) {
    if (reportType === REPORT_TYPE_PURCHASED && !orderCode) {
      throw new BadRequestException('Vui lòng nhập mã đơn hàng.');
    }
    if (reportType === REPORT_TYPE_NOT_PURCHASED && !body.notPurchasedReason) {
      throw new BadRequestException('Vui lòng chọn lý do khách chưa mua hàng.');
    }
    if (!this.optionalText(body.customerName, 120)) {
      throw new BadRequestException('Vui lòng nhập tên khách hàng.');
    }
    if (!this.optionalText(body.customerNeed, 500)) {
      throw new BadRequestException('Vui lòng nhập nhu cầu khách hàng.');
    }
    this.requireAnswer(
      body.consultedSolutionAnswer,
      YES_NO_REASON_CODES,
      'Vui lòng chọn kết quả tư vấn 3 giải pháp.',
    );
    this.requireAnswer(
      body.experiencedAnswer,
      EXPERIENCE_REASON_CODES,
      'Vui lòng chọn kết quả trải nghiệm sản phẩm.',
    );
    this.requireAnswer(
      body.zaloAnswer,
      ZALO_REASON_CODES,
      'Vui lòng chọn kết quả quét Zalo.',
    );
    this.requireAnswer(
      body.appDownloadAnswer,
      APP_DOWNLOAD_REASON_CODES,
      'Vui lòng chọn kết quả tải App PV.',
    );
    this.requireOtherReason(
      body.consultedSolutionAnswer,
      body.consultedSolutionOtherReason,
      'Vui lòng nhập lý do khác cho phần tư vấn 3 giải pháp.',
    );
    this.requireOtherReason(
      body.experiencedAnswer,
      body.experiencedOtherReason,
      'Vui lòng nhập lý do khác cho phần trải nghiệm sản phẩm.',
    );
    this.requireOtherReason(
      body.zaloAnswer,
      body.zaloOtherReason,
      'Vui lòng nhập lý do khác cho phần quét Zalo.',
    );
    this.requireOtherReason(
      body.appDownloadAnswer,
      body.appDownloadOtherReason,
      'Vui lòng nhập lý do khác cho phần tải App PV.',
    );
    if (body.notPurchasedReason === 'OTHER') {
      this.requireOtherReason(
        body.notPurchasedReason,
        body.notPurchasedOtherReason,
        'Vui lòng nhập lý do khác khi khách chưa mua hàng.',
      );
    }
  }

  private normalizeCategoryGroupIds(body: CreateSalesReportDto) {
    const ids = [
      ...(Array.isArray(body.categoryGroupIds) ? body.categoryGroupIds : []),
      body.categoryGroupId,
    ]
      .map((value) =>
        String(value || '')
          .trim()
          .toUpperCase()
          .replace(/[^A-Z0-9_]/g, ''),
      )
      .filter(Boolean);
    const unique = Array.from(new Set(ids));
    if (unique.length === 0) {
      throw new BadRequestException('Vui lòng chọn ít nhất một ngành hàng.');
    }
    return unique.slice(0, 20);
  }

  private normalizeInstallmentSelection(body: CreateSalesReportDto) {
    const rawStatus = this.optionalText(body.installmentStatus, 20);
    const legacyStatus = rawStatus
      ? this.normalizeEnum(rawStatus, INSTALLMENT_STATUSES)
      : null;
    const need = body.installmentNeed === true || Boolean(legacyStatus);
    const approved =
      typeof body.installmentApproved === 'boolean'
        ? body.installmentApproved
        : null;
    const loanAmount = this.optionalInt(
      body.installmentLoanAmount,
      10_000_000_000,
      'Số tiền vay không hợp lệ.',
    );
    const noInstallmentReason = this.normalizeOptionalEnum(
      body.installmentNoInstallmentReason,
      INSTALLMENT_NO_INSTALLMENT_REASON_CODES,
      'Lý do không trả góp không hợp lệ.',
    );
    const legacyFailureReason = this.optionalText(
      body.installmentFailureReason,
      500,
    );
    const partnerCodes = this.normalizeInstallmentPartnerCodes(
      body.installmentPartnerCodes,
    );
    if (!need) {
      if (
        legacyFailureReason ||
        noInstallmentReason ||
        partnerCodes.length > 0 ||
        approved !== null ||
        loanAmount !== null
      ) {
        throw new BadRequestException(
          'Vui lòng tick Có nhu cầu trả góp trước khi nhập thông tin trả góp.',
        );
      }
      return {
        need: false,
        approved: null,
        loanAmount: null,
        noInstallmentReason: null,
        status: null,
        failureReason: null,
        partnerCodes: [],
      };
    }
    if (partnerCodes.length === 0) {
      throw new BadRequestException('Vui lòng chọn đối tác trả góp.');
    }
    if (approved === null) {
      throw new BadRequestException(
        'Vui lòng chọn hồ sơ trả góp đã được duyệt hay chưa.',
      );
    }
    if (!noInstallmentReason && !legacyStatus) {
      throw new BadRequestException('Vui lòng chọn lý do không trả góp.');
    }
    if (noInstallmentReason === 'NORMAL_INSTALLMENT' && approved === false) {
      throw new BadRequestException(
        'Hồ sơ chưa được duyệt thì cần chọn lý do không trả góp phù hợp.',
      );
    }
    const status =
      noInstallmentReason === 'NORMAL_INSTALLMENT' ||
      legacyStatus === INSTALLMENT_SUCCESS
        ? INSTALLMENT_SUCCESS
        : INSTALLMENT_FAILED;
    const failureReason =
      status === INSTALLMENT_FAILED
        ? (legacyFailureReason ??
          (noInstallmentReason
            ? this.installmentNoInstallmentReasonLabel(noInstallmentReason)
            : null))
        : null;
    return {
      need: true,
      approved,
      loanAmount,
      noInstallmentReason,
      status,
      failureReason,
      partnerCodes,
    };
  }

  private normalizeCustomerType(value: unknown) {
    const normalized = this.normalizeOptionalEnum(
      value,
      CUSTOMER_TYPE_CODES,
      'Loại khách hàng không hợp lệ.',
    );
    if (!normalized) {
      throw new BadRequestException('Vui lòng chọn loại khách hàng.');
    }
    return normalized;
  }

  private requireCustomerName(value: unknown) {
    const customerName = this.optionalText(value, 120);
    if (!customerName) {
      throw new BadRequestException('Vui lòng nhập tên khách hàng.');
    }
    return customerName;
  }

  private assertCustomerTypeStudentConsistency(
    customerType: string,
    customerIsStudent: boolean,
  ) {
    if (customerType === 'BUSINESS' && customerIsStudent) {
      this.logger.warn(
        `Sales report blocked invalid customer flags: customerType=${customerType} customerIsStudent=${customerIsStudent}`,
      );
      throw new BadRequestException(
        'Doanh nghiệp không thể đồng thời là Học sinh - Sinh viên.',
      );
    }
  }

  private normalizePromotionCodes(value: unknown) {
    const raw = Array.isArray(value) ? value : [];
    const codes = raw
      .map((item) =>
        String(item || '')
          .trim()
          .toUpperCase(),
      )
      .filter(Boolean);
    const unique = Array.from(new Set(codes)).slice(0, 10);
    const invalid = unique.find(
      (code) => !PROMOTION_CODES.includes(code as any),
    );
    if (invalid) {
      throw new BadRequestException('CTKM áp dụng không hợp lệ.');
    }
    return unique;
  }

  private normalizeInstallmentPartnerCodes(value: unknown) {
    const raw = Array.isArray(value) ? value : [];
    const codes = raw
      .map((item) =>
        String(item || '')
          .trim()
          .toUpperCase(),
      )
      .filter(Boolean);
    const unique = Array.from(new Set(codes)).slice(0, 10);
    const invalid = unique.find(
      (code) => !INSTALLMENT_PARTNER_CODES.includes(code as any),
    );
    if (invalid) {
      throw new BadRequestException('Đối tác trả góp không hợp lệ.');
    }
    return unique;
  }

  private async assertOrderNotReported(orderCode: string | null) {
    if (!orderCode) return;
    const existing = await this.prisma.salesReport.findUnique({
      where: { orderCode },
      select: { id: true },
    });
    if (existing) {
      throw new BadRequestException('Đơn hàng này đã được báo cáo mua hàng.');
    }
  }

  private async resolveUserSnapshot(user: any) {
    const savedUser = user?.id
      ? await this.prisma.user.findUnique({
          where: { id: user.id },
          include: {
            store: {
              include: {
                area: { include: { region: true } },
                organizationNode: true,
              },
            },
            region: true,
            area: { include: { region: true } },
            organizationNode: true,
            organizationAssignments: {
              where: { isActive: true },
              orderBy: [
                { isPrimary: Prisma.SortOrder.desc },
                { createdAt: Prisma.SortOrder.asc },
              ],
              include: {
                organizationNode: {
                  include: organizationNodeStoreTreeInclude(),
                },
              },
            },
          },
        })
      : null;
    const source = savedUser ?? user ?? {};
    const primaryAssignment = source.organizationAssignments?.[0] ?? null;
    const assignedStore =
      storesForOrganizationNodeTree(primaryAssignment?.organizationNode)[0] ??
      source.store ??
      null;
    const organizationNode =
      primaryAssignment?.organizationNode ??
      source.organizationNode ??
      assignedStore?.organizationNode ??
      null;
    const area =
      assignedStore?.area ?? source.area ?? source.store?.area ?? null;
    const region = area?.region ?? source.region ?? null;
    return {
      createdByUserId: source.id ?? null,
      createdByEmail: source.email ?? null,
      createdByName:
        [source.firstName, source.lastName].filter(Boolean).join(' ').trim() ||
        null,
      createdByPersonnelCode: this.personnelCodeFor(source, assignedStore),
      storeCode: assignedStore?.storeId ?? source.storeCode ?? null,
      storeName: assignedStore?.storeName ?? source.storeName ?? null,
      organizationNodeId:
        organizationNode?.id ?? source.organizationNodeId ?? null,
      organizationNodeName:
        organizationNode?.displayName ?? source.organizationNodeName ?? null,
      regionCode: region?.code ?? source.regionCode ?? null,
      areaCode: area?.code ?? source.areaCode ?? null,
    };
  }

  private async resolveAdminScopeWhere(
    user: any,
    input: { requestedAllStores?: boolean; storeIds?: string[] },
  ): Promise<Prisma.SalesReportWhereInput> {
    if (isSuperAdminRole(user?.role)) {
      if (input.storeIds?.length) {
        return { storeCode: this.storeCodeWhere(input.storeIds) };
      }
      return {};
    }
    const allowedStores = await this.resolveUserStores(user);
    const allowedStoreCodes = allowedStores.map((store) => store.storeId);
    const selected =
      input.storeIds && input.storeIds.length > 0
        ? input.storeIds
        : allowedStoreCodes;
    if (input.requestedAllStores && allowedStoreCodes.length === 0) {
      throw new ForbiddenException('Tài khoản chưa được gán showroom.');
    }
    const invalid = selected.find(
      (storeCode) => !allowedStoreCodes.includes(storeCode),
    );
    if (invalid) {
      throw new ForbiddenException(
        'Chỉ được xem báo cáo trong phạm vi được gán.',
      );
    }
    return { storeCode: this.storeCodeWhere(selected) };
  }

  private async resolveUserStores(user: any) {
    const storesByCode = new Map<string, any>();
    const pushStore = (store: any) => {
      const storeCode = String(store?.storeId || '')
        .trim()
        .toUpperCase();
      if (storeCode && !storesByCode.has(storeCode)) {
        storesByCode.set(storeCode, store);
      }
    };
    if (user?.id) {
      const savedUser = await this.prisma.user.findUnique({
        where: { id: user.id },
        include: {
          store: true,
          organizationAssignments: {
            where: { isActive: true },
            orderBy: [
              { isPrimary: Prisma.SortOrder.desc },
              { createdAt: Prisma.SortOrder.asc },
            ],
            include: {
              organizationNode: {
                include: organizationNodeStoreTreeInclude(),
              },
            },
          },
        },
      });
      pushStore(savedUser?.store);
      for (const assignment of savedUser?.organizationAssignments ?? []) {
        for (const store of storesForOrganizationNodeTree(
          assignment.organizationNode,
        )) {
          pushStore(store);
        }
      }
    }
    const stores = Array.from(storesByCode.values());
    if (stores.length === 0) {
      throw new ForbiddenException('Tài khoản chưa được gán showroom.');
    }
    return stores;
  }

  private normalizeFilters(query: ListSalesReportsDto): SalesReportFilters {
    return {
      reportType:
        query.reportType && query.reportType !== 'ALL'
          ? this.normalizeEnum(query.reportType, SALES_REPORT_TYPES)
          : null,
      orderCode: this.optionalText(query.orderCode, 80),
      categoryGroupId: this.optionalText(query.categoryGroupId, 40),
      reporter: this.optionalText(query.reporter, 120),
      storeIds: this.parseStoreCodes(query.storeIds),
      requestedAllStores: query.allStores === 'true',
      dateRange: this.parseDateRange(query.startDate, query.endDate),
      page: Math.max(0, Number(query.page ?? 0)),
      limit: Math.max(
        1,
        Math.min(100, Number(query.limit ?? DEFAULT_PAGE_SIZE)),
      ),
    };
  }

  private buildFilterWhere(filters: SalesReportFilters) {
    const parts: Prisma.SalesReportWhereInput[] = [];
    if (filters.reportType) parts.push({ reportType: filters.reportType });
    if (filters.orderCode) parts.push({ orderCode: filters.orderCode });
    if (filters.categoryGroupId) {
      parts.push({
        OR: [
          { categoryGroupId: filters.categoryGroupId },
          {
            categorySelections: {
              some: { categoryGroupId: filters.categoryGroupId },
            },
          },
        ],
      });
    }
    if (filters.reporter) {
      parts.push({
        OR: [
          {
            createdByEmail: { contains: filters.reporter, mode: 'insensitive' },
          },
          {
            createdByName: { contains: filters.reporter, mode: 'insensitive' },
          },
          {
            createdByPersonnelCode: {
              contains: filters.reporter,
              mode: 'insensitive',
            },
          },
        ],
      });
    }
    if (filters.dateRange) {
      parts.push({
        submittedAt: {
          gte: filters.dateRange.start,
          lt: filters.dateRange.end,
        },
      });
    }
    return this.andWhere(...parts);
  }

  private async attachCategoryTypes(erpOrder: SalesReportErpOrder) {
    await Promise.all(
      erpOrder.items.map(async (item) => {
        item.categoryType =
          await this.categories.matchTypeFromListingCategories(
            item.listingCategories,
            [
              item.productTypeCode,
              item.productTypeName,
              item.productGroupCode,
              item.productGroupId,
              item.productGroupName,
              item.name,
            ],
          );
      }),
    );
    const snapshotItems = (erpOrder.sanitizedSnapshot as any)?.items;
    if (Array.isArray(snapshotItems)) {
      snapshotItems.forEach((snapshotItem: any, index: number) => {
        snapshotItem.categoryType = erpOrder.items[index]?.categoryType ?? null;
      });
    }
  }

  private erpCreateData(erpOrder: SalesReportErpOrder) {
    return {
      erpOrderId: erpOrder.erpOrderId,
      erpExternalOrderRef: erpOrder.erpExternalOrderRef,
      erpOrderCreatedAt: erpOrder.erpOrderCreatedAt,
      erpPaymentStatus: erpOrder.erpPaymentStatus,
      erpConfirmationStatus: erpOrder.erpConfirmationStatus,
      erpFulfillmentStatus: erpOrder.erpFulfillmentStatus,
      erpTerminalName: erpOrder.erpTerminalName,
      erpGrandTotal: erpOrder.erpGrandTotal,
      erpPaymentMethods: erpOrder.paymentMethods,
      erpCustomerType: erpOrder.erpCustomerType,
      erpPlatformId: erpOrder.erpPlatformId,
      erpConsultantCustomId: erpOrder.erpConsultantCustomId,
      erpConsultantName: erpOrder.erpConsultantName,
      erpSnapshot: erpOrder.sanitizedSnapshot as Prisma.InputJsonValue,
      erpFetchedAt: erpOrder.fetchedAt,
      erpFetchStatus: 'FOUND',
    };
  }

  private toOrderDto(erpOrder: SalesReportErpOrder) {
    return {
      orderCode: erpOrder.orderCode,
      orderId: erpOrder.erpOrderId,
      externalOrderRef: erpOrder.erpExternalOrderRef,
      orderCreatedAt: erpOrder.erpOrderCreatedAt,
      paymentStatus: erpOrder.erpPaymentStatus,
      confirmationStatus: erpOrder.erpConfirmationStatus,
      fulfillmentStatus: erpOrder.erpFulfillmentStatus,
      terminalName: erpOrder.erpTerminalName,
      grandTotal: erpOrder.erpGrandTotal,
      paymentMethods: erpOrder.paymentMethods,
      customerName: erpOrder.customerName,
      customerType: erpOrder.customerType,
      customerTypeLabel: this.customerTypeLabel(erpOrder.customerType),
      consultantName: erpOrder.erpConsultantName,
    };
  }

  private toReportDto(row: any) {
    const categoryGroups = this.categoryGroupsFor(row);
    const installmentPartnerCodes = this.cleanInstallmentPartnerCodes(
      row.installmentPartnerCodes,
    );
    return {
      id: row.id,
      reportType: row.reportType,
      orderCode: row.orderCode,
      customerName: row.customerName,
      customerPhone: row.customerPhone,
      customerNeed: row.customerNeed,
      categoryGroupId: row.categoryGroupId,
      categoryGroupName: row.categoryGroupName,
      categoryGroupNameVi: row.categoryGroupNameVi,
      categoryGroups,
      consultedSolutionAnswer: row.consultedSolutionAnswer,
      consultedSolutionLabel: this.answerLabel(row.consultedSolutionAnswer),
      consultedSolutionOtherReason: row.consultedSolutionOtherReason,
      experiencedAnswer: row.experiencedAnswer,
      experiencedLabel: this.answerLabel(row.experiencedAnswer),
      experiencedOtherReason: row.experiencedOtherReason,
      zaloAnswer: row.zaloAnswer,
      zaloLabel: this.answerLabel(row.zaloAnswer),
      zaloOtherReason: row.zaloOtherReason,
      appDownloadAnswer: row.appDownloadAnswer,
      appDownloadLabel: this.answerLabel(row.appDownloadAnswer),
      appDownloadOtherReason: row.appDownloadOtherReason,
      notPurchasedReason: row.notPurchasedReason,
      notPurchasedReasonLabel: row.notPurchasedReason
        ? this.notPurchasedLabel(row.notPurchasedReason)
        : null,
      notPurchasedOtherReason: row.notPurchasedOtherReason,
      customerType: row.customerType,
      customerTypeLabel: row.customerType
        ? this.customerTypeLabel(row.customerType)
        : null,
      customerIsStudent: row.customerIsStudent === true,
      promotionCodes: this.cleanPromotionCodes(row.promotionCodes),
      promotionLabels: this.cleanPromotionCodes(row.promotionCodes).map(
        (code) => this.promotionLabel(code),
      ),
      installmentNeed: row.installmentNeed === true,
      installmentApproved: row.installmentApproved,
      installmentLoanAmount: row.installmentLoanAmount,
      installmentNoInstallmentReason: row.installmentNoInstallmentReason,
      installmentNoInstallmentReasonLabel: row.installmentNoInstallmentReason
        ? this.installmentNoInstallmentReasonLabel(
            row.installmentNoInstallmentReason,
          )
        : null,
      installmentStatus: row.installmentStatus,
      installmentStatusLabel: row.installmentStatus
        ? this.installmentLabel(row.installmentStatus)
        : null,
      installmentFailureReason: row.installmentFailureReason,
      installmentPartnerCodes,
      installmentPartnerLabels: installmentPartnerCodes.map((code) =>
        this.installmentPartnerLabel(code),
      ),
      createdByEmail: row.createdByEmail,
      createdByName: row.createdByName,
      createdByPersonnelCode: row.createdByPersonnelCode,
      storeCode: row.storeCode,
      storeName: row.storeName,
      organizationNodeName: row.organizationNodeName,
      erpPaymentStatus: row.erpPaymentStatus,
      erpConfirmationStatus: row.erpConfirmationStatus,
      erpFulfillmentStatus: row.erpFulfillmentStatus,
      erpGrandTotal: row.erpGrandTotal,
      erpPaymentMethods: Array.isArray(row.erpPaymentMethods)
        ? row.erpPaymentMethods
        : [],
      erpCustomerType: row.erpCustomerType,
      erpTerminalName: row.erpTerminalName,
      erpConsultantName: row.erpConsultantName,
      submittedAt: row.submittedAt,
      items: row.items ?? [],
      payments: row.payments ?? [],
    };
  }

  private buildHvtcCsv(rows: any[]) {
    const headers = [
      'Ngày báo cáo',
      'Email người báo cáo',
      'Mã nhân viên tư vấn ERP',
      'Tên khách hàng',
      'Số điện thoại khách hàng',
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
    const lines = [headers.map((header) => this.csvCell(header)).join(',')];
    for (const row of rows) {
      lines.push(
        [
          this.csvCell(this.csvVietnamDateTime(row.submittedAt)),
          this.csvCell(row.createdByEmail),
          this.csvExcelTextCell(
            row.erpConsultantCustomId ?? row.createdByPersonnelCode,
          ),
          this.csvCell(row.customerName),
          this.csvExcelTextCell(row.customerPhone),
          this.csvCell(row.customerNeed),
          this.csvCell(this.answerLabel(row.consultedSolutionAnswer)),
          this.csvCell(row.consultedSolutionOtherReason),
          this.csvCell(this.answerLabel(row.experiencedAnswer)),
          this.csvCell(row.experiencedOtherReason),
          this.csvCell(this.answerLabel(row.zaloAnswer)),
          this.csvCell(row.zaloOtherReason),
          this.csvCell(this.answerLabel(row.appDownloadAnswer)),
          this.csvCell(row.appDownloadOtherReason),
          this.csvCell(this.reportTypeLabel(row.reportType)),
          this.csvCell(
            row.notPurchasedReason
              ? this.notPurchasedLabel(row.notPurchasedReason)
              : '',
          ),
          this.csvCell(row.notPurchasedOtherReason),
          this.csvCell(row.storeCode),
        ].join(','),
      );
    }
    return `\ufeff${lines.join('\n')}`;
  }

  private buildRevenueCsv(rows: any[]) {
    const summary = this.salesRevenueSummary(rows);
    const headers = [
      'Số đơn hàng duy nhất',
      'Tổng doanh thu khách hàng doanh nghiệp',
      'Tổng doanh thu khách hàng cá nhân',
      'Các lý do khách không trả góp',
      'Số lượng laptop',
      'Số lượng PC',
      'Số lượng PC ráp',
      'Số lượng Apple',
      'Số lượng màn hình',
      'Số lượng máy in',
      'Số lượng phụ kiện',
      'Số lượng dịch vụ bảo hiểm',
    ];
    const values = [
      summary.orderCountUnique,
      summary.businessRevenue,
      summary.personalRevenue,
      this.csvCompactList(
        Array.from(summary.noInstallmentReasons.entries()).map(
          ([reason, count]) => `${reason}: ${count}`,
        ),
      ),
      summary.laptopQuantity,
      summary.pcQuantity,
      summary.assembledPcQuantity,
      summary.appleQuantity,
      summary.monitorQuantity,
      summary.printerQuantity,
      summary.accessoriesQuantity,
      summary.extendedInsuranceQuantity,
    ];
    return `\ufeff${[
      headers.map((header) => this.csvCell(header)).join(','),
      values.map((value) => this.csvCell(value)).join(','),
    ].join('\n')}`;
  }

  private salesRevenueSummary(rows: any[]) {
    const uniquePurchased = new Map<string, any>();
    const noInstallmentReasons = new Map<string, number>();
    for (const row of rows) {
      if (row.installmentNoInstallmentReason) {
        const reasonCode = String(row.installmentNoInstallmentReason);
        if (reasonCode !== 'NORMAL_INSTALLMENT') {
          const label = this.installmentNoInstallmentReasonLabel(reasonCode);
          noInstallmentReasons.set(
            label,
            (noInstallmentReasons.get(label) ?? 0) + 1,
          );
        }
      }
      if (row.reportType !== REPORT_TYPE_PURCHASED) continue;
      const key = String(
        row.orderCode ?? row.erpOrderId ?? row.id ?? '',
      ).trim();
      if (key && !uniquePurchased.has(key)) uniquePurchased.set(key, row);
    }

    const summary = {
      orderCountUnique: uniquePurchased.size,
      businessRevenue: 0,
      personalRevenue: 0,
      noInstallmentReasons,
      laptopQuantity: 0,
      pcQuantity: 0,
      assembledPcQuantity: 0,
      appleQuantity: 0,
      monitorQuantity: 0,
      printerQuantity: 0,
      accessoriesQuantity: 0,
      extendedInsuranceQuantity: 0,
    };

    for (const row of uniquePurchased.values()) {
      const revenue = this.orderRevenue(row);
      if (row.customerType === 'BUSINESS') {
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

    return summary;
  }

  private orderRevenue(row: any) {
    const grandTotal = this.numberValue(row.erpGrandTotal);
    if (grandTotal !== null) return grandTotal;
    return (Array.isArray(row.items) ? row.items : []).reduce(
      (total: number, item: any) => {
        const rowTotal = this.numberValue(item?.rowTotal);
        if (rowTotal !== null) return total + rowTotal;
        const price = this.numberValue(item?.finalSellPrice);
        return price === null
          ? total
          : total + price * this.salesItemQuantity(item);
      },
      0,
    );
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

  private salesItemQuantity(item: any) {
    const quantity = this.numberValue(item?.quantity);
    return quantity !== null && quantity > 0 ? quantity : 1;
  }

  private normalizeSalesCategoryType(value: unknown) {
    return String(value || '')
      .trim()
      .replace(/\s+/g, '')
      .toLowerCase();
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

  private numberValue(value: unknown) {
    if (value === undefined || value === null || value === '') return null;
    const number =
      typeof value === 'string'
        ? Number(value.replace(/,/g, ''))
        : Number(value);
    return Number.isFinite(number) ? Math.trunc(number) : null;
  }

  private salesReportExportNote({
    row,
    categoryGroups,
    promotionCodes,
    partnerCodes,
    paymentMethods,
    paymentSummary,
  }: {
    row: any;
    categoryGroups: Array<{
      id?: string | null;
      catGroupName?: string | null;
      catGroupNameVi?: string | null;
    }>;
    promotionCodes: string[];
    partnerCodes: string[];
    paymentMethods: unknown[];
    paymentSummary: string;
  }) {
    const customerType = row.customerType
      ? `${this.customerTypeLabel(row.customerType)}${
          row.customerIsStudent === true ? ' - Học sinh/Sinh viên' : ''
        }`
      : null;
    const installmentSummary = this.csvCompactList([
      row.installmentNeed === true ? 'Có nhu cầu trả góp' : 'Không trả góp',
      row.installmentApproved === true
        ? 'Hồ sơ duyệt'
        : row.installmentApproved === false
          ? 'Hồ sơ chưa duyệt'
          : null,
      row.installmentLoanAmount ? `Vay ${row.installmentLoanAmount}` : null,
      row.installmentStatus
        ? this.installmentLabel(row.installmentStatus)
        : null,
      ...partnerCodes.map((code) => this.installmentPartnerLabel(code)),
      row.installmentNoInstallmentReason
        ? this.installmentNoInstallmentReasonLabel(
            row.installmentNoInstallmentReason,
          )
        : null,
      row.installmentFailureReason,
    ]);
    return this.csvCompactList([
      this.exportNotePart('Nhu cầu', row.customerNeed),
      this.exportNotePart(
        'Ngành báo cáo',
        this.csvCompactList(
          categoryGroups
            .map((category) => category.catGroupNameVi || category.catGroupName)
            .filter(Boolean),
        ),
      ),
      this.exportNotePart('Loại khách', customerType),
      this.exportNotePart(
        'CTKM',
        this.csvCompactList(
          promotionCodes.map((code) => this.promotionLabel(code)),
        ),
      ),
      this.exportNotePart(
        'Tư vấn',
        this.exportAnswer(
          row.consultedSolutionAnswer,
          row.consultedSolutionOtherReason,
        ),
      ),
      this.exportNotePart(
        'Trải nghiệm',
        this.exportAnswer(row.experiencedAnswer, row.experiencedOtherReason),
      ),
      this.exportNotePart(
        'Zalo',
        this.exportAnswer(row.zaloAnswer, row.zaloOtherReason),
      ),
      this.exportNotePart(
        'App',
        this.exportAnswer(row.appDownloadAnswer, row.appDownloadOtherReason),
      ),
      this.exportNotePart(
        'Chưa mua',
        row.notPurchasedReason
          ? this.exportAnswer(
              this.notPurchasedLabel(row.notPurchasedReason),
              row.notPurchasedOtherReason,
              false,
            )
          : null,
      ),
      this.exportNotePart('Trả góp', installmentSummary),
      this.exportNotePart(
        'Thanh toán ERP',
        this.csvCompactList(paymentMethods),
      ),
      this.exportNotePart('Chi tiết thanh toán', paymentSummary),
      this.exportNotePart(
        'Trạng thái ERP',
        this.csvCompactList([
          row.erpPaymentStatus,
          row.erpConfirmationStatus,
          row.erpFulfillmentStatus,
        ]),
      ),
    ]);
  }

  private exportNotePart(label: string, value: unknown) {
    const text = this.csvText(value).trim();
    return text ? `${label}: ${text}` : '';
  }

  private exportAnswer(
    codeOrLabel: unknown,
    otherReason: unknown,
    resolveAnswerLabel = true,
  ) {
    const code = this.csvText(codeOrLabel).trim();
    if (!code) return '';
    const label = resolveAnswerLabel ? this.answerLabel(code) : code;
    const other = this.csvText(otherReason).trim();
    return other ? `${label}: ${other}` : label;
  }

  private csvCompactList(values: unknown[]) {
    return Array.from(
      new Set(
        values
          .map((value) =>
            this.csvText(value)
              .replace(/[\r\n]+/g, ' ')
              .trim(),
          )
          .filter(Boolean),
      ),
    ).join('; ');
  }

  private requireOtherReason(
    code: string,
    reason: string | undefined,
    message: string,
  ) {
    if (code === 'OTHER' && !this.optionalText(reason, 500)) {
      throw new BadRequestException(message);
    }
  }

  private requireAnswer(
    code: unknown,
    allowed: readonly string[],
    message: string,
  ) {
    const normalized = String(code || '')
      .trim()
      .toUpperCase();
    if (!allowed.includes(normalized)) {
      throw new BadRequestException(message);
    }
  }

  private parseStoreCodes(value: unknown) {
    return String(value || '')
      .split(',')
      .map((item) => item.trim().toUpperCase())
      .filter(Boolean)
      .slice(0, 100);
  }

  private parseDateRange(startDate?: string, endDate?: string) {
    const start = this.parseDateOnly(startDate);
    const end = this.parseDateOnly(endDate);
    if (!start && !end) return null;
    const rangeStart = start ?? new Date('2000-01-01T00:00:00.000Z');
    const rangeEnd = end ?? new Date();
    rangeEnd.setDate(rangeEnd.getDate() + 1);
    return { start: rangeStart, end: rangeEnd };
  }

  private parseDateOnly(value?: string) {
    const text = String(value || '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null;
    const date = new Date(`${text}T00:00:00.000+07:00`);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  private personnelCodeFor(user: any, store: any) {
    const jobRoleCode = String(user?.jobRoleCode || '')
      .trim()
      .toUpperCase();
    if (!jobRoleCode) return null;
    const storeCode = String(store?.storeId || 'STORE')
      .trim()
      .toUpperCase();
    const area =
      store?.area?.abbreviation ||
      store?.area?.code ||
      user?.area?.abbreviation ||
      user?.areaCode ||
      'NATIONAL';
    const region =
      store?.area?.region?.abbreviation ||
      store?.area?.region?.code ||
      user?.region?.abbreviation ||
      user?.regionCode ||
      'NATIONAL';
    return [jobRoleCode, storeCode, area, region]
      .map((part) =>
        String(part || 'NATIONAL')
          .trim()
          .toUpperCase()
          .replace(/[^A-Z0-9_]/g, '_'),
      )
      .join('_');
  }

  private normalizeOrderCode(value: unknown) {
    return String(value || '')
      .trim()
      .toUpperCase()
      .replace(/\s+/g, '');
  }

  private normalizeEnum<T extends readonly string[]>(
    value: unknown,
    allowed: T,
  ): T[number] {
    const normalized = String(value || '')
      .trim()
      .toUpperCase();
    if (!allowed.includes(normalized as T[number])) {
      throw new BadRequestException('Dữ liệu báo cáo không hợp lệ.');
    }
    return normalized as T[number];
  }

  private normalizeExportType(value: unknown) {
    const normalized = String(value || EXPORT_TYPE_HVTC)
      .trim()
      .toUpperCase();
    if (!SALES_REPORT_EXPORT_TYPES.includes(normalized as any)) {
      throw new BadRequestException('Loại file xuất báo cáo không hợp lệ.');
    }
    return normalized;
  }

  private normalizeOptionalEnum<T extends readonly string[]>(
    value: unknown,
    allowed: T,
    message: string,
  ): T[number] | null {
    const normalized = String(value || '')
      .trim()
      .toUpperCase();
    if (!normalized) return null;
    if (!allowed.includes(normalized as T[number])) {
      throw new BadRequestException(message);
    }
    return normalized as T[number];
  }

  private optionalInt(value: unknown, max: number, message: string) {
    if (value === undefined || value === null || value === '') return null;
    const number = Number(value);
    if (!Number.isFinite(number) || number < 0 || number > max) {
      throw new BadRequestException(message);
    }
    return Math.trunc(number);
  }

  private optionalText(value: unknown, maxLength: number) {
    if (value === undefined || value === null) return null;
    const text = String(value).trim();
    return text ? text.slice(0, maxLength) : null;
  }

  private storeCodeWhere(storeCodes: string[]) {
    return storeCodes.length === 1 ? storeCodes[0] : { in: storeCodes };
  }

  private andWhere(
    ...parts: Array<Prisma.SalesReportWhereInput | null | undefined>
  ) {
    const filtered = parts.filter(
      (part): part is Prisma.SalesReportWhereInput =>
        Boolean(part && Object.keys(part).length > 0),
    );
    if (filtered.length === 0) return {};
    if (filtered.length === 1) return filtered[0];
    return { AND: filtered };
  }

  private answerLabel(code: string) {
    return ANSWER_LABELS[code] ?? code;
  }

  private reportTypeLabel(code: string) {
    return code === REPORT_TYPE_PURCHASED ? 'Mua hàng' : 'Chưa mua hàng';
  }

  private notPurchasedLabel(code: string) {
    return NOT_PURCHASED_LABELS[code] ?? code;
  }

  private installmentLabel(code: string) {
    return INSTALLMENT_LABELS[code] ?? code;
  }

  private installmentPartnerLabel(code: string) {
    return INSTALLMENT_PARTNER_LABELS[code] ?? code;
  }

  private customerTypeLabel(code: string) {
    return CUSTOMER_TYPE_LABELS[code] ?? code;
  }

  private promotionLabel(code: string) {
    return PROMOTION_LABELS[code] ?? code;
  }

  private installmentNoInstallmentReasonLabel(code: string) {
    return INSTALLMENT_NO_INSTALLMENT_REASON_LABELS[code] ?? code;
  }

  private cleanInstallmentPartnerCodes(value: unknown) {
    const raw = Array.isArray(value) ? value : [];
    return raw
      .map((item) =>
        String(item || '')
          .trim()
          .toUpperCase(),
      )
      .filter((code) => INSTALLMENT_PARTNER_CODES.includes(code as any));
  }

  private cleanPromotionCodes(value: unknown) {
    const raw = Array.isArray(value) ? value : [];
    return raw
      .map((item) =>
        String(item || '')
          .trim()
          .toUpperCase(),
      )
      .filter((code) => PROMOTION_CODES.includes(code as any));
  }

  private categoryGroupsFor(row: any) {
    const selections = Array.isArray(row.categorySelections)
      ? row.categorySelections
      : [];
    if (selections.length > 0) {
      return selections.map((selection: any) => ({
        id: selection.categoryGroupId,
        catGroupName: selection.categoryGroupName,
        catGroupNameVi: selection.categoryGroupNameVi,
      }));
    }
    return [
      {
        id: row.categoryGroupId,
        catGroupName: row.categoryGroupName,
        catGroupNameVi: row.categoryGroupNameVi,
      },
    ].filter((category) => Boolean(category.id));
  }

  private csvCell(value: unknown) {
    return this.csvText(value)
      .replace(/"/g, '')
      .replace(/,/g, ';')
      .replace(/[\r\n]+/g, ' ')
      .trim();
  }

  private csvExcelTextCell(value: unknown) {
    const text = this.csvText(value).replace(/[\r\n]+/g, ' ');
    if (!text) return '';
    return this.csvCell(text);
  }

  private csvReportDate(value: unknown) {
    const date = value instanceof Date ? value : new Date(String(value || ''));
    if (Number.isNaN(date.getTime())) return '';
    return new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Ho_Chi_Minh',
      month: 'numeric',
      day: 'numeric',
      year: 'numeric',
    }).format(date);
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

  private normalizeComparable(value: unknown) {
    return String(value || '')
      .trim()
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();
  }

  private csvText(value: unknown) {
    if (value === undefined || value === null) return '';
    return String(value);
  }

  private safeUserLabel(user: any) {
    return user?.email || user?.id || 'unknown';
  }
}
