import { ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { isSuperAdminRole } from '../common/system-role';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateSalesTargetsDto } from './sales-targets.dto';

@Injectable()
export class SalesTargetsService {
  private readonly logger = new Logger(SalesTargetsService.name);

  constructor(private readonly prisma: PrismaService) {}

  async list(user: any, month: string) {
    const startedAt = Date.now();
    const monthStart = this.monthStart(month);
    const stores = await this.accessibleStores(user);
    const nodeIds = stores
      .map((store) => store.organizationNodeId)
      .filter((value): value is string => Boolean(value));
    const targets = nodeIds.length
      ? await this.prisma.salesTarget.findMany({
          where: { monthStart, organizationNodeId: { in: nodeIds } },
        })
      : [];
    const byNode = new Map(
      targets.map((target) => [target.organizationNodeId, target]),
    );
    this.logger.log(
      `Sales targets load succeeded: user=${this.safeUser(user)} month=${month} storeCount=${stores.length} configuredCount=${targets.length} durationMs=${Date.now() - startedAt}`,
    );
    return {
      month,
      items: stores.map((store) => {
        const target = store.organizationNodeId
          ? byNode.get(store.organizationNodeId)
          : null;
        return {
          organizationNodeId: store.organizationNodeId,
          storeCode: store.storeId,
          storeName: store.storeName,
          targetBeforeTax: target ? Number(target.targetBeforeTax) : null,
          updatedAt: target?.updatedAt ?? null,
        };
      }),
    };
  }

  async updateBatch(user: any, body: UpdateSalesTargetsDto) {
    const startedAt = Date.now();
    const monthStart = this.monthStart(body.month);
    const stores = await this.accessibleStores(user);
    const allowed = new Set(
      stores
        .map((store) => store.organizationNodeId)
        .filter((value): value is string => Boolean(value)),
    );
    const invalid = body.targets.find(
      (target) => !allowed.has(target.organizationNodeId),
    );
    if (invalid) {
      this.logger.warn(
        `Sales targets update denied: user=${this.safeUser(user)} month=${body.month} itemCount=${body.targets.length}`,
      );
      throw new ForbiddenException(
        'Bạn chỉ được cập nhật chỉ tiêu các showroom trong phạm vi được cấp quyền.',
      );
    }
    const writes: Prisma.PrismaPromise<unknown>[] = body.targets.map(
      (target) =>
        target.targetBeforeTax == null
          ? this.prisma.salesTarget.deleteMany({
              where: {
                organizationNodeId: target.organizationNodeId,
                monthStart,
              },
            })
          : this.prisma.salesTarget.upsert({
              where: {
                organizationNodeId_monthStart: {
                  organizationNodeId: target.organizationNodeId,
                  monthStart,
                },
              },
              create: {
                organizationNodeId: target.organizationNodeId,
                monthStart,
                targetBeforeTax: BigInt(target.targetBeforeTax),
                updatedByUserId: user?.id ?? null,
                updatedByEmail: user?.email ?? null,
              },
              update: {
                targetBeforeTax: BigInt(target.targetBeforeTax),
                updatedByUserId: user?.id ?? null,
                updatedByEmail: user?.email ?? null,
              },
            }),
    );
    if (writes.length) await this.prisma.$transaction(writes);
    this.logger.log(
      `Sales targets update succeeded: user=${this.safeUser(user)} month=${body.month} itemCount=${body.targets.length} durationMs=${Date.now() - startedAt}`,
    );
    return this.list(user, body.month);
  }

  private async accessibleStores(user: any) {
    if (isSuperAdminRole(user?.role)) {
      return this.prisma.store.findMany({
        where: {
          organizationNodeId: { not: null },
          organizationNode: { isActive: true },
        },
        orderBy: { storeId: 'asc' },
        select: {
          storeId: true,
          storeName: true,
          organizationNodeId: true,
        },
      });
    }
    const saved = await this.prisma.user.findUnique({
      where: { id: user?.id ?? '' },
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
    if (!saved) return [];
    const storesByCode = new Map<string, any>();
    for (const assignment of saved.organizationAssignments) {
      for (const store of storesForOrganizationNodeTree(
        assignment.organizationNode,
      )) {
        const code = String(store.storeId || '').trim();
        if (code && store.organizationNodeId) storesByCode.set(code, store);
      }
    }
    for (const store of storesForOrganizationNodeTree(saved.organizationNode)) {
      const code = String(store.storeId || '').trim();
      if (code && store.organizationNodeId) storesByCode.set(code, store);
    }
    if (saved.store?.organizationNodeId) {
      storesByCode.set(saved.store.storeId, saved.store);
    }
    return Array.from(storesByCode.values()).sort((a, b) =>
      String(a.storeId).localeCompare(String(b.storeId)),
    );
  }

  private monthStart(month: string) {
    return new Date(`${month}-01T00:00:00.000Z`);
  }

  private safeUser(user: any) {
    return user?.id || user?.email || 'unknown';
  }
}
