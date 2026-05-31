import {
  Injectable,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import nodemailer from 'nodemailer';

@Injectable()
export class OpshubMailService {
  private readonly logger = new Logger(OpshubMailService.name);

  async sendMail(input: {
    to: string;
    subject: string;
    text: string;
    html?: string;
  }): Promise<void> {
    const host = process.env.SMTP_HOST?.trim();
    const user = process.env.SMTP_USER?.trim();
    const pass = process.env.SMTP_PASS?.trim();
    const from = process.env.SMTP_FROM?.trim() || user;
    const port = Number(process.env.SMTP_PORT || '587');
    const secure = process.env.SMTP_SECURE === 'true';

    if (!host || !user || !pass || !from) {
      throw new InternalServerErrorException('Chua cau hinh gui email OpsHub.');
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
        to: input.to,
        subject: input.subject,
        text: input.text,
        html: input.html,
      });
    } catch (error) {
      this.logger.error(`Failed to send OpsHub email to ${input.to}`, error);
      throw new InternalServerErrorException('Khong gui duoc email OpsHub.');
    }
  }
}
