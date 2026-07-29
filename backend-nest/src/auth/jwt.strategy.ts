import { Injectable, UnauthorizedException } from '@nestjs/common';
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

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
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
}
