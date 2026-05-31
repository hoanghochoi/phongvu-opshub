import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
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
      subject: 'Ma xac thuc dang ky OpsHub',
      text: `Ma xac thuc OpsHub cua ban la ${code}. Ma het han sau ${CODE_TTL_MINUTES} phut.`,
    });
    this.logger.log(`Registration verification email sent to ${email}`);
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
      throw new BadRequestException('Vui long gui ma xac thuc email truoc.');
    }

    if (record.expiresAt.getTime() < Date.now()) {
      throw new BadRequestException('Ma xac thuc da het han.');
    }

    if (record.attempts >= MAX_ATTEMPTS) {
      throw new BadRequestException(
        'Ma xac thuc da bi khoa do nhap sai qua nhieu lan.',
      );
    }

    const isValid = await bcrypt.compare(code, record.codeHash);
    if (!isValid) {
      await this.prisma.emailVerificationCode.update({
        where: { id: record.id },
        data: { attempts: { increment: 1 } },
      });
      throw new BadRequestException('Ma xac thuc khong dung.');
    }

    await this.prisma.emailVerificationCode.update({
      where: { id: record.id },
      data: { consumedAt: new Date() },
    });
  }

  private generateCode() {
    return Math.floor(100000 + Math.random() * 900000).toString();
  }
}
