import {
  Injectable,
  Logger,
  Optional,
  UnauthorizedException,
} from '@nestjs/common';
import { createHash } from 'crypto';
import { safeLogError } from '../common/log-sanitizer';
import { FeatureService } from '../feature/feature.service';
import { PolicyService } from '../policy/policy.service';
import { AuthService } from './auth.service';
import { AuthContextService } from './auth-context.service';

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

type AuthBootstrapUser = Record<string, unknown> & {
  id: string;
  email: string;
};

export type AuthBootstrapPayload = {
  schemaVersion: typeof AUTH_BOOTSTRAP_SCHEMA_VERSION;
  generatedAt: string;
  version: string;
  user: AuthBootstrapUser;
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
    @Optional() private readonly authContextService?: AuthContextService,
  ) {}

  async resolve(user: AuthenticatedUser): Promise<AuthBootstrapResult> {
    const startedAt = Date.now();
    const userId = String(user?.id || 'unknown');
    this.logger.log(`Auth bootstrap started: userId=${userId}`);

    try {
      const authenticatedUserId = String(user?.id || '').trim();
      const authenticatedEmail = String(user?.email || '')
        .trim()
        .toLowerCase();
      if (!authenticatedUserId || !authenticatedEmail) {
        throw new UnauthorizedException(
          'Phiên làm việc thiếu thông tin tài khoản. Vui lòng đăng nhập lại.',
        );
      }
      const context = this.authContextService
        ? await this.authContextService.getContext(user)
        : null;
      let userData: Record<string, unknown>;
      let featureAccess: Record<string, boolean>;
      let policyAccess: Record<string, boolean>;
      if (context) {
        userData = this.profileRecord(context.profile as unknown);
        featureAccess = context.featureAccess;
        policyAccess = context.policyAccess;
      } else {
        const userDataPromise = this.authService.getUserData(
          user.email,
        ) as Promise<unknown>;
        const featureAccessPromise =
          this.featureService.resolveFeatureAccessMap(user) as Promise<
            Record<string, boolean>
          >;
        const policyAccessPromise = this.policyService.resolvePolicyAccessMap(
          user,
        ) as Promise<Record<string, boolean>>;
        const [resolvedUserData, resolvedFeatureAccess, resolvedPolicyAccess] =
          await Promise.all([
            userDataPromise,
            featureAccessPromise,
            policyAccessPromise,
          ]);
        userData = this.profileRecord(resolvedUserData);
        featureAccess = resolvedFeatureAccess;
        policyAccess = resolvedPolicyAccess;
      }
      // /auth/get-user receives the identity in its request body, so its
      // compatibility profile intentionally omits id/email. Bootstrap is the
      // canonical self-contained snapshot and must project authenticated
      // identity explicitly. Write these fields last so profile data can
      // never override the authenticated principal.
      const bootstrapUser = {
        ...userData,
        id: authenticatedUserId,
        email: authenticatedEmail,
      };
      const capabilities = {
        conditionalGet: true as const,
        realtimeV2Topics: REALTIME_V2_TOPICS,
      };
      const version = context
        ? this.authContextService!.etagForUser(user).replace(/^"|"$/g, '')
        : this.stableVersion({
            schemaVersion: AUTH_BOOTSTRAP_SCHEMA_VERSION,
            user: bootstrapUser,
            featureAccess,
            policyAccess,
            capabilities,
          });
      const body: AuthBootstrapPayload = {
        schemaVersion: AUTH_BOOTSTRAP_SCHEMA_VERSION,
        generatedAt: new Date().toISOString(),
        version,
        user: bootstrapUser,
        featureAccess,
        policyAccess,
        capabilities,
      };

      this.logger.log(
        `Auth bootstrap succeeded: userId=${userId} schemaVersion=${AUTH_BOOTSTRAP_SCHEMA_VERSION} identity=complete features=${Object.keys(featureAccess).length} policies=${Object.keys(policyAccess).length} version=${version.slice(0, 12)} durationMs=${Date.now() - startedAt}`,
      );
      return { body, etag: `"${version}"` };
    } catch (error) {
      this.logger.error(
        `Auth bootstrap failed: userId=${userId} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
      throw error;
    }
  }

  etagForUser(user: AuthenticatedUser) {
    return this.authContextService?.etagForUser(user) ?? null;
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

  private profileRecord(value: unknown): Record<string, unknown> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
    return value as Record<string, unknown>;
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
