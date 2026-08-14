import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { Prisma } from '@prisma/client';

const ORDER_TRANSFER_WINDOW_FORBIDDEN_MESSAGE =
  'Quá thời hạn cập nhật trong ngày. Vui lòng dùng chức năng Cấn trừ.';

type UserStore = { storeId: string };

export type MapVietinStatementPolicyRuntimeConfig = {
  canAccessStatements: (user: any) => Promise<boolean>;
  hasNationalScope: (user: any) => Promise<boolean>;
  resolveUserStores: (user: any) => Promise<UserStore[]>;
  isPhongVuEmail: (email: unknown) => boolean;
  userMatchesAccessCodes: (
    user: any,
    codes: string[],
  ) => boolean | Promise<boolean>;
  userBelongsToAccessCodes: (user: any, codes: string[]) => Promise<boolean>;
  finAccDepartmentCode: string;
  accDepartmentCode: string;
  vietnamDateToken: (value: Date) => string;
  now: () => Date;
};

export class MapVietinStatementPolicyRuntime {
  constructor(private readonly config: MapVietinStatementPolicyRuntimeConfig) {}

  async canReadStatementStore(user: any, storeCode?: string | null) {
    await this.assertCanUseStatements(user);
    if (!storeCode) return this.canReadUnassignedStatementTransactions(user);
    if (await this.config.hasNationalScope(user)) return true;
    const stores = await this.config.resolveUserStores(user);
    return stores.some((store) => store.storeId === storeCode);
  }

  async canReadUnassignedStatementTransactions(user: any) {
    await this.assertCanUseStatements(user);
    const snapshot = user as { role?: unknown; email?: unknown } | null;
    const role = typeof snapshot?.role === 'string' ? snapshot.role : '';
    if (role.toUpperCase() === 'SUPER_ADMIN') return true;
    if (this.config.isPhongVuEmail(snapshot?.email)) return true;
    return this.config.userMatchesAccessCodes(user, [
      this.config.finAccDepartmentCode,
    ]);
  }

  async resolveStatementActionScope(user: any) {
    await this.assertCanUseStatements(user);
    if (await this.config.hasNationalScope(user)) {
      return {
        allStores: true,
        storeCodes: [] as string[],
        includeUnassigned: true,
      };
    }
    const stores = await this.config.resolveUserStores(user);
    return {
      allStores: false,
      storeCodes: stores.map((store) => store.storeId),
      includeUnassigned:
        await this.canReadUnassignedStatementTransactions(user),
    };
  }

  statementActionScopeWhere(scope: {
    allStores: boolean;
    storeCodes: string[];
    includeUnassigned: boolean;
  }): Prisma.MapVietinTransactionWhereInput {
    if (scope.allStores) return {};
    const storeWhere: Prisma.MapVietinTransactionWhereInput = {
      storeCode: { in: scope.storeCodes },
    };
    return scope.includeUnassigned
      ? { OR: [storeWhere, { storeCode: null }] }
      : storeWhere;
  }

  async canEditProtectedStatementOrders(user: any) {
    return this.config.userMatchesAccessCodes(user, [
      this.config.finAccDepartmentCode,
    ]);
  }

  canEditStatementIncomeType(user: any) {
    return this.config.userBelongsToAccessCodes(user, [
      this.config.finAccDepartmentCode,
    ]);
  }

  async canReviewStatementOrderTransferRequests(user: any) {
    return this.config.userMatchesAccessCodes(user, [
      this.config.finAccDepartmentCode,
      this.config.accDepartmentCode,
    ]);
  }

  async canManageStatementOrderTracking(user: any) {
    return this.config.userMatchesAccessCodes(user, [
      this.config.finAccDepartmentCode,
      this.config.accDepartmentCode,
    ]);
  }

  async assertCanReviewStatementOrderTransferRequests(user: any) {
    await this.assertCanUseStatements(user);
    if (await this.canReviewStatementOrderTransferRequests(user)) return;
    throw new ForbiddenException('Bạn không có quyền xác nhận cấn trừ.');
  }

  async assertCanUseStatements(user: any) {
    if (await this.config.canAccessStatements(user)) return;
    throw new ForbiddenException('Không có quyền xem sao kê');
  }

  assertStatementOrderTransferWindow(row: {
    paidAt?: Date | null;
    firstSeenAt?: Date | null;
  }) {
    const anchor = row.paidAt ?? row.firstSeenAt ?? null;
    if (
      anchor &&
      this.config.vietnamDateToken(anchor) ===
        this.config.vietnamDateToken(this.config.now())
    ) {
      return;
    }
    throw new BadRequestException(ORDER_TRANSFER_WINDOW_FORBIDDEN_MESSAGE);
  }
}
