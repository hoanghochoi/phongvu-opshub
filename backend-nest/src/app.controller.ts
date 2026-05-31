import {
  Body,
  Controller,
  Get,
  Header,
  HttpException,
  Logger,
  Post,
  Query,
} from '@nestjs/common';
import { resetPasswordPageHtml } from './auth/reset-password-page';
import { AppService } from './app.service';
import { PasswordResetService } from './auth/password-reset.service';

type ResetPasswordFormBody = {
  token?: unknown;
  newPassword?: unknown;
  confirmPassword?: unknown;
};

@Controller()
export class AppController {
  private readonly logger = new Logger(AppController.name);

  constructor(
    private readonly appService: AppService,
    private readonly passwordResetService: PasswordResetService,
  ) {}

  @Get()
  getHello(): string {
    return this.appService.getHello();
  }
  @Get('reset-password')
  @Header('Content-Type', 'text/html; charset=utf-8')
  getResetPasswordPage(@Query('token') token?: string): string {
    const resetToken = this.cleanToken(token);
    if (!resetToken) {
      return resetPasswordPageHtml({
        status: 'error',
        message: 'Link đổi mật khẩu không hợp lệ.',
        showForm: false,
      });
    }
    return resetPasswordPageHtml({ token: resetToken, showForm: true });
  }

  @Post('reset-password')
  @Header('Content-Type', 'text/html; charset=utf-8')
  async submitResetPassword(@Body() body: ResetPasswordFormBody) {
    const token = this.cleanToken(body.token);
    const newPassword = this.formString(body.newPassword);
    const confirmPassword = this.formString(body.confirmPassword);

    this.logger.log(
      `Password reset form submitted: hasToken=${Boolean(token)} hasPassword=${Boolean(newPassword)} hasConfirm=${Boolean(confirmPassword)}`,
    );

    if (!token) {
      this.logger.warn('Password reset form rejected: reason=missing_token');
      return resetPasswordPageHtml({
        status: 'error',
        message: 'Link đổi mật khẩu không hợp lệ.',
        showForm: false,
      });
    }

    if (!newPassword || !confirmPassword) {
      this.logger.warn(
        'Password reset form rejected: reason=missing_password_fields',
      );
      return resetPasswordPageHtml({
        token,
        status: 'error',
        message: 'Vui lòng nhập đầy đủ mật khẩu mới.',
        showForm: true,
      });
    }

    if (newPassword !== confirmPassword) {
      this.logger.warn(
        'Password reset form rejected: reason=password_mismatch',
      );
      return resetPasswordPageHtml({
        token,
        status: 'error',
        message: 'Mật khẩu nhập lại chưa khớp.',
        showForm: true,
      });
    }

    try {
      await this.passwordResetService.resetPassword(token, newPassword);
      this.logger.log('Password reset form completed');
      return resetPasswordPageHtml({
        status: 'success',
        message: 'Đã đổi mật khẩu. Bạn có thể quay lại ứng dụng để đăng nhập.',
        showForm: false,
      });
    } catch (error) {
      const message = this.userFacingErrorMessage(error);
      const showForm = this.canRetryReset(message);
      this.logger.warn(
        `Password reset form failed: showForm=${showForm} error=${message}`,
      );
      return resetPasswordPageHtml({
        token,
        status: 'error',
        message,
        showForm,
      });
    }
  }

  @Get('health')
  getHealth() {
    return this.appService.getHealth();
  }

  private cleanToken(value: unknown): string {
    return this.formString(value).trim();
  }

  private formString(value: unknown): string {
    if (Array.isArray(value)) return this.formString(value[0]);
    if (value == null) return '';
    return typeof value === 'string' ? value : String(value);
  }

  private userFacingErrorMessage(error: unknown): string {
    if (error instanceof HttpException) {
      const response = error.getResponse();
      if (typeof response === 'string') return response;
      if (response && typeof response === 'object' && 'message' in response) {
        const message = (response as { message?: unknown }).message;
        if (Array.isArray(message)) return message.join('\n');
        if (typeof message === 'string') return message;
      }
    }
    return 'Không đổi được mật khẩu. Vui lòng thử lại.';
  }

  private canRetryReset(message: string): boolean {
    const normalized = message.toLowerCase();
    return !normalized.includes('link đổi mật khẩu');
  }
}
