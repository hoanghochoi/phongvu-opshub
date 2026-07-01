import { Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { createHash } from 'crypto';
import {
  InjectThrottlerOptions,
  InjectThrottlerStorage,
  ThrottlerGuard,
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
    const authorization = this.valueFromRecord(req.headers, 'authorization');
    const token = this.bearerToken(authorization);
    if (token) {
      try {
        const claims =
          await this.jwtService.verifyAsync<RateLimitJwtClaims>(token);
        const userId = this.stringClaim(claims.sub);
        if (userId) return `user:${userId}`;
      } catch {
        // Invalid or expired tokens continue through the non-JWT trackers.
      }
    }

    const clientId = this.clientIdentifier(req);
    if (clientId) return `client:${this.hashTrackerValue(clientId)}`;

    const email = this.emailIdentifier(req);
    if (email) return `user-email:${this.hashTrackerValue(email)}`;

    return `ip:${await super.getTracker(req)}`;
  }

  private clientIdentifier(req: RateLimitRequest): string | null {
    return this.firstUsableValue([
      this.valueFromRecord(req.headers, 'x-opshub-client-id'),
      this.valueFromRecord(req.headers, 'x-client-id'),
      this.valueFromRecord(req.headers, 'x-device-id'),
      this.valueFromRecord(req.query, 'clientId'),
      this.valueFromRecord(req.query, 'deviceId'),
      this.valueFromRecord(this.bodyRecord(req.body), 'clientId'),
      this.valueFromRecord(this.bodyRecord(req.body), 'deviceId'),
    ]);
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
