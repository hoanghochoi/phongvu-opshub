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
  ExportSalesReportsDto,
  EXPERIENCE_REASON_CODES,
  INSTALLMENT_PARTNER_CODES,
  INSTALLMENT_STATUSES,
  ListSalesReportsDto,
  NOT_PURCHASED_REASON_CODES,
  SALES_REPORT_TYPES,
  YES_NO_REASON_CODES,
  ZALO_REASON_CODES,
} from './sales-reports.dto';

const REPORT_TYPE_PURCHASED = 'PURCHASED';
const REPORT_TYPE_NOT_PURCHASED = 'NOT_PURCHASED';
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

const INSTALLMENT_PARTNER_LABELS: Record<string, string> = {
  VNPAY_POS: 'VNPAY - POS',
  PAYOO_POS: 'PAYOO - POS',
  HOMECREDIT_CTTC: 'HomeCredit - CTTC',
  SHINHAN_CTTC: 'Shinhan - CTTC',
  HDSAISON_CTTC: 'HDSaison - CTTC',
  AEON_FINANCE_CTTC: 'AEON Finance - CTTC',
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
    const matchedCategories = await this.categories.matchCategoriesFromErp(
      erpOrder.categoryCandidates,
    );
    return {
      orderCode,
      customerNeed: erpOrder.customerNeed,
      categoryGroup: matchedCategories[0] ?? null,
      categoryGroups: matchedCategories,
      order: this.toOrderDto(erpOrder),
      items: erpOrder.items,
      payments: erpOrder.payments,
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
    const installment = this.normalizeInstallmentSelection(
      reportType,
      body,
    );
    const categories = await this.categories.requireCategories(categoryIds);
    const primaryCategory = categories[0]!;
    const context = await this.resolveUserSnapshot(user);
    let erpOrder: SalesReportErpOrder | null = null;
    if (reportType === REPORT_TYPE_PURCHASED) {
      await this.assertOrderNotReported(orderCode);
      erpOrder = await this.erp.lookupOrder(orderCode ?? '', context.storeCode);
    }

    this.logger.log(
      `Sales report create started: user=${this.safeUserLabel(user)} type=${reportType} primaryCategory=${primaryCategory.id} categoryCount=${categories.length} hasOrder=${Boolean(orderCode)} hasInstallment=${Boolean(installment.status)}`,
    );
    try {
      const report = await this.prisma.salesReport.create({
        data: {
          reportType,
          orderCode,
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
          installmentStatus: installment.status,
          installmentFailureReason:
            installment.status === INSTALLMENT_FAILED
              ? this.optionalText(body.installmentFailureReason, 500)
              : null,
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
                  productGroupName: item.productGroupName,
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
      `Sales reports export completed: user=${this.safeUserLabel(user)} count=${rows.length}`,
    );
    return this.buildCsv(rows);
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

  private normalizeInstallmentSelection(
    reportType: string,
    body: CreateSalesReportDto,
  ) {
    const rawStatus = this.optionalText(body.installmentStatus, 20);
    const failureReason = this.optionalText(
      body.installmentFailureReason,
      500,
    );
    const partnerCodes = this.normalizeInstallmentPartnerCodes(
      body.installmentPartnerCodes,
    );
    if (!rawStatus) {
      if (failureReason || partnerCodes.length > 0) {
        throw new BadRequestException(
          'Vui lòng tick Trả góp trước khi nhập thông tin trả góp.',
        );
      }
      return { status: null, partnerCodes: [] };
    }
    const status = this.normalizeEnum(rawStatus, INSTALLMENT_STATUSES);
    if (reportType === REPORT_TYPE_PURCHASED && status !== INSTALLMENT_SUCCESS) {
      throw new BadRequestException(
        'Báo cáo mua hàng chỉ ghi nhận trả góp thành công.',
      );
    }
    if (
      reportType === REPORT_TYPE_NOT_PURCHASED &&
      status !== INSTALLMENT_FAILED
    ) {
      throw new BadRequestException(
        'Báo cáo chưa mua hàng chỉ ghi nhận trả góp thất bại.',
      );
    }
    if (status === INSTALLMENT_FAILED && !failureReason) {
      throw new BadRequestException('Vui lòng nhập lý do trả góp thất bại.');
    }
    if (partnerCodes.length === 0) {
      throw new BadRequestException('Vui lòng chọn đối tác trả góp.');
    }
    return { status, partnerCodes };
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
      erpTerminalName: row.erpTerminalName,
      erpConsultantName: row.erpConsultantName,
      submittedAt: row.submittedAt,
      items: row.items ?? [],
      payments: row.payments ?? [],
    };
  }

  private buildCsv(rows: any[]) {
    const headers = [
      'Thời gian gửi',
      'Loại báo cáo',
      'Mã đơn hàng',
      'Showroom',
      'Người gửi',
      'MSNV hệ thống',
      'Ngành hàng',
      'SĐT khách',
      'Sản phẩm khách tìm',
      'Tư vấn 3 giải pháp',
      'Lý do khác tư vấn',
      'KH trải nghiệm',
      'Lý do khác trải nghiệm',
      'KH quét Zalo',
      'Lý do khác Zalo',
      'KH tải App PV',
      'Lý do khác App',
      'Lý do chưa mua',
      'Lý do khác chưa mua',
      'Trả góp',
      'Đối tác trả góp',
      'Lý do trả góp thất bại',
      'Tổng tiền ERP',
      'Thanh toán ERP',
      'Xác nhận ERP',
      'Giao hàng ERP',
      'Sản phẩm ERP',
      'Thanh toán',
    ];
    const lines = [headers.map((header) => this.csvCell(header)).join(',')];
    for (const row of rows) {
      const categoryGroups = this.categoryGroupsFor(row);
      const partnerCodes = this.cleanInstallmentPartnerCodes(
        row.installmentPartnerCodes,
      );
      lines.push(
        [
          this.csvCell(this.csvVietnamDate(row.submittedAt)),
          this.csvCell(
            row.reportType === REPORT_TYPE_PURCHASED
              ? 'Mua hàng'
              : 'Chưa mua hàng',
          ),
          this.csvExcelTextCell(row.orderCode),
          this.csvCell(row.storeCode),
          this.csvCell(row.createdByName || row.createdByEmail),
          this.csvExcelTextCell(row.createdByPersonnelCode),
          this.csvCell(
            categoryGroups
              .map(
                (category: { catGroupNameVi?: string | null }) =>
                  category.catGroupNameVi,
              )
              .filter(Boolean)
              .join('\n'),
          ),
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
          this.csvCell(
            row.notPurchasedReason
              ? this.notPurchasedLabel(row.notPurchasedReason)
              : null,
          ),
          this.csvCell(row.notPurchasedOtherReason),
          this.csvCell(
            row.installmentStatus
              ? this.installmentLabel(row.installmentStatus)
              : null,
          ),
          this.csvCell(
            partnerCodes
              .map((code) => this.installmentPartnerLabel(code))
              .join('\n'),
          ),
          this.csvCell(row.installmentFailureReason),
          this.csvCell(row.erpGrandTotal),
          this.csvCell(row.erpPaymentStatus),
          this.csvCell(row.erpConfirmationStatus),
          this.csvCell(row.erpFulfillmentStatus),
          this.csvCell(
            (row.items || [])
              .map((item: any) =>
                [item.sellerSku, item.name, item.quantity]
                  .filter(Boolean)
                  .join(' - '),
              )
              .join('\n'),
          ),
          this.csvCell(
            (row.payments || [])
              .map((payment: any) =>
                [payment.paymentMethod, payment.amount]
                  .filter(Boolean)
                  .join(' '),
              )
              .join('\n'),
          ),
        ].join(','),
      );
    }
    return `\ufeff${lines.join('\n')}`;
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

  private notPurchasedLabel(code: string) {
    return NOT_PURCHASED_LABELS[code] ?? code;
  }

  private installmentLabel(code: string) {
    return INSTALLMENT_LABELS[code] ?? code;
  }

  private installmentPartnerLabel(code: string) {
    return INSTALLMENT_PARTNER_LABELS[code] ?? code;
  }

  private cleanInstallmentPartnerCodes(value: unknown) {
    const raw = Array.isArray(value) ? value : [];
    return raw
      .map((item) => String(item || '').trim().toUpperCase())
      .filter((code) => INSTALLMENT_PARTNER_CODES.includes(code as any));
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
    const text = this.csvText(value);
    if (!/[",\r\n]/.test(text)) return text;
    return `"${text.replace(/"/g, '""')}"`;
  }

  private csvExcelTextCell(value: unknown) {
    const text = this.csvText(value).replace(/[\r\n]+/g, ' ');
    if (!text) return '';
    return this.csvCell(`="${text.replace(/"/g, '""')}"`);
  }

  private csvVietnamDate(value: unknown) {
    const date = value instanceof Date ? value : new Date(String(value || ''));
    if (Number.isNaN(date.getTime())) return '';
    return new Intl.DateTimeFormat('vi-VN', {
      timeZone: 'Asia/Ho_Chi_Minh',
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    }).format(date);
  }

  private csvText(value: unknown) {
    if (value === undefined || value === null) return '';
    return String(value);
  }

  private safeUserLabel(user: any) {
    return user?.email || user?.id || 'unknown';
  }
}
