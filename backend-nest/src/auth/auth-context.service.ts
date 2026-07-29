import { Injectable, Logger } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { safeLogError } from '../common/log-sanitizer';
import { FeatureService } from '../feature/feature.service';
import { PolicyService } from '../policy/policy.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { getOrganizationTree } from '../common/organization-tree-cache';
import { AuthService } from './auth.service';

const AUTH_CONTEXT_SCHEMA_VERSION = 1;
const AUTH_CONTEXT_L1_TTL_MS = 5_000;
const AUTH_CONTEXT_REDIS_TTL_SECONDS = 30;
const AUTH_CONTEXT_LEASE_TTL_MS = 5_000;
const AUTH_CONTEXT_MAX_L1_ENTRIES = 2_000;
const AUTH_CONTEXT_KEY_PREFIX = 'opshub:auth-context:v1:';
const AUTH_CONTEXT_LEASE_PREFIX = 'opshub:auth-context:lease:v1:';
const AUTH_PROFILE_KEY_PREFIX = 'opshub:auth-profile:v1:';
const HOME_SCOPE_BATCH_DELAY_MS = 20;
const MAX_PENDING_HOME_SCOPE_REQUESTS = 5_000;
const HOME_SCOPE_TREE_DEPTH = 6;

export type AuthContextVersion = {
  userId: string;
  tokenVersion: number;
  sessionVersion: number;
  accessVersion: number;
};

export type AuthContext = {
  version: AuthContextVersion;
  profile: Awaited<ReturnType<AuthService['getUserData']>>;
  featureAccess: Record<string, boolean>;
  policyAccess: Record<string, boolean>;
  capabilities: {
    conditionalGet: true;
    realtimeV2Topics: readonly string[];
  };
  orgScopeSlice: {
    organizationAccessCodes: string[];
    organizationNodeIds: string[];
    assignedStores: unknown[];
  };
  scopeSnapshot: any | null;
};

type CacheEntry = {
  expiresAt: number;
  context: AuthContext;
};

type ProfileCacheEntry = {
  expiresAt: number;
  profile: AuthContext['profile'];
};

type HomeFeatureScopeSlice = {
  featureAccess: Record<string, boolean>;
  scopeSnapshot: any | null;
};

type PendingHomeScopeRequest = {
  authenticatedUser: any;
  featureCodes: string[];
  userId: string;
  resolve: (slice: HomeFeatureScopeSlice) => void;
  reject: (reason?: unknown) => void;
};

@Injectable()
export class AuthContextService {
  private readonly logger = new Logger(AuthContextService.name);
  private readonly l1 = new Map<string, CacheEntry>();
  private readonly inFlight = new Map<string, Promise<AuthContext>>();
  private readonly profileL1 = new Map<string, ProfileCacheEntry>();
  private readonly profileInFlight = new Map<
    string,
    Promise<AuthContext['profile']>
  >();
  private pendingHomeScopeBatch: PendingHomeScopeRequest[] | null = null;

  constructor(
    private readonly authService: AuthService,
    private readonly featureService: FeatureService,
    private readonly policyService: PolicyService,
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  async getContext(authenticatedUser: any): Promise<AuthContext> {
    const version = this.versionFor(authenticatedUser);
    const key = this.cacheKey(version);
    const label = key.slice(-12);
    const now = Date.now();
    const local = this.l1.get(key);
    if (local && local.expiresAt > now) {
      this.logger.debug(
        `Auth context L1 hit: userId=${version.userId} key=${label}`,
      );
      return local.context;
    }
    if (local) this.l1.delete(key);

    const pending = this.inFlight.get(key);
    if (pending) {
      this.logger.debug(
        `Auth context joined in-flight: userId=${version.userId} key=${label}`,
      );
      return pending;
    }

    const promise = this.load(version, authenticatedUser, key, label).finally(
      () => {
        this.inFlight.delete(key);
      },
    );
    this.inFlight.set(key, promise);
    return promise;
  }

  async profile(authenticatedUser: any) {
    const version = this.versionFor(authenticatedUser);
    const contextKey = this.cacheKey(version);
    const label = contextKey.slice(-12);
    const now = Date.now();
    const local = this.profileL1.get(contextKey);
    if (local && local.expiresAt > now) {
      this.logger.debug(
        `Auth profile L1 hit: userId=${version.userId} key=${label}`,
      );
      return local.profile;
    }
    if (local) this.profileL1.delete(contextKey);

    const fullPending = this.inFlight.get(contextKey);
    if (fullPending) return (await fullPending).profile;

    const pending = this.profileInFlight.get(contextKey);
    if (pending) return pending;
    const promise = this.loadProfile(version, contextKey, label).finally(() =>
      this.profileInFlight.delete(contextKey),
    );
    this.profileInFlight.set(contextKey, promise);
    return promise;
  }

  async withContext(authenticatedUser: any) {
    const context = await this.getContext(authenticatedUser);
    const enriched = { ...authenticatedUser };
    Object.defineProperty(enriched, '__authContext', {
      configurable: true,
      enumerable: false,
      value: context,
      writable: false,
    });
    return enriched;
  }

  async withFeatureScopeContext(
    authenticatedUser: any,
    featureCodes: string[],
  ) {
    const { featureAccess, scopeSnapshot } =
      await this.loadHomeFeatureScopeSlice(authenticatedUser, featureCodes);

    const enriched = { ...authenticatedUser };
    Object.defineProperty(enriched, '__authContext', {
      configurable: true,
      enumerable: false,
      value: { featureAccess, scopeSnapshot },
      writable: false,
    });
    return enriched;
  }

  etagForUser(authenticatedUser: any) {
    const version = this.versionFor(authenticatedUser);
    const projectionIdentity = this.projectionIdentityFor(authenticatedUser);
    return `"${createHash('sha256')
      .update(
        [
          AUTH_CONTEXT_SCHEMA_VERSION,
          version.userId,
          version.tokenVersion,
          version.sessionVersion,
          version.accessVersion,
          projectionIdentity,
        ].join('|'),
      )
      .digest('hex')}"`;
  }

  versionFor(authenticatedUser: any): AuthContextVersion {
    const authSession = authenticatedUser?.authSession;
    return {
      userId: String(authenticatedUser?.id || '').trim(),
      tokenVersion: this.safeInt(authenticatedUser?.tokenVersion),
      sessionVersion: this.safeInt(authSession?.sessionVersion),
      accessVersion: this.safeInt(authenticatedUser?.accessVersion),
    };
  }

  private async load(
    version: AuthContextVersion,
    authenticatedUser: any,
    key: string,
    label: string,
  ): Promise<AuthContext> {
    const startedAt = Date.now();
    this.logger.log(
      `Auth context load started: userId=${version.userId} key=${label}`,
    );

    const cached = await this.redisJson<AuthContext>(key);
    if (cached?.version && this.sameVersion(cached.version, version)) {
      this.storeL1(key, cached);
      this.logger.log(
        `Auth context Redis hit: userId=${version.userId} key=${label}`,
      );
      return cached;
    }

    const leaseKey =
      AUTH_CONTEXT_LEASE_PREFIX + key.slice(AUTH_CONTEXT_KEY_PREFIX.length);
    let leaseToken: string | null = null;
    let leaseUnavailable = false;
    try {
      try {
        leaseToken = await this.redis.tryAcquireLease(
          leaseKey,
          AUTH_CONTEXT_LEASE_TTL_MS,
        );
      } catch (error) {
        leaseUnavailable = true;
        this.logger.warn(
          `Auth context lease unavailable; hydrating locally: userId=${version.userId} key=${label} error=${safeLogError(error)}`,
        );
      }
      if (!leaseToken && !leaseUnavailable) {
        for (let attempt = 0; attempt < 5; attempt += 1) {
          await new Promise((resolve) => setTimeout(resolve, 25));
          const retry = await this.redisJson<AuthContext>(key);
          if (retry?.version && this.sameVersion(retry.version, version)) {
            this.storeL1(key, retry);
            this.logger.log(
              `Auth context Redis lease wait hit: userId=${version.userId} key=${label} attempt=${attempt + 1}`,
            );
            return retry;
          }
        }
        this.logger.warn(
          `Auth context lease unavailable; hydrating locally: userId=${version.userId} key=${label}`,
        );
      }

      const scopeSnapshot = await this.loadScopeSnapshot(version.userId);
      const profile = await this.authService.projectUserData(scopeSnapshot);
      const contextUser = { ...authenticatedUser };
      Object.defineProperty(contextUser, '__authScopeSnapshot', {
        configurable: false,
        enumerable: false,
        value: scopeSnapshot,
        writable: false,
      });
      const [featureAccess, policyAccess] = await Promise.all([
        this.featureService.resolveFeatureAccessMap(contextUser),
        this.policyService.resolvePolicyAccessMap(contextUser),
      ]);
      const context: AuthContext = {
        version,
        profile,
        featureAccess,
        policyAccess,
        capabilities: {
          conditionalGet: true,
          realtimeV2Topics: [
            'access.changed',
            'home.summary',
            'warranty',
            'payment.transactions',
            'payment.speaker',
            'payment.delivery-metrics',
            'notifications.statement-transfer',
            'notifications.offset-adjustment',
            'sales-report.orders',
            'quick-actions.links',
          ],
        },
        orgScopeSlice: {
          organizationAccessCodes: Array.isArray(
            profile.organizationAccessCodes,
          )
            ? profile.organizationAccessCodes
            : [],
          organizationNodeIds: Array.isArray(profile.organizationNodeIds)
            ? profile.organizationNodeIds
            : [],
          assignedStores: Array.isArray(profile.assignedStores)
            ? profile.assignedStores
            : [],
        },
        scopeSnapshot,
      };
      this.storeL1(key, context);
      try {
        await this.redis.setJsonWithTtl(
          key,
          context,
          AUTH_CONTEXT_REDIS_TTL_SECONDS,
        );
      } catch (error) {
        this.logger.warn(
          `Auth context Redis store skipped: userId=${version.userId} error=${safeLogError(error)}`,
        );
      }
      this.logger.log(
        `Auth context load succeeded: userId=${version.userId} features=${Object.keys(featureAccess).length} policies=${Object.keys(policyAccess).length} scopeNodes=${context.orgScopeSlice.organizationNodeIds.length} durationMs=${Date.now() - startedAt}`,
      );
      return context;
    } catch (error) {
      this.logger.error(
        `Auth context load failed: userId=${version.userId} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
      throw error;
    } finally {
      if (leaseToken) {
        try {
          await this.redis.releaseLease(leaseKey, leaseToken);
        } catch (error) {
          this.logger.warn(
            `Auth context lease release failed: userId=${version.userId} error=${safeLogError(error)}`,
          );
        }
      }
    }
  }

  private async loadProfile(
    version: AuthContextVersion,
    contextKey: string,
    label: string,
  ) {
    const fullCached = await this.redisJson<AuthContext>(contextKey);
    if (fullCached?.version && this.sameVersion(fullCached.version, version)) {
      this.storeL1(contextKey, fullCached);
      this.storeProfileL1(contextKey, fullCached.profile);
      this.logger.log(
        `Auth profile reused full context: userId=${version.userId} key=${label}`,
      );
      return fullCached.profile;
    }

    const profileKey = this.profileCacheKey(version);
    const cached = await this.redisJson<{
      version: AuthContextVersion;
      profile: AuthContext['profile'];
    }>(profileKey);
    if (cached?.version && this.sameVersion(cached.version, version)) {
      this.storeProfileL1(contextKey, cached.profile);
      this.logger.log(
        `Auth profile Redis hit: userId=${version.userId} key=${label}`,
      );
      return cached.profile;
    }

    const startedAt = Date.now();
    const scopeSnapshot = await this.loadScopeSnapshot(version.userId);
    const profile = await this.authService.projectUserData(scopeSnapshot);
    this.storeProfileL1(contextKey, profile);
    try {
      await this.redis.setJsonWithTtl(
        profileKey,
        { version, profile },
        AUTH_CONTEXT_REDIS_TTL_SECONDS,
      );
    } catch (error) {
      this.logger.warn(
        `Auth profile Redis store skipped: userId=${version.userId} error=${safeLogError(error)}`,
      );
    }
    this.logger.log(
      `Auth profile load succeeded: userId=${version.userId} key=${label} durationMs=${Date.now() - startedAt}`,
    );
    return profile;
  }

  private loadHomeFeatureScopeSlice(
    authenticatedUser: any,
    featureCodes: string[],
  ): Promise<HomeFeatureScopeSlice> {
    const userId = this.versionFor(authenticatedUser).userId;
    const userModel = (this.prisma as any)?.user;
    if (!userId || !userModel?.findMany) {
      return this.loadIndependentFeatureScopeSlice(
        authenticatedUser,
        featureCodes,
        userId,
      );
    }

    return new Promise<HomeFeatureScopeSlice>((resolve, reject) => {
      const batch = this.pendingHomeScopeBatch;
      if (batch && batch.length < MAX_PENDING_HOME_SCOPE_REQUESTS) {
        batch.push({
          authenticatedUser,
          featureCodes,
          userId,
          resolve,
          reject,
        });
        return;
      }
      if (batch) {
        this.logger.debug(
          `Home auth feature/scope overflow fallback: pendingRequests=${batch.length} features=${featureCodes.length}`,
        );
        void this.loadIndependentFeatureScopeSlice(
          authenticatedUser,
          featureCodes,
          userId,
        ).then(resolve, reject);
        return;
      }

      const newBatch: PendingHomeScopeRequest[] = [
        { authenticatedUser, featureCodes, userId, resolve, reject },
      ];
      this.pendingHomeScopeBatch = newBatch;
      setTimeout(() => {
        if (this.pendingHomeScopeBatch === newBatch) {
          this.pendingHomeScopeBatch = null;
        }
        void this.flushHomeScopeBatch(newBatch);
      }, HOME_SCOPE_BATCH_DELAY_MS);
    });
  }

  private async flushHomeScopeBatch(
    batch: PendingHomeScopeRequest[],
  ): Promise<void> {
    const startedAt = Date.now();
    const principalCount = new Set(batch.map((entry) => entry.userId)).size;
    const featureCount = new Set(batch.flatMap((entry) => entry.featureCodes))
      .size;
    if (batch.length > 1) {
      this.logger.debug(
        `Home auth feature/scope pre-query batch started: callers=${batch.length} principals=${principalCount} features=${featureCount}`,
      );
    }
    try {
      const [rows, organizationNodes] = await Promise.all([
        (this.prisma as any).user.findMany({
          where: {
            id: { in: Array.from(new Set(batch.map((entry) => entry.userId))) },
          },
          select: this.scopeSnapshotSelect(),
        }),
        getOrganizationTree(this.prisma),
      ]);
      const organizationGraph = this.organizationGraph(organizationNodes);
      const enrichedRows = (rows as any[]).map((row) =>
        this.enrichScopeSnapshot(row, organizationGraph),
      );
      const byId = new Map(enrichedRows.map((row) => [String(row.id), row]));
      const featureCodes = Array.from(
        new Set(batch.flatMap((entry) => entry.featureCodes)),
      );
      const representativeById = new Map<string, PendingHomeScopeRequest>();
      for (const entry of batch) {
        if (byId.has(entry.userId) && !representativeById.has(entry.userId)) {
          representativeById.set(entry.userId, entry);
        }
      }
      const principalIds = Array.from(representativeById.keys());
      const contextUsers = principalIds.map((userId) =>
        this.withScopeSnapshot(
          representativeById.get(userId)!.authenticatedUser,
          byId.get(userId),
        ),
      );
      const accessMaps =
        await this.featureService.resolveFeatureAccessMapsForCodes(
          contextUsers,
          featureCodes,
        );
      const accessById = new Map(
        principalIds.map((userId, index) => [userId, accessMaps[index] ?? {}]),
      );

      for (const entry of batch) {
        const scopeSnapshot = byId.get(entry.userId) ?? null;
        const requestedCodes = new Set(
          entry.featureCodes.map((featureCode) =>
            String(featureCode).trim().toUpperCase(),
          ),
        );
        const featureAccess = scopeSnapshot
          ? Object.fromEntries(
              Object.entries(accessById.get(entry.userId) ?? {}).filter(
                ([featureCode]) => requestedCodes.has(featureCode),
              ),
            )
          : Object.fromEntries(
              entry.featureCodes.map((featureCode) => [featureCode, false]),
            );
        entry.resolve({ featureAccess, scopeSnapshot });
      }

      if (batch.length > 1) {
        this.logger.debug(
          `Home auth feature/scope pre-query batch closed: callers=${batch.length} principals=${byId.size} features=${featureCodes.length} pendingRequests=${this.pendingHomeScopeBatch?.length ?? 0} durationMs=${Date.now() - startedAt}`,
        );
      }
    } catch (error) {
      this.logger.error(
        `Home auth feature/scope pre-query batch failed: callers=${batch.length} principals=${principalCount} features=${featureCount} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
      batch.forEach((entry) => entry.reject(error));
    }
  }

  private async loadIndependentFeatureScopeSlice(
    authenticatedUser: any,
    featureCodes: string[],
    userId: string,
  ): Promise<HomeFeatureScopeSlice> {
    const scopeSnapshot = await this.loadScopeSnapshot(userId);
    if (!scopeSnapshot) {
      return {
        featureAccess: Object.fromEntries(
          featureCodes.map((featureCode) => [featureCode, false]),
        ),
        scopeSnapshot: null,
      };
    }
    const featureAccess =
      await this.featureService.resolveFeatureAccessMapForCodes(
        this.withScopeSnapshot(authenticatedUser, scopeSnapshot),
        featureCodes,
      );
    return { featureAccess, scopeSnapshot };
  }

  private withScopeSnapshot(authenticatedUser: any, scopeSnapshot: any) {
    const contextUser = { ...authenticatedUser };
    Object.defineProperty(contextUser, '__authScopeSnapshot', {
      configurable: false,
      enumerable: false,
      value: scopeSnapshot,
      writable: false,
    });
    return contextUser;
  }

  private homeScopeStoreSelect() {
    return {
      storeId: true,
      storeName: true,
      organizationNodeId: true,
      area: {
        select: {
          code: true,
          abbreviation: true,
          region: { select: { code: true, abbreviation: true } },
        },
      },
    };
  }

  private scopeSnapshotSelect() {
    return {
      id: true,
      email: true,
      firstName: true,
      lastName: true,
      role: true,
      status: true,
      avatarUrl: true,
      profileCompletedAt: true,
      branchLockedAt: true,
      departmentCode: true,
      jobRoleCode: true,
      workScopeType: true,
      regionCode: true,
      areaCode: true,
      organizationNodeId: true,
      storeId: true,
      store: {
        select: this.homeScopeStoreSelect(),
      },
      organizationAssignments: {
        where: { isActive: true },
        orderBy: [{ isPrimary: 'desc' }, { createdAt: 'asc' }],
        select: {
          isActive: true,
          isPrimary: true,
          createdAt: true,
          organizationNodeId: true,
        },
      },
      region: { select: { code: true, abbreviation: true } },
      area: {
        select: {
          code: true,
          abbreviation: true,
          region: { select: { code: true, abbreviation: true } },
        },
      },
    };
  }

  private async loadScopeSnapshot(userId: string) {
    const userModel = (this.prisma as any)?.user;
    if (!userId || !userModel?.findUnique) return null;
    const [row, organizationNodes] = await Promise.all([
      userModel.findUnique({
        where: { id: userId },
        select: this.scopeSnapshotSelect(),
      }),
      getOrganizationTree(this.prisma),
    ]);
    return row
      ? this.enrichScopeSnapshot(row, this.organizationGraph(organizationNodes))
      : null;
  }

  private enrichScopeSnapshot(
    row: any,
    graph: { treeFor: (id: string) => any },
  ) {
    if (!row) return row;
    const enriched = { ...row };
    const organizationNodeId = String(row.organizationNodeId || '').trim();
    if (organizationNodeId) {
      enriched.organizationNode = graph.treeFor(organizationNodeId);
    }

    if (row.store && typeof row.store === 'object') {
      const store = { ...row.store };
      const storeNodeId = String(store.organizationNodeId || '').trim();
      store.organizationNode = storeNodeId ? graph.treeFor(storeNodeId) : null;
      enriched.store = store;
    }

    if (Array.isArray(row.organizationAssignments)) {
      enriched.organizationAssignments = row.organizationAssignments.map(
        (assignment: any) => {
          const next = { ...assignment };
          const assignmentNodeId = String(
            assignment?.organizationNodeId || '',
          ).trim();
          if (assignmentNodeId) {
            next.organizationNode = graph.treeFor(assignmentNodeId);
          }
          return next;
        },
      );
    }

    return enriched;
  }

  private organizationGraph(organizationNodes: any[]) {
    const byId = new Map<string, any>();
    for (const source of organizationNodes) {
      const id = String(source?.id || '').trim();
      if (!id) continue;
      byId.set(id, {
        ...source,
        parent: null,
        children: [],
        stores: Array.isArray(source?.stores)
          ? source.stores.map((store: any) => ({ ...store }))
          : [],
      });
    }

    const childrenById = new Map<string, string[]>();
    for (const node of byId.values()) {
      const parentId = String(node.parentId || '').trim();
      if (!parentId || !byId.has(parentId)) continue;
      const children = childrenById.get(parentId) ?? [];
      children.push(node.id);
      childrenById.set(parentId, children);
    }

    const sortChildren = (ids: string[]) =>
      ids.sort((leftId, rightId) => {
        const left = byId.get(leftId);
        const right = byId.get(rightId);
        return (
          Number(left?.sortOrder ?? 0) - Number(right?.sortOrder ?? 0) ||
          String(left?.id ?? '').localeCompare(String(right?.id ?? ''))
        );
      });

    for (const node of byId.values()) {
      node.stores.sort((left: any, right: any) =>
        String(left.storeId).localeCompare(String(right.storeId)),
      );
    }

    const buildBranch = (id: string, depth: number, path: Set<string>): any => {
      const source = byId.get(id);
      if (!source) return null;
      const node = {
        ...source,
        parent: null,
        stores: source.stores.map((store: any) => ({ ...store })),
        children: [] as any[],
      };
      if (depth >= HOME_SCOPE_TREE_DEPTH || path.has(id)) return node;
      const nextPath = new Set(path);
      nextPath.add(id);
      node.children = sortChildren([...(childrenById.get(id) ?? [])])
        .map((childId) => buildBranch(childId, depth + 1, nextPath))
        .filter(Boolean);
      return node;
    };

    const buildParentBranch = (
      id: string,
      depth: number,
      path: Set<string>,
      includeDescendants: boolean,
    ): any => {
      const source = byId.get(id);
      if (!source) return null;
      const node = {
        ...source,
        parent: null,
        stores: source.stores.map((store: any) => ({ ...store })),
        children: includeDescendants
          ? sortChildren([...(childrenById.get(id) ?? [])])
              .map((childId) => buildBranch(childId, depth + 1, path))
              .filter(Boolean)
          : [],
      };
      if (depth >= HOME_SCOPE_TREE_DEPTH || path.has(id)) return node;
      const nextPath = new Set(path);
      nextPath.add(id);
      const parentId = String(byId.get(id)?.parentId || '').trim();
      node.parent = parentId
        ? buildParentBranch(parentId, depth + 1, nextPath, false)
        : null;
      return node;
    };

    const treeFor = (id: string) => {
      if (!byId.has(id)) return null;
      const node = buildBranch(id, 0, new Set());
      const parentId = String(byId.get(id)?.parentId || '').trim();
      const nodeType = String(byId.get(id)?.type || '')
        .trim()
        .toUpperCase();
      const parentType = String(byId.get(parentId)?.type || '')
        .trim()
        .toUpperCase();
      const includeParentDescendants =
        ['LV5_POSITION', 'JOB_ROLE', 'POSITION'].includes(nodeType) &&
        !['LV4_STORE', 'SHOWROOM', 'STORE'].includes(parentType);
      node.parent = parentId
        ? buildParentBranch(
            parentId,
            1,
            new Set([id]),
            includeParentDescendants,
          )
        : null;
      return node;
    };

    return { treeFor };
  }

  private async redisJson<T>(key: string) {
    try {
      return await this.redis.getJson<T>(key);
    } catch (error) {
      this.logger.warn(
        `Auth context Redis read skipped: error=${safeLogError(error)}`,
      );
      return null;
    }
  }

  private storeL1(key: string, context: AuthContext) {
    while (this.l1.size >= AUTH_CONTEXT_MAX_L1_ENTRIES) {
      const oldest = this.l1.keys().next().value;
      if (!oldest) break;
      this.l1.delete(oldest);
    }
    this.l1.set(key, {
      expiresAt: Date.now() + AUTH_CONTEXT_L1_TTL_MS,
      context,
    });
  }

  private storeProfileL1(key: string, profile: AuthContext['profile']) {
    while (this.profileL1.size >= AUTH_CONTEXT_MAX_L1_ENTRIES) {
      const oldest = this.profileL1.keys().next().value;
      if (!oldest) break;
      this.profileL1.delete(oldest);
    }
    this.profileL1.set(key, {
      expiresAt: Date.now() + AUTH_CONTEXT_L1_TTL_MS,
      profile,
    });
  }

  private cacheKey(version: AuthContextVersion) {
    const digest = this.versionDigest(version);
    return AUTH_CONTEXT_KEY_PREFIX + digest;
  }

  private profileCacheKey(version: AuthContextVersion) {
    return AUTH_PROFILE_KEY_PREFIX + this.versionDigest(version);
  }

  private versionDigest(version: AuthContextVersion) {
    return createHash('sha256')
      .update(
        [
          version.userId,
          version.tokenVersion,
          version.sessionVersion,
          version.accessVersion,
        ].join('|'),
      )
      .digest('hex');
  }

  private sameVersion(left: AuthContextVersion, right: AuthContextVersion) {
    return (
      left.userId === right.userId &&
      left.tokenVersion === right.tokenVersion &&
      left.sessionVersion === right.sessionVersion &&
      left.accessVersion === right.accessVersion
    );
  }

  private safeInt(value: unknown) {
    const parsed = Number(value ?? 0);
    return Number.isInteger(parsed) && parsed >= 0 ? parsed : 0;
  }

  private projectionIdentityFor(authenticatedUser: any) {
    const updatedAt = authenticatedUser?.updatedAt;
    if (updatedAt instanceof Date) return updatedAt.toISOString();
    const normalized = String(updatedAt ?? '').trim();
    return normalized || 'unknown-profile-version';
  }
}
