import { Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { createHash } from 'crypto';
import {
  InjectThrottlerOptions,
  InjectThrottlerStorage,
  ThrottlerGuard,
  ThrottlerRequest,
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
};

@Injectable()
export class UserAwareThrottlerGuard extends ThrottlerGuard {
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

  protected async handleRequest(
    requestProps: ThrottlerRequest,
  ): Promise<boolean> {
    const getTracker =
      requestProps.throttler.name === 'ip'
        ? (req: RateLimitRequest) => this.getIpTracker(req)
        : (req: RateLimitRequest) => this.getPrincipalTracker(req);
    return super.handleRequest({ ...requestProps, getTracker });
  }

  protected async getIpTracker(req: RateLimitRequest): Promise<string> {
    return `ip:${await super.getTracker(req)}`;
  }

  protected async getPrincipalTracker(
    req: RateLimitRequest,
  ): Promise<string> {
    const authorization = this.valueFromRecord(req.headers, 'authorization');
    const token = this.bearerToken(authorization);
    if (token) {
      try {
        const claims =
          await this.jwtService.verifyAsync<RateLimitJwtClaims>(token);
        const userId = this.stringClaim(claims.sub);
        if (userId) return `principal:user:${userId}`;
      } catch {
        // Invalid or expired tokens continue through the non-JWT trackers.
      }
    }

    const email = this.emailIdentifier(req);
    if (email) {
      return `principal:email:${this.hashTrackerValue(email)}`;
    }

    return `principal:${await this.getIpTracker(req)}`;
  }

  private emailIdentifier(req: RateLimitRequest): string | null {
    const email = this.firstUsableValue([
      this.valueFromRecord(req.query, 'email'),
      this.valueFromRecord(this.bodyRecord(req.body), 'email'),
    ]);
    return email?.toLowerCase() ?? null;
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
    return createHash('sha256').update(value).digest('hex').slice(0, 32);
  }
}
