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
const RESET_CODE_TTL_MINUTES = 10;
const RESET_CODE_SALT_ROUNDS = 10;
const RESET_CODE_MAX_ATTEMPTS = 5;
const RESET_TOKEN_BYTES = 32;
const RESET_TOKEN_SALT_ROUNDS = 12;
const RESET_TOKEN_MAX_ATTEMPTS = 5;

type ResetActor = {
  id?: string | null;
  email?: string | null;
};

type ResetUser = {
  id: string;
  email: string;
  firstName?: string | null;
  status?: string | null;
};

@Injectable()
export class PasswordResetService {
  private readonly logger = new Logger(PasswordResetService.name);

  constructor(
    private prisma: PrismaService,
    private mailService: OpshubMailService,
  ) {}

  async sendResetCodeForEmail(email: string): Promise<{
    ok: true;
    expiresInMinutes: number;
  }> {
    const user = await this.prisma.user.findUnique({
      where: { email },
      select: { id: true, email: true, firstName: true, status: true },
    });

    if (!user) {
      this.logger.warn(`Password reset requested for missing email=${email}`);
      throw new NotFoundException(
        'Email này chưa có tài khoản OpsHub. Vui lòng đăng ký tài khoản trước.',
      );
    }

    await this.sendResetCodeForUser(user);
    return this.genericCodeResponse();
  }

  async verifyResetCode(
    email: string,
    code: string,
  ): Promise<{ ok: true; resetToken: string; expiresInMinutes: number }> {
    this.logger.log(`Password reset code verification started: email=${email}`);
    const record = await this.prisma.emailVerificationCode.findFirst({
      where: {
        email,
        purpose: PASSWORD_RESET_PURPOSE,
        consumedAt: null,
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!record) {
      this.logger.warn(
        `Password reset code verification failed: email=${email} reason=missing_code`,
      );
      throw new BadRequestException('Vui lòng gửi mã xác thực trước.');
    }

    if (record.expiresAt.getTime() < Date.now()) {
      this.logger.warn(
        `Password reset code verification failed: email=${email} reason=expired`,
      );
      throw new BadRequestException('Mã xác thực đã hết hạn.');
    }

    if (record.attempts >= RESET_CODE_MAX_ATTEMPTS) {
      this.logger.warn(
        `Password reset code verification failed: email=${email} reason=max_attempts attempts=${record.attempts}`,
      );
      throw new BadRequestException(
        'Mã xác thực đã bị khóa do nhập sai quá nhiều lần.',
      );
    }

    const isValid = await bcrypt.compare(code, record.codeHash);
    if (!isValid) {
      await this.prisma.emailVerificationCode.update({
        where: { id: record.id },
        data: { attempts: { increment: 1 } },
      });
      this.logger.warn(
        `Password reset code verification failed: email=${email} reason=invalid_code attempts=${record.attempts + 1}`,
      );
      throw new BadRequestException('Mã xác thực không đúng.');
    }

    const user = await this.prisma.user.findUnique({
      where: { email },
      select: { id: true, email: true },
    });
    if (!user) {
      this.logger.warn(
        `Password reset code verification failed: email=${email} reason=missing_user_after_code`,
      );
      throw new BadRequestException('Không thể đổi mật khẩu cho email này.');
    }

    const resetToken = this.generateToken();
    const tokenHash = this.hashToken(resetToken);
    const expiresAt = this.expiresAt();
    const consumedAt = new Date();

    await this.prisma.$transaction(async (tx) => {
      await tx.emailVerificationCode.update({
        where: { id: record.id },
        data: { consumedAt },
      });
      await tx.passwordResetToken.updateMany({
        where: {
          userId: user.id,
          purpose: PASSWORD_RESET_PURPOSE,
          consumedAt: null,
        },
        data: { consumedAt },
      });
      await tx.passwordResetToken.create({
        data: {
          userId: user.id,
          email: user.email,
          purpose: PASSWORD_RESET_PURPOSE,
          tokenHash,
          expiresAt,
          source: 'SELF_SERVICE',
        },
      });
    });

    this.logger.log(
      `Password reset code verified: userId=${user.id} email=${email}`,
    );
    return {
      ok: true,
      resetToken,
      expiresInMinutes: RESET_CODE_TTL_MINUTES,
    };
  }

  async resetPassword(token: string, newPassword: string) {
    const tokenHash = this.hashToken(token);
    this.logger.log('Password reset started');
    const record = await this.prisma.passwordResetToken.findUnique({
      where: { tokenHash },
      include: { user: { include: { store: true } } },
    });

    if (!record) {
      this.logger.warn('Password reset failed: reason=missing_token');
      throw this.invalidTokenError();
    }
    if (record.consumedAt || record.expiresAt.getTime() < Date.now()) {
      this.logger.warn(
        `Password reset failed: userId=${record.userId} source=${record.source} reason=${record.consumedAt ? 'consumed' : 'expired'}`,
      );
      throw this.invalidTokenError();
    }
    if (record.attempts >= RESET_TOKEN_MAX_ATTEMPTS) {
      this.logger.warn(
        `Password reset failed: userId=${record.userId} source=${record.source} reason=max_attempts attempts=${record.attempts}`,
      );
      throw new BadRequestException(
        'Phiên đổi mật khẩu đã bị khóa do thử sai quá nhiều lần.',
      );
    }

    try {
      assertPasswordPolicy(newPassword);
    } catch (error) {
      await this.prisma.passwordResetToken.update({
        where: { id: record.id },
        data: { attempts: { increment: 1 } },
      });
      this.logger.warn(
        `Password reset failed: userId=${record.userId} source=${record.source} reason=weak_password attempts=${record.attempts + 1}`,
      );
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

  async setPasswordForUserId(
    userId: string,
    newPassword: string,
    actor: ResetActor,
  ): Promise<{ ok: true }> {
    this.logger.log(
      `Admin password reset started: actor=${actor.email || actor.id || 'unknown'} targetUserId=${userId}`,
    );
    assertPasswordPolicy(newPassword);

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, email: true, status: true },
    });
    if (!user) throw new NotFoundException('Không tìm thấy user');

    const password = await bcrypt.hash(newPassword, RESET_TOKEN_SALT_ROUNDS);
    const revokedAt = new Date();

    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: user.id },
        data: {
          password,
          tokenVersion: { increment: 1 },
        },
      });
      await tx.userPlatformSession.updateMany({
        where: { userId: user.id, revokedAt: null },
        data: { revokedAt, revokedReason: 'ADMIN_PASSWORD_RESET' },
      });
      await tx.passwordResetToken.updateMany({
        where: {
          userId: user.id,
          purpose: PASSWORD_RESET_PURPOSE,
          consumedAt: null,
        },
        data: { consumedAt: revokedAt },
      });
      await tx.emailVerificationCode.updateMany({
        where: {
          email: user.email,
          purpose: PASSWORD_RESET_PURPOSE,
          consumedAt: null,
        },
        data: { consumedAt: revokedAt },
      });
    });

    this.logger.log(
      `Admin password reset completed: actor=${actor.email || actor.id || 'unknown'} targetUserId=${user.id} email=${user.email} status=${user.status}`,
    );
    return { ok: true };
  }

  private async sendResetCodeForUser(user: ResetUser) {
    const code = this.generateCode();
    const codeHash = await bcrypt.hash(code, RESET_CODE_SALT_ROUNDS);
    const expiresAt = this.expiresAt();
    const invalidatedAt = new Date();

    await this.prisma.$transaction(async (tx) => {
      await tx.emailVerificationCode.updateMany({
        where: {
          email: user.email,
          purpose: PASSWORD_RESET_PURPOSE,
          consumedAt: null,
        },
        data: { consumedAt: invalidatedAt },
      });
      await tx.passwordResetToken.updateMany({
        where: {
          userId: user.id,
          purpose: PASSWORD_RESET_PURPOSE,
          consumedAt: null,
        },
        data: { consumedAt: invalidatedAt },
      });
      await tx.emailVerificationCode.create({
        data: {
          email: user.email,
          purpose: PASSWORD_RESET_PURPOSE,
          codeHash,
          expiresAt,
        },
      });
    });

    await this.mailService.sendMail({
      to: user.email,
      subject: 'Mã đổi mật khẩu OpsHub',
      text:
        `Xin chào ${user.firstName || user.email},\n\n` +
        `Mã đổi mật khẩu OpsHub của bạn là ${code}. Mã hết hạn sau ${RESET_CODE_TTL_MINUTES} phút.\n\n` +
        'Nếu bạn không yêu cầu đổi mật khẩu, vui lòng bỏ qua email này.',
      html:
        `<p>Xin chào ${this.escapeHtml(user.firstName || user.email)},</p>` +
        `<p>Mã đổi mật khẩu OpsHub của bạn là <strong>${code}</strong>. Mã hết hạn sau ${RESET_CODE_TTL_MINUTES} phút.</p>` +
        '<p>Nếu bạn không yêu cầu đổi mật khẩu, vui lòng bỏ qua email này.</p>',
    });

    this.logger.log(
      `Password reset code sent: userId=${user.id} email=${user.email}`,
    );
  }

  private genericCodeResponse() {
    return { ok: true as const, expiresInMinutes: RESET_CODE_TTL_MINUTES };
  }

  private expiresAt() {
    return new Date(Date.now() + RESET_CODE_TTL_MINUTES * 60 * 1000);
  }

  private generateToken() {
    return randomBytes(RESET_TOKEN_BYTES).toString('base64url');
  }

  private generateCode() {
    return Math.floor(100000 + Math.random() * 900000).toString();
  }

  private hashToken(token: string) {
    return createHash('sha256').update(token).digest('hex');
  }

  private invalidTokenError() {
    return new BadRequestException(
      'Phiên đổi mật khẩu không hợp lệ hoặc đã hết hạn.',
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
