import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { createHash, randomInt } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { OpshubMailService } from './opshub-mail.service';

const CODE_TTL_MINUTES = 10;
const CODE_SALT_ROUNDS = 10;
const MAX_ATTEMPTS = 5;
const REGISTER_PURPOSE = 'REGISTER';

@Injectable()
export class EmailVerificationService {
  private readonly logger = new Logger(EmailVerificationService.name);

  constructor(
    private prisma: PrismaService,
    private mailService: OpshubMailService,
  ) {}

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

    await this.mailService.sendMail({
      to: email,
      subject: 'Mã xác thực đăng ký PhongVu OpsHub',
      text: `Mã xác thực PhongVu OpsHub của bạn là ${code}. Mã hết hạn sau ${CODE_TTL_MINUTES} phút.`,
    });
    this.logger.log(
      `Registration verification email sent: emailHash=${this.emailLogId(email)}`,
    );
    return this.registrationCodeResponse();
  }

  registrationCodeResponse() {
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
    return randomInt(100000, 1_000_000).toString();
  }

  private emailLogId(email: string) {
    return createHash('sha256').update(email).digest('hex').slice(0, 12);
  }
}
