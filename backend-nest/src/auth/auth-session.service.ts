import {
  BadRequestException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { createHash } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';

export const AUTH_PLATFORMS = [
  'windows',
  'android',
  'ios',
  'macos',
  'linux',
  'web',
] as const;

export type AuthPlatform = (typeof AUTH_PLATFORMS)[number];

export type AuthDeviceContext = {
  platform: string;
  deviceId: string;
  deviceLabel?: string | null;
  appVersion?: string | null;
  buildNumber?: string | null;
};

export type AuthSessionClaims = {
  sessionId: string;
  platform: AuthPlatform;
  sessionVersion: number;
};

const SESSION_TTL_DAYS = 7;
const SESSION_REPLACED_MESSAGE =
  'Tai khoan da dang nhap tren thiet bi khac cung nen tang. Vui long dang nhap lai.';

@Injectable()
export class AuthSessionService {
  private readonly logger = new Logger(AuthSessionService.name);

  constructor(private prisma: PrismaService) {}

  async replacePlatformSession(
    user: { id: string; email?: string | null },
    device: AuthDeviceContext,
  ): Promise<AuthSessionClaims> {
    const normalized = this.normalizeDevice(device);
    const now = new Date();
    const expiresAt = this.sessionExpiresAt(now);
    const deviceIdHash = this.hashDeviceId(normalized.deviceId);

    const session = await this.prisma.userPlatformSession.upsert({
      where: {
        userId_platform: { userId: user.id, platform: normalized.platform },
      },
      create: {
        userId: user.id,
        platform: normalized.platform,
        sessionVersion: 1,
        deviceIdHash,
        deviceLabel: normalized.deviceLabel,
        appVersion: normalized.appVersion,
        buildNumber: normalized.buildNumber,
        lastLoginAt: now,
        expiresAt,
      },
      update: {
        sessionVersion: { increment: 1 },
        deviceIdHash,
        deviceLabel: normalized.deviceLabel,
        appVersion: normalized.appVersion,
        buildNumber: normalized.buildNumber,
        lastLoginAt: now,
        expiresAt,
        revokedAt: null,
        revokedReason: null,
      },
    });

    this.logger.log(
      `Auth platform session issued: userId=${user.id} email=${user.email || 'unknown'} platform=${session.platform} sessionVersion=${session.sessionVersion} deviceHashPrefix=${deviceIdHash.slice(0, 10)}`,
    );

    return {
      sessionId: session.id,
      platform: session.platform as AuthPlatform,
      sessionVersion: session.sessionVersion,
    };
  }

  async validateJwtSession(
    userId: string,
    payload: any,
  ): Promise<AuthSessionClaims> {
    const sessionId = this.stringClaim(payload.sessionId);
    const platform = this.stringClaim(payload.platform);
    const sessionVersion = Number.isInteger(payload.sessionVersion)
      ? payload.sessionVersion
      : null;
    if (!sessionId || !platform || sessionVersion == null) {
      this.logger.warn(
        `Auth session rejected: userId=${userId} reason=missing_claims`,
      );
      throw new UnauthorizedException(SESSION_REPLACED_MESSAGE);
    }
    if (!this.isAllowedPlatform(platform)) {
      this.logger.warn(
        `Auth session rejected: userId=${userId} platform=${platform} reason=invalid_platform`,
      );
      throw new UnauthorizedException(SESSION_REPLACED_MESSAGE);
    }

    const session = await this.prisma.userPlatformSession.findUnique({
      where: { id: sessionId },
    });
    const reason = this.invalidSessionReason(
      session,
      userId,
      platform,
      sessionVersion,
    );
    if (reason) {
      this.logger.warn(
        `Auth session rejected: userId=${userId} platform=${platform} sessionId=${sessionId} reason=${reason}`,
      );
      throw new UnauthorizedException(SESSION_REPLACED_MESSAGE);
    }

    return {
      sessionId: session!.id,
      platform: session!.platform as AuthPlatform,
      sessionVersion: session!.sessionVersion,
    };
  }

  async revokeCurrentSession(
    userId: string,
    claims: AuthSessionClaims,
    reason = 'LOGOUT',
  ): Promise<{ ok: true }> {
    await this.prisma.userPlatformSession.updateMany({
      where: {
        id: claims.sessionId,
        userId,
        platform: claims.platform,
        sessionVersion: claims.sessionVersion,
        revokedAt: null,
      },
      data: { revokedAt: new Date(), revokedReason: reason },
    });
    this.logger.log(
      `Auth session revoked: userId=${userId} platform=${claims.platform} sessionVersion=${claims.sessionVersion} reason=${reason}`,
    );
    return { ok: true };
  }

  async revokeAllUserSessions(
    userId: string,
    reason: string,
    now = new Date(),
  ) {
    await this.prisma.userPlatformSession.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: now, revokedReason: reason },
    });
    this.logger.log(`Auth sessions revoked: userId=${userId} reason=${reason}`);
  }

  normalizeDevice(device: AuthDeviceContext): Required<AuthDeviceContext> & {
    platform: AuthPlatform;
  } {
    const platform = String(device.platform || '')
      .trim()
      .toLowerCase();
    if (!this.isAllowedPlatform(platform)) {
      throw new BadRequestException('Nen tang dang nhap khong hop le.');
    }
    const deviceId = String(device.deviceId || '').trim();
    if (deviceId.length < 8 || deviceId.length > 128) {
      throw new BadRequestException('Ma thiet bi dang nhap khong hop le.');
    }
    return {
      platform,
      deviceId,
      deviceLabel: this.cleanOptional(device.deviceLabel, 120),
      appVersion: this.cleanOptional(device.appVersion, 40),
      buildNumber: this.cleanOptional(device.buildNumber, 40),
    };
  }

  private invalidSessionReason(
    session: any,
    userId: string,
    platform: string,
    sessionVersion: number,
  ): string | null {
    if (!session) return 'missing_session';
    if (session.userId !== userId) return 'user_mismatch';
    if (session.platform !== platform) return 'platform_mismatch';
    if (session.sessionVersion !== sessionVersion) return 'version_mismatch';
    if (session.revokedAt) return 'revoked';
    if (session.expiresAt?.getTime?.() < Date.now()) return 'expired';
    return null;
  }

  private sessionExpiresAt(now: Date) {
    return new Date(now.getTime() + SESSION_TTL_DAYS * 24 * 60 * 60 * 1000);
  }

  private hashDeviceId(deviceId: string) {
    return createHash('sha256').update(deviceId).digest('hex');
  }

  private isAllowedPlatform(value: string): value is AuthPlatform {
    return (AUTH_PLATFORMS as readonly string[]).includes(value);
  }

  private stringClaim(value: unknown) {
    return typeof value === 'string' && value.trim() ? value.trim() : null;
  }

  private cleanOptional(value: unknown, maxLength: number) {
    const text = typeof value === 'string' ? value.trim() : '';
    return text ? text.slice(0, maxLength) : null;
  }
}
