import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import type { User } from '@prisma/client';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { getRequiredEnv } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';
import {
  AuthSessionService,
  type AuthSessionClaims,
  type AuthSessionSnapshot,
} from './auth-session.service';

type AuthSnapshotRow = User & {
  authSessionId: string | null;
  authSessionUserId: string | null;
  authSessionPlatform: string | null;
  authSessionVersion: number | null;
  authSessionRevokedAt: Date | null;
  authSessionExpiresAt: Date | null;
};

type ValidatedJwtPrincipal = User & {
  authSession: AuthSessionClaims;
};

const AUTH_VALIDATION_BATCH_DELAY_MS = 2;
const MAX_PENDING_AUTH_VALIDATION_BATCHES = 5_000;

type PendingAuthValidationBatch = {
  callers: number;
  validation: Promise<ValidatedJwtPrincipal>;
};

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  private readonly logger = new Logger(JwtStrategy.name);
  private readonly pendingValidationBatches = new Map<
    string,
    PendingAuthValidationBatch
  >();

  constructor(
    private prisma: PrismaService,
    private authSessionService: AuthSessionService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: getRequiredEnv('JWT_SECRET'),
    });
  }

  async validate(payload: any): Promise<ValidatedJwtPrincipal> {
    const batchKey = this.validationBatchKey(payload);
    if (!batchKey) {
      return this.cloneValidatedPrincipal(await this.validateSnapshot(payload));
    }

    const pending = this.pendingValidationBatches.get(batchKey);
    if (pending) {
      pending.callers += 1;
      return this.cloneValidatedPrincipal(await pending.validation);
    }
    if (
      this.pendingValidationBatches.size >= MAX_PENDING_AUTH_VALIDATION_BATCHES
    ) {
      return this.cloneValidatedPrincipal(await this.validateSnapshot(payload));
    }

    const batch = {} as PendingAuthValidationBatch;
    batch.callers = 1;
    let validation: Promise<ValidatedJwtPrincipal>;
    validation = new Promise<void>((resolve) => {
      setTimeout(resolve, AUTH_VALIDATION_BATCH_DELAY_MS);
    }).then(() => {
      if (this.pendingValidationBatches.get(batchKey) === batch) {
        this.pendingValidationBatches.delete(batchKey);
        if (batch.callers > 1) {
          this.logger.debug(
            `Auth validation pre-query batch closed: callers=${batch.callers} pendingBatches=${this.pendingValidationBatches.size}`,
          );
        }
      }
      return this.validateSnapshot(payload);
    });
    batch.validation = validation;
    this.pendingValidationBatches.set(batchKey, batch);
    return this.cloneValidatedPrincipal(await validation);
  }

  private async validateSnapshot(payload: any): Promise<ValidatedJwtPrincipal> {
    const userId = typeof payload?.sub === 'string' ? payload.sub : '';
    const sessionId = this.stringClaim(payload?.sessionId);

    const [snapshot] = await this.prisma.$queryRaw<AuthSnapshotRow[]>`
      SELECT
        authenticated_user.*,
        platform_session.id AS "authSessionId",
        platform_session."userId" AS "authSessionUserId",
        platform_session.platform AS "authSessionPlatform",
        platform_session."sessionVersion" AS "authSessionVersion",
        platform_session."revokedAt" AS "authSessionRevokedAt",
        platform_session."expiresAt" AS "authSessionExpiresAt"
      FROM "User" authenticated_user
      LEFT JOIN "UserPlatformSession" platform_session
        ON platform_session.id = ${sessionId ?? ''}
      WHERE authenticated_user.id = ${userId}
      LIMIT 1
    `;

    if (!snapshot) {
      throw new UnauthorizedException();
    }
    if (snapshot.status === 'no') {
      throw new UnauthorizedException();
    }
    const payloadTokenVersion = Number.isInteger(payload?.tokenVersion)
      ? payload.tokenVersion
      : 0;
    if ((snapshot.tokenVersion ?? 0) !== payloadTokenVersion) {
      throw new UnauthorizedException();
    }
    const {
      authSessionId,
      authSessionPlatform,
      authSessionVersion,
      authSessionUserId: _authSessionUserId,
      authSessionRevokedAt: _authSessionRevokedAt,
      authSessionExpiresAt: _authSessionExpiresAt,
      ...user
    } = snapshot;
    const session: AuthSessionSnapshot | null = authSessionId
      ? {
          id: authSessionId,
          userId: _authSessionUserId!,
          platform: authSessionPlatform!,
          sessionVersion: authSessionVersion!,
          revokedAt: _authSessionRevokedAt,
          expiresAt: _authSessionExpiresAt!,
        }
      : null;
    const authSession = this.authSessionService.validateJwtSessionSnapshot(
      snapshot.id,
      payload,
      session,
    );

    return {
      ...user,
      authSession,
    };
  }

  private stringClaim(value: unknown) {
    return typeof value === 'string' && value.trim() ? value.trim() : null;
  }

  private validationBatchKey(payload: any) {
    const userId = this.nonEmptyExactString(payload?.sub);
    const sessionId = this.stringClaim(payload?.sessionId);
    const platform = this.stringClaim(payload?.platform);
    const sessionVersion = Number.isInteger(payload?.sessionVersion)
      ? payload.sessionVersion
      : null;
    if (!userId || !sessionId || !platform || sessionVersion == null) {
      return null;
    }
    return JSON.stringify([
      'prequery-v1',
      userId,
      Number.isInteger(payload?.tokenVersion) ? payload.tokenVersion : 0,
      Number.isInteger(payload?.accessVersion) ? payload.accessVersion : 0,
      sessionId,
      platform,
      sessionVersion,
    ]);
  }

  private nonEmptyExactString(value: unknown) {
    return typeof value === 'string' && value.trim() ? value : null;
  }

  private cloneValidatedPrincipal(
    principal: ValidatedJwtPrincipal,
  ): ValidatedJwtPrincipal {
    return {
      ...principal,
      profileCompletedAt: principal.profileCompletedAt
        ? new Date(principal.profileCompletedAt)
        : null,
      branchLockedAt: principal.branchLockedAt
        ? new Date(principal.branchLockedAt)
        : null,
      createdAt: new Date(principal.createdAt),
      updatedAt: new Date(principal.updatedAt),
      authSession: { ...principal.authSession },
    };
  }
}
