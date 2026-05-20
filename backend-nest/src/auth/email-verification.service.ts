import {
  BadRequestException,
  Injectable,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import nodemailer from 'nodemailer';
import { PrismaService } from '../prisma/prisma.service';

const CODE_TTL_MINUTES = 10;
const CODE_SALT_ROUNDS = 10;
const MAX_ATTEMPTS = 5;
const REGISTER_PURPOSE = 'REGISTER';

@Injectable()
export class EmailVerificationService {
  private readonly logger = new Logger(EmailVerificationService.name);

  constructor(private prisma: PrismaService) {}

  async sendRegistrationCode(email: string) {
    const code = this.generateCode();
    const codeHash = await bcrypt.hash(code, CODE_SALT_ROUNDS);
    const expiresAt = new Date(Date.now() + CODE_TTL_MINUTES * 60 * 1000);

    await this.prisma.emailVerificationCode.create({
      data: {
        email,
        purpose: REGISTER_PURPOSE,
        codeHash,
        expiresAt,
      },
    });

    await this.sendEmail(email, code);
    return {
      ok: true,
      expiresInMinutes: CODE_TTL_MINUTES,
    };
  }

  async consumeRegistrationCode(email: string, code: string) {
    const record = await this.prisma.emailVerificationCode.findFirst({
      where: {
        email,
        purpose: REGISTER_PURPOSE,
        consumedAt: null,
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!record) {
      throw new BadRequestException('Vui lòng gửi mã xác thực email trước.');
    }

    if (record.expiresAt.getTime() < Date.now()) {
      throw new BadRequestException('Mã xác thực đã hết hạn.');
    }

    if (record.attempts >= MAX_ATTEMPTS) {
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
      throw new BadRequestException('Mã xác thực không đúng.');
    }

    await this.prisma.emailVerificationCode.update({
      where: { id: record.id },
      data: { consumedAt: new Date() },
    });
  }

  private generateCode() {
    return Math.floor(100000 + Math.random() * 900000).toString();
  }

  private async sendEmail(to: string, code: string) {
    const host = process.env.SMTP_HOST?.trim();
    const user = process.env.SMTP_USER?.trim();
    const pass = process.env.SMTP_PASS?.trim();
    const from = process.env.SMTP_FROM?.trim() || user;
    const port = Number(process.env.SMTP_PORT || '587');
    const secure = process.env.SMTP_SECURE === 'true';

    if (!host || !user || !pass || !from) {
      throw new InternalServerErrorException(
        'Chưa cấu hình gửi email xác thực.',
      );
    }

    const transporter = nodemailer.createTransport({
      host,
      port,
      secure,
      auth: { user, pass },
    });

    try {
      await transporter.sendMail({
        from,
        to,
        subject: 'Mã xác thực đăng ký OpsHub',
        text: `Mã xác thực OpsHub của bạn là ${code}. Mã hết hạn sau ${CODE_TTL_MINUTES} phút.`,
      });
    } catch (error) {
      this.logger.error(`Failed to send verification email to ${to}`, error);
      throw new InternalServerErrorException(
        'Không gửi được mã xác thực email.',
      );
    }
  }
}
