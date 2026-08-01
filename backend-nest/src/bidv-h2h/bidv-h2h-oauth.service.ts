import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { compare } from 'bcrypt';
import { createHash, randomBytes } from 'crypto';
import { getBidvH2hConfig } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { safeLogError } from '../common/log-sanitizer';

export type BidvClientPrincipal = {
  id: string;
  clientId: string;
  bankCode: string;
  scope: string;
};

@Injectable()
export class BidvH2hOauthService {
  private readonly logger = new Logger(BidvH2hOauthService.name);

  constructor(private readonly prisma: PrismaService) {}

  async issueToken(authorization: unknown) {
    const startedAt = Date.now();
    const credentials = this.parseBasicAuthorization(authorization);
    this.logger.log('BIDV OAuth token request started');
    try {
      const client = await (this.prisma as any).bankApiClient.findUnique({
        where: { clientId: credentials.clientId },
      });
      const valid =
        client &&
        client.bankCode === 'BIDV' &&
        client.scope === 'balance-changes:write' &&
        this.clientUsable(client) &&
        (await compare(credentials.clientSecret, client.secretHash));
      if (!valid) throw this.invalidClient();

      const token = randomBytes(32).toString('base64url');
      const config = getBidvH2hConfig();
      const expiresAt = new Date(Date.now() + config.tokenTtlSeconds * 1000);
      await (this.prisma as any).bankAccessToken.create({
        data: {
          clientRefId: client.id,
          tokenHash: this.hashToken(token),
          scope: client.scope,
          expiresAt,
        },
      });
      this.logger.log(
        `BIDV OAuth token request succeeded clientRef=${client.id} durationMs=${Date.now() - startedAt}`,
      );
      return {
        access_token: token,
        token_type: 'Bearer',
        expires_in: config.tokenTtlSeconds,
        scope: client.scope,
      };
    } catch (error) {
      this.logger.warn(
        `BIDV OAuth token request failed durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
      if (error instanceof UnauthorizedException) throw error;
      throw this.invalidClient();
    }
  }

  async authenticateBearer(
    authorization: unknown,
  ): Promise<BidvClientPrincipal> {
    const token = this.parseBearerAuthorization(authorization);
    const stored = await (this.prisma as any).bankAccessToken.findUnique({
      where: { tokenHash: this.hashToken(token) },
      include: { client: true },
    });
    if (
      !stored ||
      stored.revokedAt ||
      stored.expiresAt <= new Date() ||
      !this.clientUsable(stored.client) ||
      stored.scope !== 'balance-changes:write' ||
      stored.client?.bankCode !== 'BIDV'
    ) {
      throw this.invalidToken();
    }
    return {
      id: stored.client.id,
      clientId: stored.client.clientId,
      bankCode: stored.client.bankCode,
      scope: stored.scope,
    };
  }

  private parseBasicAuthorization(value: unknown) {
    const authorization = this.header(value);
    const match = authorization.match(/^Basic\s+([^\s]+)$/i);
    if (!match) throw this.invalidClient();
    let decoded: string;
    try {
      decoded = Buffer.from(match[1], 'base64').toString('utf8');
    } catch {
      throw this.invalidClient();
    }
    const separator = decoded.indexOf(':');
    if (separator <= 0) throw this.invalidClient();
    const clientId = decoded.slice(0, separator).trim();
    const clientSecret = decoded.slice(separator + 1);
    if (
      !clientId ||
      !clientSecret ||
      clientId.length > 200 ||
      clientSecret.length > 500
    ) {
      throw this.invalidClient();
    }
    return { clientId, clientSecret };
  }

  private parseBearerAuthorization(value: unknown) {
    const authorization = this.header(value);
    const match = authorization.match(/^Bearer\s+([^\s]+)$/i);
    if (!match || match[1].length > 1000) throw this.invalidToken();
    return match[1];
  }

  private header(value: unknown) {
    const normalized = Array.isArray(value) ? value[0] : value;
    return typeof normalized === 'string' ? normalized.trim() : '';
  }

  private clientUsable(client: any) {
    const now = new Date();
    return (
      client?.status === 'ACTIVE' &&
      !client.revokedAt &&
      (!client.overlapExpiresAt || client.overlapExpiresAt > now)
    );
  }

  private hashToken(token: string) {
    return createHash('sha256').update(token).digest('hex');
  }

  private invalidClient() {
    return new UnauthorizedException({
      error: 'invalid_client',
      error_description: 'Thông tin kết nối không hợp lệ.',
    });
  }

  private invalidToken() {
    return new UnauthorizedException({
      error: 'invalid_token',
      error_description: 'Phiên kết nối không hợp lệ hoặc đã hết hạn.',
    });
  }
}
