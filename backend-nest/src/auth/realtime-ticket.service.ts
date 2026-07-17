import {
  ForbiddenException,
  Injectable,
  Logger,
  Optional,
  UnauthorizedException,
} from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';
import { FeatureService } from '../feature/feature.service';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { PolicyService } from '../policy/policy.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { AuthContextService } from './auth-context.service';
import { getOrganizationTree } from '../common/organization-tree-cache';

const REALTIME_TICKET_AUDIENCE = 'opshub-realtime';
const REALTIME_TICKET_KEY_PREFIX = 'opshub:realtime:ticket:';
const DEFAULT_REALTIME_TICKET_TTL_SECONDS = 45;
const MIN_REALTIME_TICKET_TTL_SECONDS = 15;
const MAX_REALTIME_TICKET_TTL_SECONDS = 120;
const SUPER_ADMIN_ROLE = 'SUPER_ADMIN';

type OrganizationNodeScope = {
  id: string;
  parentId: string | null;
  code: string;
  businessCode: string | null;
  isActive: boolean;
  stores: Array<{ storeId: string }>;
};

@Injectable()
export class RealtimeTicketService {
  private readonly logger = new Logger(RealtimeTicketService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly featureService: FeatureService,
    private readonly policyService: PolicyService,
    @Optional() private readonly authContextService?: AuthContextService,
  ) {}

  async issueTicket(
    authenticatedUser: any,
    requestedStoreCode?: string | null,
  ) {
    const startedAt = Date.now();
    const userId = String(authenticatedUser?.id || '').trim();
    if (!userId || !authenticatedUser?.authSession) {
      throw new UnauthorizedException(
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      );
    }

    this.logger.log(
      'Realtime ticket issue started: userId=' +
        userId +
        ' hasRequestedStore=' +
        Boolean(requestedStoreCode?.trim()),
    );

    const authContext = this.authContextService
      ? await this.authContextService.getContext(authenticatedUser)
      : null;
    const user = authContext
      ? {
          id: userId,
          email: authenticatedUser.email,
          role: authContext.profile.role,
          status: authContext.profile.status,
          tokenVersion: authenticatedUser.tokenVersion ?? 0,
          departmentCode: authContext.profile.departmentCode,
          organizationNodeId: authContext.profile.organizationNodeId,
          store: authContext.profile.storeId
            ? { storeId: authContext.profile.storeId }
            : null,
          organizationAssignments: (
            authContext.profile.organizationNodeIds ?? []
          ).map((organizationNodeId: string) => ({ organizationNodeId })),
        }
      : await this.prisma.user.findUnique({
          where: { id: userId },
          include: {
            store: { select: { storeId: true } },
            organizationAssignments: {
              where: { isActive: true },
              select: { organizationNodeId: true },
            },
          },
        });
    if (!user || user.status === 'no') {
      this.logger.warn(
        'Realtime ticket issue blocked: userId=' +
          userId +
          ' reason=user_unavailable',
      );
      throw new UnauthorizedException(
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      );
    }

    const nodes: OrganizationNodeScope[] = authContext
      ? []
      : ((await getOrganizationTree(this.prisma)) as OrganizationNodeScope[]);
    const organizationAccessCodes = authContext
      ? [...authContext.orgScopeSlice.organizationAccessCodes]
      : this.organizationAccessCodes(user, nodes);
    const requestedStore = this.normalizeCode(requestedStoreCode);
    if (
      requestedStore &&
      user.role !== SUPER_ADMIN_ROLE &&
      !organizationAccessCodes.includes(requestedStore)
    ) {
      this.logger.warn(
        'Realtime ticket issue blocked: userId=' +
          userId +
          ' reason=store_out_of_scope',
      );
      throw new ForbiddenException(
        'Bạn không có quyền nhận dữ liệu của showroom đã chọn.',
      );
    }

    const [featureAccess, policyAccess] = authContext
      ? [authContext.featureAccess, authContext.policyAccess]
      : await Promise.all([
          this.featureService.resolveFeatureAccessMap(user),
          this.policyService.resolvePolicyAccessMap(user),
        ]);
    const featureCodes = new Set(
      Object.entries(featureAccess)
        .filter(([, enabled]) => enabled === true)
        .map(([code]) => code),
    );
    // Keep the speaker claim aligned with the exact authorization predicate
    // used by /ready, /stream and /ack. Auth context is intentionally cached,
    // but a stale or incomplete feature map must not silently drop realtime
    // speaker events while the same user is still authorized over HTTP.
    const speakerFeatureFromMap =
      featureAccess[FEATURE_KEYS.PAYMENT_SPEAKER] === true;
    const speakerFeatureAllowed = await this.featureService.canAccessFeature(
      user,
      FEATURE_KEYS.PAYMENT_SPEAKER,
    );
    if (speakerFeatureAllowed) {
      featureCodes.add(FEATURE_KEYS.PAYMENT_SPEAKER);
    } else {
      featureCodes.delete(FEATURE_KEYS.PAYMENT_SPEAKER);
    }
    if (speakerFeatureFromMap !== speakerFeatureAllowed) {
      this.logger.warn(
        'Realtime ticket speaker entitlement reconciled: userId=' +
          userId +
          ' cachedAllowed=' +
          speakerFeatureFromMap +
          ' effectiveAllowed=' +
          speakerFeatureAllowed,
      );
    }
    if (
      policyAccess[ADMIN_POLICY_CODES.BANK_STATEMENTS] === true ||
      policyAccess[ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE] === true
    ) {
      featureCodes.add(FEATURE_KEYS.BANK_STATEMENTS);
    }
    if (policyAccess[ADMIN_POLICY_CODES.OFFSET_ADJUSTMENTS] === true) {
      featureCodes.add(FEATURE_KEYS.OFFSET_ADJUSTMENTS);
    }
    organizationAccessCodes.sort();
    const policyCodes = !requestedStore
      ? [
          ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE,
          ADMIN_POLICY_CODES.PAYMENT_MONITOR_ALL_SCOPE,
        ].filter((code) => policyAccess[code] === true)
      : [];
    const effectiveFeatureCodes = Array.from(featureCodes).sort();
    const now = new Date();
    const ttlSeconds = this.ticketTtlSeconds();
    const expiresAt = new Date(now.getTime() + ttlSeconds * 1000);
    const rawTicket = randomBytes(32).toString('base64url');
    const ticketHash = createHash('sha256').update(rawTicket).digest('hex');
    const primaryStoreCode =
      requestedStore ??
      (user.role === SUPER_ADMIN_ROLE
        ? null
        : (this.normalizeCode(user.store?.storeId) ?? null));
    const session = authenticatedUser.authSession;
    const payload = {
      version: 1,
      audience: REALTIME_TICKET_AUDIENCE,
      userId,
      email: String(user.email || '')
        .trim()
        .toLowerCase(),
      role: String(user.role || '')
        .trim()
        .toUpperCase(),
      storeCode: primaryStoreCode,
      departmentCode: this.normalizeCode(user.departmentCode),
      organizationNodeId: user.organizationNodeId ?? null,
      organizationAccessCodes,
      policyCodes,
      featureCodes: effectiveFeatureCodes,
      sessionId: String(session.sessionId || ''),
      sessionVersion: Number(session.sessionVersion),
      platform: String(session.platform || ''),
      tokenVersion: Number(user.tokenVersion ?? 0),
      issuedAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
    };

    await this.redis.setJsonWithTtl(
      REALTIME_TICKET_KEY_PREFIX + ticketHash,
      payload,
      ttlSeconds,
    );
    this.logger.log(
      'Realtime ticket issue succeeded: userId=' +
        userId +
        ' storeScoped=' +
        Boolean(primaryStoreCode) +
        ' organizationCodeCount=' +
        organizationAccessCodes.length +
        ' featureCount=' +
        effectiveFeatureCodes.length +
        ' speakerFeature=' +
        speakerFeatureAllowed +
        ' ttlSeconds=' +
        ttlSeconds +
        ' durationMs=' +
        (Date.now() - startedAt),
    );
    return {
      ticket: rawTicket,
      audience: REALTIME_TICKET_AUDIENCE,
      expiresAt: expiresAt.toISOString(),
      expiresInSeconds: ttlSeconds,
    };
  }

  private organizationAccessCodes(
    user: {
      role: string;
      departmentCode?: string | null;
      organizationNodeId?: string | null;
      store?: { storeId: string } | null;
      organizationAssignments?: Array<{ organizationNodeId: string }>;
    },
    nodes: OrganizationNodeScope[],
  ) {
    const codes = new Set<string>();
    const addCode = (value: unknown) => {
      const code = this.normalizeCode(value);
      if (code) codes.add(code);
    };
    addCode(user.departmentCode);
    addCode(user.store?.storeId);

    const byId = new Map(nodes.map((node) => [node.id, node]));
    const children = new Map<string, OrganizationNodeScope[]>();
    for (const node of nodes) {
      if (!node.parentId) continue;
      const list = children.get(node.parentId) ?? [];
      list.push(node);
      children.set(node.parentId, list);
    }
    const anchors = new Set<string>();
    if (user.organizationNodeId) anchors.add(user.organizationNodeId);
    for (const assignment of user.organizationAssignments ?? []) {
      if (assignment.organizationNodeId) {
        anchors.add(assignment.organizationNodeId);
      }
    }

    for (const anchorId of anchors) {
      const ancestorVisited = new Set<string>();
      let cursor = byId.get(anchorId);
      while (cursor && !ancestorVisited.has(cursor.id)) {
        ancestorVisited.add(cursor.id);
        if (cursor.isActive) {
          addCode(cursor.code);
          addCode(cursor.businessCode);
        }
        cursor = cursor.parentId ? byId.get(cursor.parentId) : undefined;
      }

      const queue = [anchorId];
      const descendantVisited = new Set<string>();
      while (queue.length > 0) {
        const nodeId = queue.shift()!;
        if (descendantVisited.has(nodeId)) continue;
        descendantVisited.add(nodeId);
        const node = byId.get(nodeId);
        if (!node || !node.isActive) continue;
        addCode(node.code);
        addCode(node.businessCode);
        for (const store of node.stores ?? []) addCode(store.storeId);
        for (const child of children.get(nodeId) ?? []) queue.push(child.id);
      }
    }
    return Array.from(codes).sort();
  }

  private ticketTtlSeconds() {
    const parsed = Number(process.env.REALTIME_TICKET_TTL_SECONDS);
    if (!Number.isInteger(parsed)) return DEFAULT_REALTIME_TICKET_TTL_SECONDS;
    return Math.min(
      MAX_REALTIME_TICKET_TTL_SECONDS,
      Math.max(MIN_REALTIME_TICKET_TTL_SECONDS, parsed),
    );
  }

  private normalizeCode(value: unknown) {
    const code = typeof value === 'string' ? value.trim().toUpperCase() : '';
    return code || null;
  }
}
