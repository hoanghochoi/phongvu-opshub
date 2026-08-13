import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { isSuperAdminRole } from '../common/system-role';
import { FEATURE_KEYS } from '../feature/feature.constants';
import type { FeatureService } from '../feature/feature.service';
import type { PrismaService } from '../prisma/prisma.service';
import {
  ListSalesReportOrdersDto,
  ListSalesReportsDto,
  SALES_REPORT_TYPES,
} from './sales-reports.dto';

const DEFAULT_PAGE_SIZE = 20;
const DEFAULT_ORDER_COCKPIT_LIMIT = 20;
const MANAGED_SALES_REPORT_JOB_ROLE_CODES = new Set([
  'STORE_MANAGER',
  'AREA_MANAGER',
  'REGION_MANAGER',
]);

export type SalesReportFilters = {
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

export type SalesReportOrderCockpitFilters = {
  startDate: string;
  endDate: string;
  dateRange: { start: Date; end: Date };
  storeCode: string | null;
  userEmail: string | null;
  limit: number;
  reportedPage: number;
  unreportedPage: number;
};

export type SalesReportUserSnapshotContext = {
  createdByEmail?: unknown;
  createdByPersonnelCode?: unknown;
};

export type SalesReportsScopeQueryCallbacks = {
  normalizeEmail(value: unknown): string | null;
  normalizeStoreCode(value: unknown): string | null;
  optionalText(value: unknown, maxLength: number): string | null;
  safeUserLabel(user: any): string;
  todayVietnamDate(): string;
  formatVietnamDate(value: Date): string;
  warn(message: string): void;
};

/**
 * Owns Sales Reports authorization, store scope and list/query composition.
 * SalesReportsService remains the stable facade; ERP, import, follow-up,
 * BigQuery and export/mutation orchestration stay in their existing owners.
 */
export class SalesReportsScopeQueryRuntime {
  constructor(
    private readonly prisma: PrismaService,
    private readonly featureService: FeatureService | undefined,
    private readonly callbacks: SalesReportsScopeQueryCallbacks,
  ) {}

  async canUseSalesReport(user: any) {
    if (isSuperAdminRole(user?.role)) return true;
    if (this.featureService?.canAccessFeature) {
      try {
        const canAccess = await this.featureService.canAccessFeature(
          user,
          FEATURE_KEYS.SALES_REPORT,
        );
        if (canAccess) return true;
      } catch (error) {
        this.callbacks.warn(
          `Sales report feature check failed: user=${this.callbacks.safeUserLabel(user)} error=${String(error)}`,
        );
      }
    }
    return (
      user?.featureAccess?.[FEATURE_KEYS.SALES_REPORT] === true ||
      user?.resolvedFeatureAccess?.[FEATURE_KEYS.SALES_REPORT] === true
    );
  }

  async canViewAdminSalesReports(user: any) {
    if (isSuperAdminRole(user?.role)) return true;
    const contextFeatureAccess = user?.__authContext?.featureAccess;
    const hasContextFeatureDecision =
      contextFeatureAccess &&
      typeof contextFeatureAccess === 'object' &&
      Object.prototype.hasOwnProperty.call(
        contextFeatureAccess,
        FEATURE_KEYS.ADMIN_SALES_REPORTS,
      );
    if (hasContextFeatureDecision) {
      if (contextFeatureAccess[FEATURE_KEYS.ADMIN_SALES_REPORTS] === true) {
        return true;
      }
    } else if (this.featureService?.canAccessFeature) {
      try {
        const canAccess = await this.featureService.canAccessFeature(
          user,
          FEATURE_KEYS.ADMIN_SALES_REPORTS,
        );
        if (canAccess) return true;
      } catch (error) {
        this.callbacks.warn(
          `Sales report admin feature check failed: user=${this.callbacks.safeUserLabel(user)} error=${String(error)}`,
        );
      }
    }
    if (
      !hasContextFeatureDecision &&
      (user?.featureAccess?.[FEATURE_KEYS.ADMIN_SALES_REPORTS] === true ||
        user?.resolvedFeatureAccess?.[FEATURE_KEYS.ADMIN_SALES_REPORTS] ===
          true)
    ) {
      return true;
    }
    return this.hasManagedSalesReportScope(user);
  }

  private async hasManagedSalesReportScope(user: any) {
    const authContext = user?.__authContext;
    if (
      authContext &&
      typeof authContext === 'object' &&
      Object.prototype.hasOwnProperty.call(authContext, 'scopeSnapshot')
    ) {
      return this.hasManagedSalesReportJobRole(authContext.scopeSnapshot);
    }
    if (this.hasManagedSalesReportJobRole(user)) return true;
    if (!user?.id || !(this.prisma as any).user?.findUnique) return false;
    try {
      const savedUser = await this.prisma.user.findUnique({
        where: { id: user.id },
        select: {
          jobRoleCode: true,
          jobRole: { select: { code: true } },
        },
      });
      return this.hasManagedSalesReportJobRole(savedUser);
    } catch (error) {
      this.callbacks.warn(
        `Sales report managed scope check failed: user=${this.callbacks.safeUserLabel(user)} error=${String(error)}`,
      );
      return false;
    }
  }

  private hasManagedSalesReportJobRole(user: any) {
    const candidates = [
      user?.jobRoleCode,
      user?.jobRole?.code,
      user?.jobRole?.businessCode,
    ];
    return candidates
      .map((value) =>
        String(value || '')
          .trim()
          .toUpperCase(),
      )
      .some(
        (code) =>
          MANAGED_SALES_REPORT_JOB_ROLE_CODES.has(code) ||
          Array.from(MANAGED_SALES_REPORT_JOB_ROLE_CODES).some((roleCode) =>
            code.endsWith(`_${roleCode}`),
          ),
      );
  }

  resolveUserReportScopeWhere(user: any): Prisma.SalesReportWhereInput {
    const email = this.callbacks.normalizeEmail(user?.email);
    const userId = this.callbacks.optionalText(user?.id, 80);
    const parts: Prisma.SalesReportWhereInput[] = [];
    if (userId) parts.push({ createdByUserId: userId });
    if (email) {
      parts.push({ createdByEmail: { equals: email, mode: 'insensitive' } });
    }
    if (parts.length === 0) {
      throw new ForbiddenException('Tài khoản chưa có thông tin người dùng.');
    }
    return { OR: parts };
  }

  async resolveAdminScopeWhere(
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

  async resolveAdminOrderCacheScopeWhere(
    user: any,
  ): Promise<Prisma.SalesReportErpOrderCacheWhereInput> {
    if (isSuperAdminRole(user?.role)) return {};
    const allowedStores = await this.resolveUserStores(user);
    const allowedStoreCodes = allowedStores.map((store) => store.storeId);
    if (allowedStoreCodes.length === 0) {
      throw new ForbiddenException('Tài khoản chưa được gán showroom.');
    }
    return { storeCode: this.storeCodeWhere(allowedStoreCodes) as any };
  }

  resolveUserOrderCacheScopeWhere(
    user: any,
    context: SalesReportUserSnapshotContext,
  ): Prisma.SalesReportErpOrderCacheWhereInput {
    const email = this.callbacks.normalizeEmail(
      context.createdByEmail ?? user?.email,
    );
    const personnelCode = this.callbacks.optionalText(
      context.createdByPersonnelCode,
      120,
    );
    const parts: Prisma.SalesReportErpOrderCacheWhereInput[] = [];
    if (email) {
      parts.push(
        { consultantEmail: { equals: email, mode: 'insensitive' } },
        { sellerEmail: { equals: email, mode: 'insensitive' } },
        { sourceUserEmail: { equals: email, mode: 'insensitive' } },
      );
    }
    if (personnelCode) {
      parts.push(
        { consultantCustomId: { equals: personnelCode, mode: 'insensitive' } },
        { sellerId: { equals: personnelCode, mode: 'insensitive' } },
      );
    }
    if (parts.length === 0) {
      throw new ForbiddenException('Tài khoản chưa có thông tin người dùng.');
    }
    return { OR: parts };
  }

  async resolveUserStores(user: any) {
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
      const savedUser =
        user?.__authContext?.scopeSnapshot ??
        (await this.prisma.user.findUnique({
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
        }));
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

  normalizeFilters(query: ListSalesReportsDto): SalesReportFilters {
    return {
      reportType:
        query.reportType && query.reportType !== 'ALL'
          ? this.normalizeEnum(query.reportType, SALES_REPORT_TYPES)
          : null,
      orderCode: this.callbacks.optionalText(query.orderCode, 80),
      categoryGroupId: this.callbacks.optionalText(query.categoryGroupId, 40),
      reporter: this.callbacks.optionalText(query.reporter, 120),
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

  private normalizeEnum<T extends readonly string[]>(
    value: unknown,
    allowed: T,
  ) {
    const normalized = String(value || '')
      .trim()
      .toUpperCase();
    if (!allowed.includes(normalized as T[number])) {
      throw new BadRequestException('Dữ liệu báo cáo không hợp lệ.');
    }
    return normalized as T[number];
  }

  buildFilterWhere(filters: SalesReportFilters) {
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

  normalizeOrderCockpitFilters(
    query: ListSalesReportOrdersDto,
  ): SalesReportOrderCockpitFilters {
    const legacyDate = this.parseDateParam(query.date);
    const requestedStartDate =
      this.parseDateParam(query.startDate) ?? legacyDate;
    const requestedEndDate = this.parseDateParam(query.endDate) ?? legacyDate;
    let startDate: string;
    let endDate: string;
    if (!requestedStartDate && !requestedEndDate) {
      endDate = this.callbacks.todayVietnamDate();
      const implicitStart = new Date(`${endDate}T00:00:00.000+07:00`);
      implicitStart.setDate(implicitStart.getDate() - 29);
      startDate = this.callbacks.formatVietnamDate(implicitStart);
    } else {
      const fallbackDate = requestedStartDate ?? requestedEndDate!;
      startDate = requestedStartDate ?? fallbackDate;
      endDate = requestedEndDate ?? fallbackDate;
    }
    if (startDate > endDate) {
      throw new BadRequestException(
        'Ngày kết thúc phải bằng hoặc sau ngày bắt đầu.',
      );
    }
    const start = new Date(`${startDate}T00:00:00.000+07:00`);
    const end = new Date(`${endDate}T00:00:00.000+07:00`);
    end.setDate(end.getDate() + 1);
    const normalizeNumber = (value: unknown, fallback: number) => {
      const normalized = Math.trunc(Number(value ?? fallback));
      return Number.isFinite(normalized) ? normalized : fallback;
    };
    const limit = Math.max(
      1,
      Math.min(100, normalizeNumber(query.limit, DEFAULT_ORDER_COCKPIT_LIMIT)),
    );
    return {
      startDate,
      endDate,
      dateRange: { start, end },
      storeCode: this.callbacks.normalizeStoreCode(query.storeCode),
      userEmail: this.callbacks.normalizeEmail(query.userEmail),
      limit,
      reportedPage: Math.max(0, normalizeNumber(query.reportedPage, 0)),
      unreportedPage: Math.max(0, normalizeNumber(query.unreportedPage, 0)),
    };
  }

  orderCockpitReportFilterWhere(
    filters: SalesReportOrderCockpitFilters,
  ): Prisma.SalesReportWhereInput {
    return this.andWhere(
      filters.storeCode ? { storeCode: filters.storeCode } : {},
      filters.userEmail
        ? { createdByEmail: { equals: filters.userEmail, mode: 'insensitive' } }
        : {},
    );
  }

  orderCockpitCacheFilterWhere(
    filters: SalesReportOrderCockpitFilters,
  ): Prisma.SalesReportErpOrderCacheWhereInput {
    const userWhere = filters.userEmail
      ? {
          OR: [
            {
              consultantEmail: {
                equals: filters.userEmail,
                mode: Prisma.QueryMode.insensitive,
              },
            },
            {
              sellerEmail: {
                equals: filters.userEmail,
                mode: Prisma.QueryMode.insensitive,
              },
            },
            {
              sourceUserEmail: {
                equals: filters.userEmail,
                mode: Prisma.QueryMode.insensitive,
              },
            },
          ],
        }
      : {};
    return this.andOrderCacheWhere(
      filters.storeCode ? { storeCode: filters.storeCode } : {},
      userWhere,
    );
  }

  parseStoreCodes(value: unknown) {
    return String(value || '')
      .split(',')
      .map((item) => item.trim().toUpperCase())
      .filter(Boolean)
      .slice(0, 100);
  }

  parseDateRange(startDate?: string, endDate?: string) {
    const start = this.parseDateOnly(startDate);
    const end = this.parseDateOnly(endDate);
    if (!start && !end) return null;
    const rangeStart = start ?? new Date('2000-01-01T00:00:00.000Z');
    const rangeEnd = end ?? new Date();
    rangeEnd.setDate(rangeEnd.getDate() + 1);
    return { start: rangeStart, end: rangeEnd };
  }

  private parseDateParam(value?: string) {
    const text = String(value || '').trim();
    return /^\d{4}-\d{2}-\d{2}$/.test(text) ? text : null;
  }

  private parseDateOnly(value?: string) {
    const text = String(value || '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null;
    const date = new Date(`${text}T00:00:00.000+07:00`);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  reportedOrderDateWhere(dateRange: { start: Date; end: Date }) {
    return {
      OR: [
        { erpOrderCreatedAt: { gte: dateRange.start, lt: dateRange.end } },
        {
          AND: [
            { erpOrderCreatedAt: null },
            { submittedAt: { gte: dateRange.start, lt: dateRange.end } },
          ],
        },
      ],
    };
  }

  orderCacheDateWhere(dateRange: { start: Date; end: Date }) {
    return { orderCreatedAt: { gte: dateRange.start, lt: dateRange.end } };
  }

  visibleSalesReportWhere(): Prisma.SalesReportWhereInput {
    return { erpExcludedAt: null };
  }

  visibleOrderCacheWhere(): Prisma.SalesReportErpOrderCacheWhereInput {
    return { excludedAt: null };
  }

  storeCodeWhere(storeCodes: string[]) {
    return storeCodes.length === 1 ? storeCodes[0] : { in: storeCodes };
  }

  andWhere(...parts: Array<Prisma.SalesReportWhereInput | null | undefined>) {
    const filtered = parts.filter(
      (part): part is Prisma.SalesReportWhereInput =>
        Boolean(part && Object.keys(part).length > 0),
    );
    if (filtered.length === 0) return {};
    if (filtered.length === 1) return filtered[0];
    return { AND: filtered };
  }

  andOrderCacheWhere(
    ...parts: Array<
      Prisma.SalesReportErpOrderCacheWhereInput | null | undefined
    >
  ) {
    const filtered = parts.filter(
      (part): part is Prisma.SalesReportErpOrderCacheWhereInput =>
        Boolean(part && Object.keys(part).length > 0),
    );
    if (filtered.length === 0) return {};
    if (filtered.length === 1) return filtered[0];
    return { AND: filtered };
  }
}
