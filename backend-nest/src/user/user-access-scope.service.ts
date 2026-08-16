import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

const AREA_SCOPE = 'AREA';
const REGION_SCOPE = 'REGION';
const NATIONAL_SCOPE = 'NATIONAL';

export type UserAccessScopeRuntime = {
  isScopedAdmin: (admin: any) => boolean;
  effectiveWorkScope: (admin: any) => string;
  adminDomainScope: (admin: any) => Promise<Prisma.UserWhereInput>;
  adminManagementScopeRootId: (admin: any) => Promise<string | null>;
  userOrganizationNodeWhere: (
    organizationNodeId: unknown,
  ) => Promise<Prisma.UserWhereInput | null>;
  combineUserScope: (
    domainScope: Prisma.UserWhereInput,
    locationScope: Prisma.UserWhereInput,
  ) => Prisma.UserWhereInput;
  adminOrgRootId: (admin: any) => string | null;
  adminStoreOrganizationScope: (
    admin: any,
  ) => Promise<Prisma.StoreWhereInput | undefined>;
  organizationDescendantIds: (rootId: string) => Promise<string[]>;
  combineStoreScope: (
    organizationScope: Prisma.StoreWhereInput | undefined,
    locationScope: Prisma.StoreWhereInput | undefined,
  ) => Prisma.StoreWhereInput | undefined;
};

/**
 * Owns shared admin user/store scope composition while UserService remains the
 * stable facade and retains low-level organization/policy helper ownership.
 */
export class UserAccessScopeService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly runtime: UserAccessScopeRuntime,
  ) {}

  async adminScope(admin: any): Promise<Prisma.UserWhereInput> {
    if (this.runtime.isScopedAdmin(admin)) {
      const scope = this.runtime.effectiveWorkScope(admin);
      const domainScope = await this.runtime.adminDomainScope(admin);
      if (scope === NATIONAL_SCOPE) return domainScope;
      if (admin.organizationNodeId) {
        const scopeRootId =
          await this.runtime.adminManagementScopeRootId(admin);
        const organizationScope = await this.runtime.userOrganizationNodeWhere(
          scopeRootId ?? admin.organizationNodeId,
        );
        if (organizationScope) {
          return this.runtime.combineUserScope(domainScope, organizationScope);
        }
      }
      if (scope === REGION_SCOPE) {
        const locationScope = admin.regionCode
          ? {
              OR: [
                { regionCode: admin.regionCode },
                { store: { area: { regionCode: admin.regionCode } } },
              ],
            }
          : { id: '__NO_REGION__' };
        return this.runtime.combineUserScope(domainScope, locationScope);
      }
      if (scope === AREA_SCOPE) {
        const locationScope = admin.areaCode
          ? {
              OR: [
                { areaCode: admin.areaCode },
                { store: { areaCode: admin.areaCode } },
              ],
            }
          : { id: '__NO_AREA__' };
        return this.runtime.combineUserScope(domainScope, locationScope);
      }
      const locationScope = admin.storeId
        ? { storeId: admin.storeId }
        : { id: '__NO_STORE__' };
      return this.runtime.combineUserScope(domainScope, locationScope);
    }
    return {};
  }

  async adminOrganizationNodeScopeWhere(
    admin: any,
  ): Promise<Prisma.OrganizationNodeWhereInput | undefined> {
    const rootId = this.runtime.adminOrgRootId(admin);
    if (!rootId) return undefined;
    const organizationNodeIds =
      await this.runtime.organizationDescendantIds(rootId);
    return { id: { in: organizationNodeIds } };
  }

  async storeWithinAdminScope(admin: any, store: any) {
    const organizationScope =
      await this.runtime.adminStoreOrganizationScope(admin);
    if (organizationScope) {
      const organizationNodeIds = (organizationScope.organizationNodeId as any)
        ?.in as string[] | undefined;
      if (
        !store?.organizationNodeId ||
        !organizationNodeIds?.includes(store.organizationNodeId)
      ) {
        return false;
      }
    }

    const scope = this.runtime.effectiveWorkScope(admin);
    if (scope === NATIONAL_SCOPE) return true;
    if (admin.organizationNodeId && store?.organizationNodeId) {
      const scopeRootId = await this.runtime.adminManagementScopeRootId(admin);
      const organizationNodeIds = await this.runtime.organizationDescendantIds(
        scopeRootId ?? admin.organizationNodeId,
      );
      return organizationNodeIds.includes(store.organizationNodeId);
    }
    if (scope === REGION_SCOPE) {
      return Boolean(
        admin.regionCode && store.area?.regionCode === admin.regionCode,
      );
    }
    if (scope === AREA_SCOPE) {
      return Boolean(admin.areaCode && store.areaCode === admin.areaCode);
    }
    return Boolean(admin.storeId && admin.storeId === store.id);
  }

  async userWithinAdminScope(admin: any, user: any) {
    const scope = await this.adminScope(admin);
    if (Object.keys(scope).length === 0) return true;
    const count = await this.prisma.user.count({
      where: { AND: [{ id: user.id }, scope] },
    });
    return count > 0;
  }

  async adminStoreScope(admin: any, query?: string) {
    const insensitive = Prisma.QueryMode.insensitive;
    const queryWhere = query
      ? {
          OR: [
            { storeId: { contains: query, mode: insensitive } },
            { storeName: { contains: query, mode: insensitive } },
            {
              transferAccountNumber: {
                contains: query,
                mode: insensitive,
              },
            },
            { transferAccountName: { contains: query, mode: insensitive } },
            { transferBankName: { contains: query, mode: insensitive } },
            { mapVietinUsername: { contains: query, mode: insensitive } },
          ],
        }
      : undefined;
    const scopeWhere = await this.adminStoreScopeWhere(admin);

    if (queryWhere && scopeWhere) return { AND: [scopeWhere, queryWhere] };
    return queryWhere || scopeWhere;
  }

  private async adminStoreScopeWhere(
    admin: any,
  ): Promise<Prisma.StoreWhereInput | undefined> {
    if (!this.runtime.isScopedAdmin(admin)) return undefined;
    const organizationScope =
      await this.runtime.adminStoreOrganizationScope(admin);
    const scope = this.runtime.effectiveWorkScope(admin);
    if (scope === NATIONAL_SCOPE) {
      return this.runtime.combineStoreScope(organizationScope, undefined);
    }
    if (admin.organizationNodeId) {
      const scopeRootId = await this.runtime.adminManagementScopeRootId(admin);
      const organizationNodeIds = await this.runtime.organizationDescendantIds(
        scopeRootId ?? admin.organizationNodeId,
      );
      return this.runtime.combineStoreScope(organizationScope, {
        organizationNodeId: { in: organizationNodeIds },
      });
    }
    if (scope === REGION_SCOPE) {
      const locationScope = admin.regionCode
        ? { area: { regionCode: admin.regionCode } }
        : { id: '__NO_REGION__' };
      return this.runtime.combineStoreScope(organizationScope, locationScope);
    }
    if (scope === AREA_SCOPE) {
      const locationScope = admin.areaCode
        ? { areaCode: admin.areaCode }
        : { id: '__NO_AREA__' };
      return this.runtime.combineStoreScope(organizationScope, locationScope);
    }
    return this.runtime.combineStoreScope(organizationScope, {
      id: admin.storeId || '__NO_STORE__',
    });
  }
}
