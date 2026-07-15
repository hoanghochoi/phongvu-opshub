import { Injectable, Logger } from '@nestjs/common';
import { createHash } from 'crypto';
import { safeLogError } from '../common/log-sanitizer';
import { FeatureService } from '../feature/feature.service';
import { PolicyService } from '../policy/policy.service';
import { AuthService } from './auth.service';

const AUTH_BOOTSTRAP_SCHEMA_VERSION = 1 as const;
const REALTIME_V2_TOPICS = [
  'access.changed',
  'home.summary',
  'warranty',
  'payment.transactions',
  'payment.speaker',
  'payment.delivery-metrics',
  'notifications.statement-transfer',
  'notifications.offset-adjustment',
  'sales-report.orders',
] as const;

type AuthenticatedUser = {
  id?: string | null;
  email: string;
  [key: string]: unknown;
};

export type AuthBootstrapPayload = {
  schemaVersion: typeof AUTH_BOOTSTRAP_SCHEMA_VERSION;
  generatedAt: string;
  version: string;
  user: Awaited<ReturnType<AuthService['getUserData']>>;
  featureAccess: Record<string, boolean>;
  policyAccess: Record<string, boolean>;
  capabilities: {
    conditionalGet: true;
    realtimeV2Topics: readonly string[];
  };
};

export type AuthBootstrapResult = {
  body: AuthBootstrapPayload;
  etag: string;
};

@Injectable()
export class AuthBootstrapService {
  private readonly logger = new Logger(AuthBootstrapService.name);

  constructor(
    private readonly authService: AuthService,
    private readonly featureService: FeatureService,
    private readonly policyService: PolicyService,
  ) {}

  async resolve(user: AuthenticatedUser): Promise<AuthBootstrapResult> {
    const startedAt = Date.now();
    const userId = String(user?.id || 'unknown');
    this.logger.log(`Auth bootstrap started: userId=${userId}`);

    try {
      const [userData, featureAccess, policyAccess] = await Promise.all([
        this.authService.getUserData(user.email),
        this.featureService.resolveFeatureAccessMap(user),
        this.policyService.resolvePolicyAccessMap(user),
      ]);
      const capabilities = {
        conditionalGet: true as const,
        realtimeV2Topics: REALTIME_V2_TOPICS,
      };
      const version = this.stableVersion({
        schemaVersion: AUTH_BOOTSTRAP_SCHEMA_VERSION,
        user: userData,
        featureAccess,
        policyAccess,
        capabilities,
      });
      const body: AuthBootstrapPayload = {
        schemaVersion: AUTH_BOOTSTRAP_SCHEMA_VERSION,
        generatedAt: new Date().toISOString(),
        version,
        user: userData,
        featureAccess,
        policyAccess,
        capabilities,
      };

      this.logger.log(
        `Auth bootstrap succeeded: userId=${userId} features=${Object.keys(featureAccess).length} policies=${Object.keys(policyAccess).length} version=${version.slice(0, 12)} durationMs=${Date.now() - startedAt}`,
      );
      return { body, etag: `"${version}"` };
    } catch (error) {
      this.logger.error(
        `Auth bootstrap failed: userId=${userId} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
      throw error;
    }
  }

  matchesEtag(ifNoneMatch: string | undefined, etag: string) {
    if (!ifNoneMatch) return false;
    const normalizedEtag = this.normalizeEtag(etag);
    return ifNoneMatch.split(',').some((candidate) => {
      const value = candidate.trim();
      return value === '*' || this.normalizeEtag(value) === normalizedEtag;
    });
  }

  private stableVersion(value: unknown) {
    return createHash('sha256').update(this.canonicalJson(value)).digest('hex');
  }

  private canonicalJson(value: unknown): string {
    if (value instanceof Date) {
      return JSON.stringify(value.toISOString());
    }
    if (Array.isArray(value)) {
      return `[${value.map((item) => this.canonicalJson(item)).join(',')}]`;
    }
    if (value && typeof value === 'object') {
      const entries = Object.entries(value as Record<string, unknown>)
        .filter(([, entryValue]) => entryValue !== undefined)
        .sort(([left], [right]) => left.localeCompare(right));
      return `{${entries
        .map(
          ([key, entryValue]) =>
            `${JSON.stringify(key)}:${this.canonicalJson(entryValue)}`,
        )
        .join(',')}}`;
    }
    return JSON.stringify(value) ?? 'null';
  }

  private normalizeEtag(value: string) {
    return value.trim().replace(/^W\//i, '');
  }
}
