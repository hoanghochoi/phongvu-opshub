import { Prisma } from '@prisma/client';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { FeatureService } from '../feature/feature.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { SalesReportSummaryScopeDescriptor } from '../sales-reports/sales-reports.service';

export type HomeSummaryScopeRuntimeCallbacks = {
  normalizeStoreCode(value: unknown): string | null;
  normalizeEmail(value: unknown): string | null;
  optionalText(value: unknown, maxLength: number): string | null;
  normalizedStoreCodes(values: Array<string | null | undefined>): string[];
};

export type HomeSummarySalesProgressAssignee = {
  userId: string;
  label: string;
  email: string | null;
  storeCodes: string[];
  isSelected: boolean;
  isCurrentUser: boolean;
  firstName: string | null;
  lastName: string | null;
};

export class HomeSummaryScopeRuntime {
  constructor(
    private readonly prisma: PrismaService,
    private readonly featureService: FeatureService,
    private readonly callbacks: HomeSummaryScopeRuntimeCallbacks,
  ) {}

  async resolveSectionAccess(user: any) {
    const contextAccess = user?.__authContext?.featureAccess;
    if (contextAccess && typeof contextAccess === 'object') {
      return {
        salesAvailable:
          contextAccess[FEATURE_KEYS.HOME_DASHBOARD_SALES] === true,
        financeAvailable:
          contextAccess[FEATURE_KEYS.HOME_DASHBOARD_FINANCE] === true,
      };
    }
    const [salesAvailable, financeAvailable] = await Promise.all([
      this.featureService.canAccessFeature(
        user,
        FEATURE_KEYS.HOME_DASHBOARD_SALES,
      ),
      this.featureService.canAccessFeature(
        user,
        FEATURE_KEYS.HOME_DASHBOARD_FINANCE,
      ),
    ]);
    return { salesAvailable, financeAvailable };
  }

  async resolveSelectedSalesMetricsScope(
    user: any,
    scope: SalesReportSummaryScopeDescriptor,
    requestedUserId: string | null,
  ): Promise<{
    scope: SalesReportSummaryScopeDescriptor;
    selectedUserId: string | null;
  }> {
    const requested = this.callbacks.optionalText(requestedUserId, 80);
    if (!requested) return { scope, selectedUserId: null };
    const assignees = await this.salesProgressAssigneesForScope(user, scope);
    const selected = this.selectSalesProgressAssignee(assignees, requested);
    if (!selected) return { scope, selectedUserId: null };
    return {
      scope: this.salesProgressScopeForAssignee(selected),
      selectedUserId: selected.userId,
    };
  }

  async salesProgressAssigneesForScope(
    user: any,
    scope: SalesReportSummaryScopeDescriptor,
  ): Promise<HomeSummarySalesProgressAssignee[]> {
    if (scope.scope !== 'MANAGED_SCOPE' && scope.scope !== 'ALL') return [];
    const allowedStoreCodes = await this.salesProgressAssigneeStoreCodes(scope);
    if (allowedStoreCodes.length === 0) return [];
    const allowed = new Set(allowedStoreCodes);
    const users = await this.prisma.user.findMany({
      where: { status: 'yes', jobRoleCode: 'SA' },
      include: {
        store: {
          include: {
            area: { include: { region: true } },
            organizationNode: true,
          },
        },
        area: { include: { region: true } },
        region: true,
        organizationNode: {
          include: organizationNodeStoreTreeInclude(),
        },
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
    return users
      .map((candidate: any) =>
        this.salesProgressAssigneeFromUser(candidate, allowed, user),
      )
      .filter(
        (
          value: HomeSummarySalesProgressAssignee | null,
        ): value is HomeSummarySalesProgressAssignee => value != null,
      )
      .sort((left, right) => {
        if (left.isCurrentUser !== right.isCurrentUser) {
          return left.isCurrentUser ? -1 : 1;
        }
        return left.label.localeCompare(right.label, 'vi');
      });
  }

  private async salesProgressAssigneeStoreCodes(
    scope: SalesReportSummaryScopeDescriptor,
  ) {
    const scopedStoreCodes = this.callbacks.normalizedStoreCodes(
      scope.allowedStoreCodes,
    );
    if (scope.scope !== 'ALL' || scopedStoreCodes.length > 0) {
      return scopedStoreCodes;
    }
    const stores = await this.prisma.store.findMany({
      where: {
        organizationNodeId: { not: null },
        organizationNode: { isActive: true },
      },
      orderBy: { storeId: 'asc' },
      select: { storeId: true },
    });
    return this.callbacks.normalizedStoreCodes(
      stores.map((store) => store.storeId),
    );
  }

  private salesProgressAssigneeFromUser(
    candidate: any,
    allowed: Set<string>,
    currentUser: any,
  ): HomeSummarySalesProgressAssignee | null {
    const storeSources = this.storeSourcesForUser(candidate);
    const storeCodes = this.callbacks
      .normalizedStoreCodes(storeSources.map((store) => store?.storeId))
      .filter((code) => allowed.has(code));
    if (storeCodes.length === 0) return null;
    const userId = this.callbacks.optionalText(candidate?.id, 80);
    if (!userId) return null;
    const email = this.callbacks.normalizeEmail(candidate?.email);
    const firstName = this.callbacks.optionalText(candidate?.firstName, 80);
    const lastName = this.callbacks.optionalText(candidate?.lastName, 80);
    const fullName = [firstName, lastName].filter(Boolean).join(' ').trim();
    return {
      userId,
      firstName,
      lastName,
      email,
      storeCodes,
      label: fullName || email || `Nhân viên ${storeCodes.join(', ')}`,
      isCurrentUser:
        userId === this.callbacks.optionalText(currentUser?.id, 80),
      isSelected: false,
    };
  }

  selectSalesProgressAssignee(
    assignees: HomeSummarySalesProgressAssignee[],
    requestedUserId: string | null,
  ) {
    if (assignees.length === 0) return null;
    const requested = this.callbacks.optionalText(requestedUserId, 80);
    if (requested) {
      return (
        assignees.find((assignee) => assignee.userId === requested) ?? null
      );
    }
    return null;
  }

  salesProgressScopeForAssignee(
    assignee: HomeSummarySalesProgressAssignee,
  ): SalesReportSummaryScopeDescriptor {
    return {
      available: true,
      scope: 'OWN',
      scopeLabel: 'Tổng quan cá nhân',
      scopeDetail: assignee.storeCodes.join(', '),
      unavailableMessage: null,
      ownUserId: null,
      ownEmail: assignee.email,
      ownPersonnelCode: null,
      allowedStoreCodes: assignee.storeCodes,
    };
  }

  private storeSourcesForUser(user: any) {
    const stores: any[] = [];
    const pushStore = (store?: any | null) => {
      const storeCode = this.callbacks.normalizeStoreCode(store?.storeId);
      if (!storeCode) return;
      if (
        stores.some(
          (existing) =>
            this.callbacks.normalizeStoreCode(existing?.storeId) === storeCode,
        )
      ) {
        return;
      }
      stores.push(store);
    };
    pushStore(user?.store);
    for (const store of storesForOrganizationNodeTree(user?.organizationNode)) {
      pushStore(store);
    }
    for (const assignment of user?.organizationAssignments ?? []) {
      for (const store of storesForOrganizationNodeTree(
        assignment?.organizationNode,
      )) {
        pushStore(store);
      }
    }
    return stores;
  }
}
