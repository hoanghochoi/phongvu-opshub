import { Injectable, Logger } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { organizationNodeStoreTreeInclude } from '../common/organization-store-scope';
import { safeLogError } from '../common/log-sanitizer';
import { FeatureService } from '../feature/feature.service';
import { PolicyService } from '../policy/policy.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { AuthService } from './auth.service';

const AUTH_CONTEXT_SCHEMA_VERSION = 1;
const AUTH_CONTEXT_L1_TTL_MS = 5_000;
const AUTH_CONTEXT_REDIS_TTL_SECONDS = 30;
const AUTH_CONTEXT_LEASE_TTL_MS = 5_000;
const AUTH_CONTEXT_MAX_L1_ENTRIES = 2_000;
const AUTH_CONTEXT_KEY_PREFIX = 'opshub:auth-context:v1:';
const AUTH_CONTEXT_LEASE_PREFIX = 'opshub:auth-context:lease:v1:';
const AUTH_PROFILE_KEY_PREFIX = 'opshub:auth-profile:v1:';

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

  private async loadScopeSnapshot(userId: string) {
    const userModel = (this.prisma as any)?.user;
    if (!userId || !userModel?.findUnique) return null;
    return userModel.findUnique({
      where: { id: userId },
      select: {
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
          include: {
            area: { include: { region: true } },
            organizationNode: true,
          },
        },
        organizationNode: { include: organizationNodeStoreTreeInclude() },
        organizationAssignments: {
          where: { isActive: true },
          orderBy: [{ isPrimary: 'desc' }, { createdAt: 'asc' }],
          include: {
            organizationNode: { include: organizationNodeStoreTreeInclude() },
          },
        },
        region: true,
        area: { include: { region: true } },
      },
    });
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
