import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { isSuperAdminRole } from '../common/system-role';
import { logFingerprint, safeLogError } from '../common/log-sanitizer';
import { buildRealtimeRedisEnvelope } from '../common/realtime-event';
import { FeatureService } from '../feature/feature.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import {
  QUICK_ACTION_LINK_CODES,
  QUICK_ACTION_LINK_FEATURES,
  QuickActionLinkCode,
} from './quick-actions.constants';
import { UpdateQuickActionLinksDto } from './quick-actions.dto';

const MANAGER_ROLES = new Set([
  'STORE_MANAGER',
  'AREA_MANAGER',
  'REGION_MANAGER',
  'REGIONAL_MANAGER',
]);
const QUICK_ACTION_LINKS_UPDATED_CHANNEL = 'QUICK_ACTION_LINKS_UPDATED';

@Injectable()
export class QuickActionsService {
  private readonly logger = new Logger(QuickActionsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly features: FeatureService,
    private readonly redis: RedisService,
  ) {}

  async getQuickActions(user: any, storeCodeInput?: string) {
    const startedAt = Date.now();
    const stores = await this.accessibleStores(user);
    const selected = this.selectStore(stores, storeCodeInput);
    const links = this.emptyLinks();
    const enabledQrCodes = new Set<QuickActionLinkCode>();
    for (const code of QUICK_ACTION_LINK_CODES) {
      if (
        await this.features.canAccessFeature(
          user,
          QUICK_ACTION_LINK_FEATURES[code],
        )
      )
        enabledQrCodes.add(code);
    }
    const configuredAcrossScope =
      stores.length && enabledQrCodes.size
        ? await this.prisma.quickActionLink.findMany({
            where: {
              storeCode: { in: stores.map((store) => store.storeId) },
              actionCode: { in: [...enabledQrCodes] },
            },
            select: { actionCode: true },
            distinct: ['actionCode'],
          })
        : [];
    if (selected) {
      const configured = await this.prisma.quickActionLink.findMany({
        where: {
          storeCode: selected.storeId,
          actionCode: { in: [...QUICK_ACTION_LINK_CODES] },
        },
      });
      for (const item of configured) {
        const code = item.actionCode as QuickActionLinkCode;
        if (
          QUICK_ACTION_LINK_CODES.includes(code) &&
          enabledQrCodes.has(code)
        ) {
          links[code] = item.url;
        }
      }
    }
    this.logger.log(
      `Quick actions load succeeded: user=${this.safeUser(user)} store=${selected?.storeId ?? 'none'} storeCount=${stores.length} configuredCount=${Object.values(links).filter(Boolean).length} durationMs=${Date.now() - startedAt}`,
    );
    return {
      stores: stores.map(this.storeJson),
      selectedStoreCode: selected?.storeId ?? null,
      availableActionCodes: configuredAcrossScope.map(
        (item) => item.actionCode,
      ),
      links,
    };
  }

  async getManagedStores(user: any) {
    const stores = await this.assertManagerAndStores(user);
    return { stores: stores.map(this.storeJson) };
  }

  async getAdminLinks(user: any, storeCodeInput?: string) {
    const startedAt = Date.now();
    const stores = await this.assertManagerAndStores(user);
    const selected = this.selectStore(stores, storeCodeInput, true);
    const links = this.emptyLinks();
    const rows = await this.prisma.quickActionLink.findMany({
      where: {
        storeCode: selected.storeId,
        actionCode: { in: [...QUICK_ACTION_LINK_CODES] },
      },
    });
    for (const row of rows)
      links[row.actionCode as QuickActionLinkCode] = row.url;
    this.logger.log(
      `Quick action admin load succeeded: user=${this.safeUser(user)} store=${selected.storeId} configuredCount=${rows.length} durationMs=${Date.now() - startedAt}`,
    );
    return { store: this.storeJson(selected), links };
  }

  async updateAdminLinks(
    user: any,
    storeCodeInput: string,
    body: UpdateQuickActionLinksDto,
  ) {
    const startedAt = Date.now();
    const stores = await this.assertManagerAndStores(user);
    const selected = this.selectStore(stores, storeCodeInput, true);
    const normalized = Object.fromEntries(
      QUICK_ACTION_LINK_CODES.map((code) => [
        code,
        this.normalizeUrl(body[code]),
      ]),
    ) as Record<QuickActionLinkCode, string | null>;
    const writes: Prisma.PrismaPromise<unknown>[] = QUICK_ACTION_LINK_CODES.map(
      (code) =>
        normalized[code]
          ? this.prisma.quickActionLink.upsert({
              where: {
                storeCode_actionCode: {
                  storeCode: selected.storeId,
                  actionCode: code,
                },
              },
              create: {
                storeCode: selected.storeId,
                actionCode: code,
                url: normalized[code]!,
                updatedById: user?.id ?? null,
              },
              update: { url: normalized[code]!, updatedById: user?.id ?? null },
            })
          : this.prisma.quickActionLink.deleteMany({
              where: { storeCode: selected.storeId, actionCode: code },
            }),
    );
    await this.prisma.$transaction(writes);
    const configuredActionCodes = QUICK_ACTION_LINK_CODES.filter(
      (code) => normalized[code] != null,
    );
    let realtimeStatus = 'published';
    try {
      await this.redis.publishMessageOrThrow(
        QUICK_ACTION_LINKS_UPDATED_CHANNEL,
        buildRealtimeRedisEnvelope({
          type: QUICK_ACTION_LINKS_UPDATED_CHANNEL,
          audience: {
            storeCodes: [selected.storeId],
            featureCodes: ['QUICK_ACTIONS'],
          },
          payload: {
            storeCode: selected.storeId,
            actionCodes: [...QUICK_ACTION_LINK_CODES],
            configuredActionCodes,
            configuredCount: configuredActionCodes.length,
          },
        }),
      );
    } catch (error) {
      realtimeStatus = 'failed';
      this.logger.error(
        `Quick action links realtime update failed: store=${selected.storeId} actionCount=${QUICK_ACTION_LINK_CODES.length} error=${safeLogError(error)}`,
      );
    }
    this.logger.log(
      `Quick action admin update succeeded: user=${this.safeUser(user)} store=${selected.storeId} configuredCount=${Object.values(normalized).filter(Boolean).length} urlLengths=${QUICK_ACTION_LINK_CODES.map((code) => `${code}:${normalized[code]?.length ?? 0}`).join(',')} durationMs=${Date.now() - startedAt}`,
    );
    this.logger.log(
      `Quick action links realtime update completed: store=${selected.storeId} actionCount=${QUICK_ACTION_LINK_CODES.length} configuredCount=${configuredActionCodes.length} status=${realtimeStatus}`,
    );
    return this.getAdminLinks(user, selected.storeId);
  }

  private async assertManagerAndStores(user: any) {
    const stores = await this.accessibleStores(user);
    if (!isSuperAdminRole(user?.role)) {
      const saved = await this.prisma.user.findUnique({
        where: { id: user?.id ?? '' },
        select: { jobRoleCode: true },
      });
      const role = String(saved?.jobRoleCode || '')
        .trim()
        .toUpperCase();
      if (!MANAGER_ROLES.has(role)) {
        this.logger.warn(
          `Quick action admin denied: user=${this.safeUser(user)} reason=manager-role`,
        );
        throw new ForbiddenException(
          'Chỉ quản lý showroom trở lên mới được cấu hình các mã này.',
        );
      }
    }
    if (!stores.length)
      throw new ForbiddenException(
        'Tài khoản chưa được gán showroom để quản lý.',
      );
    return stores;
  }

  private async accessibleStores(user: any) {
    if (isSuperAdminRole(user?.role)) {
      return this.prisma.store.findMany({
        where: { organizationNode: { isActive: true } },
        orderBy: { storeId: 'asc' },
        select: { storeId: true, storeName: true, organizationNodeId: true },
      });
    }
    const saved = await this.prisma.user.findUnique({
      where: { id: user?.id ?? '' },
      include: {
        store: true,
        organizationNode: { include: organizationNodeStoreTreeInclude() },
        organizationAssignments: {
          where: { isActive: true },
          include: {
            organizationNode: { include: organizationNodeStoreTreeInclude() },
          },
        },
      },
    });
    if (!saved) return [];
    const byCode = new Map<string, any>();
    const add = (store: any) => {
      const code = String(store?.storeId || '')
        .trim()
        .toUpperCase();
      if (code) byCode.set(code, store);
    };
    add(saved.store);
    for (const store of storesForOrganizationNodeTree(saved.organizationNode))
      add(store);
    for (const assignment of saved.organizationAssignments)
      for (const store of storesForOrganizationNodeTree(
        assignment.organizationNode,
      ))
        add(store);
    return Array.from(byCode.values()).sort((a, b) =>
      String(a.storeId).localeCompare(String(b.storeId)),
    );
  }

  private selectStore(stores: any[], input?: string, required = false) {
    const code = String(input || '')
      .trim()
      .toUpperCase();
    if (!code) {
      if (stores.length === 1 || required)
        return (
          stores[0] ??
          (() => {
            throw new NotFoundException(
              'Không tìm thấy showroom trong phạm vi được cấp quyền.',
            );
          })()
        );
      return null;
    }
    const store = stores.find(
      (item) => String(item.storeId).toUpperCase() === code,
    );
    if (!store)
      throw new ForbiddenException(
        'Bạn chỉ được chọn showroom trong phạm vi được cấp quyền.',
      );
    return store;
  }

  private normalizeUrl(value: unknown) {
    const text = String(value ?? '').trim();
    if (!text) return null;
    if (text.length > 2048)
      throw new BadRequestException('Liên kết không được dài quá 2.048 ký tự.');
    try {
      const parsed = new URL(text);
      if (!['http:', 'https:'].includes(parsed.protocol))
        throw new Error('protocol');
    } catch {
      throw new BadRequestException(
        'Vui lòng nhập liên kết bắt đầu bằng http:// hoặc https://.',
      );
    }
    return text;
  }

  private emptyLinks() {
    return Object.fromEntries(
      QUICK_ACTION_LINK_CODES.map((code) => [code, null]),
    ) as Record<QuickActionLinkCode, string | null>;
  }
  private storeJson = (store: any) => ({
    storeCode: store.storeId,
    storeName: store.storeName,
  });
  private safeUser(user: any) {
    const id = String(user?.id || '').trim();
    if (id) return `userId:${id}`;
    const email = String(user?.email || '')
      .trim()
      .toLowerCase();
    return email ? `emailHash:${logFingerprint(email)}` : 'unknown';
  }
}
