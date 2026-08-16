import { Prisma } from '@prisma/client';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { PrismaService } from '../prisma/prisma.service';
import { SalesReportSummaryScopeDescriptor } from '../sales-reports/sales-reports.service';
import {
  CanonicalRevenueLookup,
  canonicalRevenueForOrder,
} from '../sales-reports/sales-report-revenue';

const REPORT_TYPE_PURCHASED = 'PURCHASED';

type DateRange = {
  start: Date;
  end: Date;
};

export type SalesProgressPeriod = {
  actual: number;
  target: number | null;
  percentage: number | null;
};

export type SalesProgressResponse = {
  status: 'AVAILABLE' | 'MISSING' | 'PARTIAL' | 'NOT_APPLICABLE';
  scope: 'PERSONAL_SA' | 'MANAGED' | 'ALL' | null;
  missingStoreCodes: string[];
  range: SalesProgressPeriod;
  day: SalesProgressPeriod;
  week: SalesProgressPeriod;
  month: SalesProgressPeriod;
};

export type HomeSummarySalesProgressCallbacks = {
  normalizeEmail(value: unknown): string | null;
  personalStoreGuard(
    scope: SalesReportSummaryScopeDescriptor,
  ): Prisma.SalesReportWhereInput | null;
  dateRangeFor(summaryDate: Date): DateRange;
  loadCanonicalRevenueForRows(
    rows: Array<{ orderCode?: unknown }>,
    source: string,
  ): Promise<CanonicalRevenueLookup>;
};

/** Owns Home Summary sales-progress ranges, actuals and target composition. */
export class HomeSummarySalesProgressRuntime {
  constructor(
    private readonly prisma: PrismaService,
    private readonly callbacks: HomeSummarySalesProgressCallbacks,
  ) {}

  async build(
    user: any,
    scope: SalesReportSummaryScopeDescriptor,
    summaryDate: Date,
    selectedRange: DateRange,
  ): Promise<SalesProgressResponse> {
    const ranges = this.salesProgressRanges(summaryDate);
    const progressRange = {
      start: selectedRange.start,
      end: selectedRange.end,
    };
    const queryRange = {
      start: new Date(
        Math.min(progressRange.start.getTime(), ranges.month.start.getTime()),
      ),
      end: new Date(
        Math.max(progressRange.end.getTime(), ranges.month.end.getTime()),
      ),
    };
    const rows = await this.prisma.salesReport.findMany({
      where: this.salesProgressReportWhere(scope, queryRange),
      select: {
        orderCode: true,
        erpOrderCreatedAt: true,
        submittedAt: true,
      },
    });
    const canonicalRevenue = await this.callbacks.loadCanonicalRevenueForRows(
      rows,
      'sales_progress',
    );
    const actualFor = (range: DateRange) =>
      rows.reduce((sum, row) => {
        const occurredAt = row.erpOrderCreatedAt ?? row.submittedAt;
        if (occurredAt < range.start || occurredAt >= range.end) return sum;
        return sum + canonicalRevenueForOrder(canonicalRevenue, row.orderCode);
      }, 0);
    const actuals = {
      range: actualFor(progressRange),
      day: actualFor(ranges.day),
      week: actualFor(ranges.week),
      month: actualFor(ranges.month),
    };

    let jobRoleCode = String(user?.jobRoleCode || '')
      .trim()
      .toUpperCase();
    if (scope.scope === 'OWN' && !jobRoleCode && user?.id) {
      const saved = await this.prisma.user.findUnique({
        where: { id: user.id },
        select: { jobRoleCode: true },
      });
      jobRoleCode = String(saved?.jobRoleCode || '')
        .trim()
        .toUpperCase();
    }
    if (scope.scope === 'OWN' && jobRoleCode !== 'SA') {
      return this.withActuals('NOT_APPLICABLE', null, [], actuals);
    }

    const stores = await this.prisma.store.findMany({
      where: {
        organizationNodeId: { not: null },
        organizationNode: { isActive: true },
        ...(scope.scope === 'ALL'
          ? {}
          : { storeId: { in: scope.allowedStoreCodes } }),
      },
      orderBy: { storeId: 'asc' },
      select: {
        storeId: true,
        organizationNodeId: true,
      },
    });
    const nodeIds = stores
      .map((store) => store.organizationNodeId)
      .filter((value): value is string => Boolean(value));
    const targets = nodeIds.length
      ? await this.prisma.salesTarget.findMany({
          where: {
            organizationNodeId: { in: nodeIds },
            monthStart: ranges.targetMonthStart,
          },
        })
      : [];
    const targetByNode = new Map(
      targets.map((target) => [
        target.organizationNodeId,
        Math.round(Number(target.targetBeforeTax) * 1.08),
      ]),
    );
    const saCountByStore =
      scope.scope === 'OWN'
        ? await this.activeSaCountByStore(stores.map((store) => store.storeId))
        : new Map<string, number>();
    const missingStoreCodes: string[] = [];
    let monthlyTarget = 0;
    for (const store of stores) {
      const target = store.organizationNodeId
        ? targetByNode.get(store.organizationNodeId)
        : null;
      const saCount =
        scope.scope === 'OWN' ? (saCountByStore.get(store.storeId) ?? 0) : 1;
      if (target == null || saCount <= 0) {
        missingStoreCodes.push(store.storeId);
        continue;
      }
      monthlyTarget +=
        scope.scope === 'OWN' ? Math.round(target / saCount) : target;
    }
    if (stores.length === 0 || missingStoreCodes.length > 0) {
      return this.withActuals(
        targets.length === 0 ? 'MISSING' : 'PARTIAL',
        scope.scope === 'OWN'
          ? 'PERSONAL_SA'
          : scope.scope === 'ALL'
            ? 'ALL'
            : 'MANAGED',
        missingStoreCodes,
        actuals,
      );
    }
    const dayTarget = Math.round(monthlyTarget / ranges.daysInMonth);
    const weekTarget = Math.round(
      (monthlyTarget * ranges.weekDaysInMonth) / ranges.daysInMonth,
    );
    const selectedRangeDays = Math.max(
      1,
      Math.round(
        (progressRange.end.getTime() - progressRange.start.getTime()) /
          86_400_000,
      ),
    );
    const rangeTarget = Math.round(
      (monthlyTarget * selectedRangeDays) / ranges.daysInMonth,
    );
    const period = (actual: number, target: number): SalesProgressPeriod => ({
      actual,
      target,
      percentage: target > 0 ? Number(((actual / target) * 100).toFixed(2)) : 0,
    });
    return {
      status: 'AVAILABLE',
      scope:
        scope.scope === 'OWN'
          ? 'PERSONAL_SA'
          : scope.scope === 'ALL'
            ? 'ALL'
            : 'MANAGED',
      missingStoreCodes: [],
      range: period(actuals.range, rangeTarget),
      day: period(actuals.day, dayTarget),
      week: period(actuals.week, weekTarget),
      month: period(actuals.month, Math.round(monthlyTarget)),
    };
  }

  empty(): SalesProgressResponse {
    return this.withActuals('NOT_APPLICABLE', null, [], {
      range: 0,
      day: 0,
      week: 0,
      month: 0,
    });
  }

  salesProgressReportWhere(
    scope: SalesReportSummaryScopeDescriptor,
    range: DateRange,
  ): Prisma.SalesReportWhereInput {
    const base: Prisma.SalesReportWhereInput = {
      reportType: REPORT_TYPE_PURCHASED,
      erpExcludedAt: null,
      erpLifecycleStatus: {
        in: ['COMPLETED', 'COMPLETED_PARTIAL_RETURN'],
      },
      OR: [
        { erpOrderCreatedAt: { gte: range.start, lt: range.end } },
        {
          AND: [
            { erpOrderCreatedAt: null },
            { submittedAt: { gte: range.start, lt: range.end } },
          ],
        },
      ],
    };
    if (scope.scope === 'ALL') return base;
    if (scope.scope === 'MANAGED_SCOPE') {
      return { AND: [base, { storeCode: { in: scope.allowedStoreCodes } }] };
    }
    const email = this.callbacks.normalizeEmail(scope.ownEmail);
    if (!email) {
      return { AND: [base, { id: '__NO_PERSONAL_REPORT__' }] };
    }
    const filters: Prisma.SalesReportWhereInput[] = [
      base,
      { createdByEmail: { equals: email, mode: 'insensitive' } },
    ];
    const storeGuard = this.callbacks.personalStoreGuard(scope);
    if (storeGuard) filters.push(storeGuard);
    return { AND: filters };
  }

  salesProgressRanges(summaryDate: Date) {
    const local = new Date(summaryDate.getTime() + 7 * 60 * 60 * 1000);
    const year = local.getUTCFullYear();
    const monthIndex = local.getUTCMonth();
    const monthStart = new Date(
      Date.UTC(year, monthIndex, 1) - 7 * 60 * 60 * 1000,
    );
    const monthEnd = new Date(
      Date.UTC(year, monthIndex + 1, 1) - 7 * 60 * 60 * 1000,
    );
    const weekday = local.getUTCDay();
    const mondayOffset = (weekday + 6) % 7;
    const rawWeekStart = new Date(summaryDate);
    rawWeekStart.setUTCDate(rawWeekStart.getUTCDate() - mondayOffset);
    const rawWeekEnd = new Date(rawWeekStart);
    rawWeekEnd.setUTCDate(rawWeekEnd.getUTCDate() + 7);
    const weekStart = new Date(
      Math.max(rawWeekStart.getTime(), monthStart.getTime()),
    );
    const weekEnd = new Date(
      Math.min(rawWeekEnd.getTime(), monthEnd.getTime()),
    );
    const day = this.callbacks.dateRangeFor(summaryDate);
    return {
      day,
      week: { start: weekStart, end: weekEnd },
      month: { start: monthStart, end: monthEnd },
      targetMonthStart: new Date(Date.UTC(year, monthIndex, 1)),
      daysInMonth: new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate(),
      weekDaysInMonth: Math.max(
        1,
        Math.round((weekEnd.getTime() - weekStart.getTime()) / 86_400_000),
      ),
    };
  }

  async activeSaCountByStore(storeCodes: string[]) {
    const allowed = new Set(storeCodes.map((code) => code.toUpperCase()));
    const counts = new Map<string, number>();
    if (allowed.size === 0) return counts;
    const users = await this.prisma.user.findMany({
      where: { status: 'yes', jobRoleCode: 'SA' },
      include: {
        store: true,
        organizationNode: {
          include: organizationNodeStoreTreeInclude(),
        },
        organizationAssignments: {
          where: { isActive: true },
          include: {
            organizationNode: {
              include: organizationNodeStoreTreeInclude(),
            },
          },
        },
      },
    });
    for (const user of users) {
      const userStores = new Set<string>();
      if (user.store?.storeId) userStores.add(user.store.storeId.toUpperCase());
      for (const store of storesForOrganizationNodeTree(
        user.organizationNode,
      )) {
        if (store.storeId) userStores.add(String(store.storeId).toUpperCase());
      }
      for (const assignment of user.organizationAssignments) {
        for (const store of storesForOrganizationNodeTree(
          assignment.organizationNode,
        )) {
          if (store.storeId)
            userStores.add(String(store.storeId).toUpperCase());
        }
      }
      for (const storeCode of userStores) {
        if (allowed.has(storeCode)) {
          counts.set(storeCode, (counts.get(storeCode) ?? 0) + 1);
        }
      }
    }
    return counts;
  }

  withActuals(
    status: SalesProgressResponse['status'],
    scope: SalesProgressResponse['scope'],
    missingStoreCodes: string[],
    actuals: { range: number; day: number; week: number; month: number },
  ): SalesProgressResponse {
    const period = (actual: number): SalesProgressPeriod => ({
      actual,
      target: null,
      percentage: null,
    });
    return {
      status,
      scope,
      missingStoreCodes,
      range: period(actuals.range),
      day: period(actuals.day),
      week: period(actuals.week),
      month: period(actuals.month),
    };
  }
}
