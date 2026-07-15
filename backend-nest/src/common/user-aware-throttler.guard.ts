import { ExecutionContext, Injectable, Logger } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { createHash } from 'crypto';
import {
  InjectThrottlerOptions,
  InjectThrottlerStorage,
  ThrottlerGuard,
  ThrottlerLimitDetail,
  ThrottlerStorage,
} from '@nestjs/throttler';
import type { ThrottlerModuleOptions } from '@nestjs/throttler';

type RateLimitJwtClaims = {
  sub?: unknown;
};

type RateLimitRequest = Record<string, any> & {
  headers?: Record<string, unknown>;
  query?: Record<string, unknown>;
  body?: unknown;
  method?: unknown;
  route?: { path?: unknown };
  path?: unknown;
  originalUrl?: unknown;
};

@Injectable()
export class UserAwareThrottlerGuard extends ThrottlerGuard {
  private readonly logger = new Logger(UserAwareThrottlerGuard.name);
  private readonly rateLimitLogAtByRoute = new Map<string, number>();

  constructor(
    @InjectThrottlerOptions() options: ThrottlerModuleOptions,
    @InjectThrottlerStorage() storageService: ThrottlerStorage,
    reflector: Reflector,
    private readonly jwtService: JwtService,
  ) {
    super(options, storageService, reflector);
  }

  protected async getTracker(req: RateLimitRequest): Promise<string> {
    return this.getPrincipalTracker(req);
  }

  protected generateKey(
    context: ExecutionContext,
    suffix: string,
    name: string,
  ): string {
    const { req } = this.getRequestResponse(context);
    const method = (this.stringClaim(req?.method) || 'UNKNOWN').toUpperCase();
    const routePath = this.routePath(req);
    // Keep endpoint isolation literal and durable instead of depending on
    // controller/handler names. Hash the complete value before storage so the
    // verified user id and trusted-IP digest are never stored as plain text.
    return this.hashTrackerValue(`${name}:${method}:${routePath}:${suffix}`);
  }

  protected async throwThrottlingException(
    context: ExecutionContext,
    throttlerLimitDetail: ThrottlerLimitDetail,
  ): Promise<void> {
    const { req, res } = this.getRequestResponse(context);
    const retryAfterSeconds = Math.max(
      1,
      Math.ceil(
        Math.max(
          throttlerLimitDetail.timeToBlockExpire,
          throttlerLimitDetail.timeToExpire,
        ) / 1000,
      ),
    );
    // Header chuẩn giúp mọi client dùng chung một cooldown thay vì tiếp tục
    // poll trong khi các bucket có hậu tố của Nest vẫn đang bị khóa.
    res.header('Retry-After', String(retryAfterSeconds));
    res.header('Cache-Control', 'no-store');

    const method = this.stringClaim(req?.method) || 'UNKNOWN';
    const route = this.stringClaim(req?.route?.path) || 'unknown';
    const logKey = `${method}:${route}`;
    const now = Date.now();
    const lastLoggedAt = this.rateLimitLogAtByRoute.get(logKey) ?? 0;
    if (now - lastLoggedAt >= 15_000) {
      this.rateLimitLogAtByRoute.set(logKey, now);
      this.logger.warn(
        `API rate limit activated method=${method} route=${route} retryAfterSeconds=${retryAfterSeconds}`,
      );
    }

    return super.throwThrottlingException(context, throttlerLimitDetail);
  }

  protected async getPrincipalTracker(req: RateLimitRequest): Promise<string> {
    const trustedIpHash = await this.trustedIpHash(req);
    const authorization = this.valueFromRecord(req.headers, 'authorization');
    const token = this.bearerToken(authorization);
    if (token) {
      try {
        const claims =
          await this.jwtService.verifyAsync<RateLimitJwtClaims>(token);
        const userId = this.stringClaim(claims.sub);
        if (userId) {
          return `principal:user:${userId}:ip:${trustedIpHash}`;
        }
      } catch {
        // Invalid or expired tokens continue through the non-JWT trackers.
      }
    }

    const email = this.emailIdentifier(req);
    if (email) {
      return `principal:email:${this.hashTrackerValue(email)}`;
    }

    return `principal:ip:${trustedIpHash}`;
  }

  private async trustedIpHash(req: RateLimitRequest): Promise<string> {
    // Express resolves req.ip from the single trusted Caddy hop configured in
    // main.ts. Hash it before it enters a throttler key so Redis and logs never
    // receive a raw client address.
    return this.hashTrackerValue(await super.getTracker(req));
  }

  private emailIdentifier(req: RateLimitRequest): string | null {
    const email = this.firstUsableValue([
      this.valueFromRecord(this.bodyRecord(req.body), 'email'),
      this.valueFromRecord(req.query, 'email'),
    ]);
    return email?.toLowerCase() ?? null;
  }

  private routePath(req: RateLimitRequest): string {
    const routeTemplate = this.stringClaim(req?.route?.path);
    if (routeTemplate) return routeTemplate.split('?')[0];
    const requestPath = this.firstUsableValue([req?.path, req?.originalUrl]);
    return requestPath?.split('?')[0] || 'unknown';
  }

  private valueFromRecord(
    record: Record<string, unknown> | undefined,
    key: string,
  ): unknown {
    return record?.[key];
  }

  private bodyRecord(body: unknown): Record<string, unknown> | undefined {
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return undefined;
    }
    return body as Record<string, unknown>;
  }

  private firstUsableValue(values: unknown[]): string | null {
    for (const value of values) {
      const normalized = this.stringClaim(value);
      if (normalized && normalized.length <= 128) return normalized;
    }
    return null;
  }

  private bearerToken(value: unknown): string | null {
    const authorization = this.stringClaim(value);
    if (typeof authorization !== 'string') return null;
    const match = authorization.match(/^Bearer\s+(.+)$/i);
    return match?.[1]?.trim() || null;
  }

  private stringClaim(value: unknown): string | null {
    const raw: unknown = Array.isArray(value) ? value[0] : value;
    if (typeof raw !== 'string') return null;
    const normalized = raw.trim();
    return normalized || null;
  }

  private hashTrackerValue(value: string) {
    return createHash('sha256').update(value).digest('hex');
  }
}
