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
  authRequestIndex: number;
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

type AuthValidationPayload = {
  sub?: unknown;
  tokenVersion?: unknown;
  sessionId?: unknown;
  platform?: unknown;
  sessionVersion?: unknown;
};

type PendingAuthValidationRequest = {
  payload: AuthValidationPayload;
  resolve: (principal: ValidatedJwtPrincipal) => void;
  reject: (reason?: unknown) => void;
};

type AuthSnapshotRequest = {
  index: number;
  payload: AuthValidationPayload;
};

const AUTH_VALIDATION_BATCH_DELAY_MS = 2;
const MAX_PENDING_AUTH_VALIDATION_REQUESTS = 5_000;

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  private readonly logger = new Logger(JwtStrategy.name);
  private pendingValidationBatch: PendingAuthValidationRequest[] | null = null;

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
    const requestPayload = this.validationPayload(payload);

    return new Promise<ValidatedJwtPrincipal>((resolve, reject) => {
      const batch = this.pendingValidationBatch;
      if (batch && batch.length < MAX_PENDING_AUTH_VALIDATION_REQUESTS) {
        batch.push({ payload: requestPayload, resolve, reject });
        return;
      }

      if (batch) {
        void this.validateSnapshot(requestPayload).then(
          (principal) => resolve(this.cloneValidatedPrincipal(principal)),
          reject,
        );
        return;
      }

      const newBatch: PendingAuthValidationRequest[] = [
        { payload: requestPayload, resolve, reject },
      ];
      this.pendingValidationBatch = newBatch;
      setTimeout(() => {
        if (this.pendingValidationBatch === newBatch) {
          this.pendingValidationBatch = null;
        }
        void this.validatePendingBatch(newBatch);
      }, AUTH_VALIDATION_BATCH_DELAY_MS);
    });
  }

  private async validatePendingBatch(
    batch: PendingAuthValidationRequest[],
  ): Promise<void> {
    let rows: AuthSnapshotRow[];
    try {
      rows = await this.querySnapshots(
        batch.map((entry, index) => ({
          index,
          payload: entry.payload,
        })),
      );
    } catch (error) {
      batch.forEach((entry) => entry.reject(error));
      return;
    }

    const rowsByIndex = new Map(rows.map((row) => [row.authRequestIndex, row]));
    batch.forEach((entry, index) => {
      try {
        const principal = this.validateSnapshotRow(
          entry.payload,
          rowsByIndex.get(index),
        );
        entry.resolve(this.cloneValidatedPrincipal(principal));
      } catch (error) {
        entry.reject(error);
      }
    });

    if (batch.length > 1) {
      this.logger.debug(
        `Auth validation pre-query batch closed: callers=${batch.length} pendingRequests=${this.pendingValidationBatch?.length ?? 0}`,
      );
    }
  }

  private async validateSnapshot(
    payload: AuthValidationPayload,
  ): Promise<ValidatedJwtPrincipal> {
    const [row] = await this.querySnapshots([{ index: 0, payload }]);
    return this.validateSnapshotRow(payload, row);
  }

  private async querySnapshots(
    requests: AuthSnapshotRequest[],
  ): Promise<AuthSnapshotRow[]> {
    const encodedRequests = JSON.stringify(
      requests.map(({ index, payload }) => ({
        authRequestIndex: index,
        userId: typeof payload.sub === 'string' ? payload.sub : '',
        sessionId: this.stringClaim(payload.sessionId) ?? '',
      })),
    );

    return this.prisma.$queryRaw<AuthSnapshotRow[]>`
      WITH requested AS (
        SELECT *
        FROM jsonb_to_recordset(${encodedRequests}::jsonb)
          AS input("authRequestIndex" integer, "userId" text, "sessionId" text)
      )
      SELECT
        input."authRequestIndex" AS "authRequestIndex",
        authenticated_user.*,
        platform_session.id AS "authSessionId",
        platform_session."userId" AS "authSessionUserId",
        platform_session.platform AS "authSessionPlatform",
        platform_session."sessionVersion" AS "authSessionVersion",
        platform_session."revokedAt" AS "authSessionRevokedAt",
        platform_session."expiresAt" AS "authSessionExpiresAt"
      FROM requested input
      JOIN "User" authenticated_user
        ON authenticated_user.id = input."userId"
      LEFT JOIN LATERAL (
        SELECT *
        FROM "UserPlatformSession" session_row
        WHERE session_row.id = input."sessionId"
        LIMIT 1
      ) platform_session ON TRUE
      ORDER BY input."authRequestIndex"
    `;
  }

  private validateSnapshotRow(
    payload: AuthValidationPayload,
    snapshot: AuthSnapshotRow | undefined,
  ): ValidatedJwtPrincipal {
    if (!snapshot) {
      throw new UnauthorizedException();
    }
    if (snapshot.status === 'no') {
      throw new UnauthorizedException();
    }
    const payloadTokenVersion = Number.isInteger(payload.tokenVersion)
      ? payload.tokenVersion
      : 0;
    if ((snapshot.tokenVersion ?? 0) !== payloadTokenVersion) {
      throw new UnauthorizedException();
    }
    const {
      authRequestIndex: _authRequestIndex,
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

  private validationPayload(payload: any): AuthValidationPayload {
    return {
      sub: payload?.sub,
      tokenVersion: payload?.tokenVersion,
      sessionId: payload?.sessionId,
      platform: payload?.platform,
      sessionVersion: payload?.sessionVersion,
    };
  }

  private stringClaim(value: unknown) {
    return typeof value === 'string' && value.trim() ? value.trim() : null;
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
