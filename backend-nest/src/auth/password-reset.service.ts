import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { createHash, randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { OpshubMailService } from './opshub-mail.service';
import { assertPasswordPolicy } from './password-policy';

const PASSWORD_RESET_PURPOSE = 'PASSWORD_RESET';
const RESET_TOKEN_BYTES = 32;
const RESET_TOKEN_SALT_ROUNDS = 12;
const RESET_TOKEN_MAX_ATTEMPTS = 5;
const DEFAULT_RESET_TTL_MINUTES = 30;

type ResetSource = 'SELF_SERVICE' | 'SUPER_ADMIN';

type ResetUser = {
  id: string;
  email: string;
  firstName?: string | null;
  status?: string | null;
};

type ResetActor = {
  id?: string | null;
  email?: string | null;
};

@Injectable()
export class PasswordResetService {
  private readonly logger = new Logger(PasswordResetService.name);

  constructor(
    private prisma: PrismaService,
    private mailService: OpshubMailService,
  ) {}

  async sendResetLinkForEmail(email: string): Promise<{
    ok: true;
    expiresInMinutes: number;
  }> {
    const user = await this.prisma.user.findUnique({
      where: { email },
      select: { id: true, email: true, firstName: true, status: true },
    });

    if (!user) {
      this.logger.warn(`Password reset requested for missing email=${email}`);
      return this.genericResponse();
    }

    await this.sendResetLinkForUser(user, { source: 'SELF_SERVICE' });
    return this.genericResponse();
  }

  async sendResetLinkForUserId(
    userId: string,
    actor: ResetActor,
  ): Promise<{ ok: true; expiresInMinutes: number }> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, email: true, firstName: true, status: true },
    });
    if (!user) throw new NotFoundException('Khong tim thay user');

    await this.sendResetLinkForUser(user, {
      source: 'SUPER_ADMIN',
      actor,
    });
    return this.genericResponse();
  }

  async resetPassword(token: string, newPassword: string) {
    const tokenHash = this.hashToken(token);
    const record = await this.prisma.passwordResetToken.findUnique({
      where: { tokenHash },
      include: { user: { include: { store: true } } },
    });

    if (!record) {
      throw this.invalidTokenError();
    }
    if (record.consumedAt || record.expiresAt.getTime() < Date.now()) {
      throw this.invalidTokenError();
    }
    if (record.attempts >= RESET_TOKEN_MAX_ATTEMPTS) {
      throw new BadRequestException(
        'Link doi mat khau da bi khoa do thu sai qua nhieu lan.',
      );
    }

    try {
      assertPasswordPolicy(newPassword);
    } catch (error) {
      await this.prisma.passwordResetToken.update({
        where: { id: record.id },
        data: { attempts: { increment: 1 } },
      });
      throw error;
    }

    const password = await bcrypt.hash(newPassword, RESET_TOKEN_SALT_ROUNDS);
    const consumedAt = new Date();

    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: record.userId },
        data: {
          password,
          tokenVersion: { increment: 1 },
        },
      });
      await tx.userPlatformSession.updateMany({
        where: { userId: record.userId, revokedAt: null },
        data: { revokedAt: consumedAt, revokedReason: 'PASSWORD_RESET' },
      });
      await tx.passwordResetToken.update({
        where: { id: record.id },
        data: { consumedAt },
      });
      await tx.passwordResetToken.updateMany({
        where: {
          userId: record.userId,
          purpose: PASSWORD_RESET_PURPOSE,
          consumedAt: null,
          id: { not: record.id },
        },
        data: { consumedAt },
      });
    });

    this.logger.log(
      `Password reset completed: userId=${record.userId} email=${record.email} source=${record.source}`,
    );
    return { ok: true };
  }

  private async sendResetLinkForUser(
    user: ResetUser,
    options: { source: ResetSource; actor?: ResetActor },
  ) {
    const ttlMinutes = this.ttlMinutes();
    const token = this.generateToken();
    const tokenHash = this.hashToken(token);
    const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000);
    const invalidatedAt = new Date();

    await this.prisma.$transaction(async (tx) => {
      await tx.passwordResetToken.updateMany({
        where: {
          userId: user.id,
          purpose: PASSWORD_RESET_PURPOSE,
          consumedAt: null,
        },
        data: { consumedAt: invalidatedAt },
      });
      await tx.passwordResetToken.create({
        data: {
          userId: user.id,
          email: user.email,
          purpose: PASSWORD_RESET_PURPOSE,
          tokenHash,
          expiresAt,
          source: options.source,
          createdByUserId: options.actor?.id || null,
          createdByEmail: options.actor?.email || null,
        },
      });
    });

    const link = this.resetLink(token);
    await this.mailService.sendMail({
      to: user.email,
      subject: 'Doi mat khau OpsHub',
      text:
        `Xin chao ${user.firstName || user.email},\n\n` +
        `Bam link sau de doi mat khau OpsHub. Link het han sau ${ttlMinutes} phut:\n` +
        `${link}\n\n` +
        'Neu ban khong yeu cau doi mat khau, vui long bo qua email nay.',
      html:
        `<p>Xin chao ${this.escapeHtml(user.firstName || user.email)},</p>` +
        `<p>Bam link sau de doi mat khau OpsHub. Link het han sau ${ttlMinutes} phut.</p>` +
        `<p><a href="${link}">Doi mat khau OpsHub</a></p>` +
        '<p>Neu ban khong yeu cau doi mat khau, vui long bo qua email nay.</p>',
    });

    this.logger.log(
      `Password reset link sent: userId=${user.id} email=${user.email} source=${options.source} actor=${options.actor?.email || 'self'}`,
    );
  }

  private genericResponse() {
    return { ok: true as const, expiresInMinutes: this.ttlMinutes() };
  }

  private ttlMinutes() {
    const raw = Number(process.env.PASSWORD_RESET_TTL_MINUTES || '');
    if (Number.isInteger(raw) && raw >= 5 && raw <= 1440) return raw;
    return DEFAULT_RESET_TTL_MINUTES;
  }

  private generateToken() {
    return randomBytes(RESET_TOKEN_BYTES).toString('base64url');
  }

  private hashToken(token: string) {
    return createHash('sha256').update(token).digest('hex');
  }

  private resetLink(token: string) {
    const base =
      process.env.PUBLIC_BASE_URL?.trim() ||
      process.env.OPSHUB_PUBLIC_BASE_URL?.trim() ||
      'http://localhost:3000';
    const url = new URL('/reset-password', base);
    url.searchParams.set('token', token);
    return url.toString();
  }

  private invalidTokenError() {
    return new BadRequestException(
      'Link doi mat khau khong hop le hoac da het han.',
    );
  }

  private escapeHtml(value: string) {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }
}
