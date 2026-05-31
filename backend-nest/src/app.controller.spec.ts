import { BadRequestException } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PasswordResetService } from './auth/password-reset.service';

describe('AppController', () => {
  let appController: AppController;
  let passwordResetService: { resetPassword: jest.Mock };

  beforeEach(async () => {
    passwordResetService = { resetPassword: jest.fn() };
    const app: TestingModule = await Test.createTestingModule({
      controllers: [AppController],
      providers: [
        AppService,
        { provide: PasswordResetService, useValue: passwordResetService },
      ],
    }).compile();

    appController = app.get<AppController>(AppController);
  });

  describe('root', () => {
    it('should return "Hello World!"', () => {
      expect(appController.getHello()).toBe('Hello World!');
    });
  });

  describe('health', () => {
    it('returns liveness data', () => {
      expect(appController.getHealth()).toEqual({
        status: 'ok',
        service: 'backend-nest',
      });
    });
  });

  describe('reset password page', () => {
    it('returns a CSP-safe backend-served POST form', () => {
      const html = appController.getResetPasswordPage('reset-token');
      expect(html).toContain('method="post"');
      expect(html).toContain('action="/reset-password"');
      expect(html).toContain('name="token" value="reset-token"');
      expect(html).toContain('name="newPassword"');
      expect(html).toContain('name="confirmPassword"');
      expect(html).not.toContain('<script');
      expect(html).not.toContain('name="password"');
      expect(html).not.toContain('/api/auth/reset-password');
      expect(html).not.toContain('/auth/reset-password');
    });

    it('renders an invalid-link message when token is missing', () => {
      const html = appController.getResetPasswordPage();
      expect(html).toContain('Link đổi mật khẩu không hợp lệ.');
      expect(html).not.toContain('name="newPassword"');
    });

    it('rejects mismatched password confirmation without calling the reset service', async () => {
      const html = await appController.submitResetPassword({
        token: 'reset-token',
        newPassword: 'Password2!',
        confirmPassword: 'Password3!',
      });

      expect(passwordResetService.resetPassword).not.toHaveBeenCalled();
      expect(html).toContain('Mật khẩu nhập lại chưa khớp.');
      expect(html).toContain('name="token" value="reset-token"');
      expect(html).not.toContain('Password2!');
    });

    it('submits matching passwords to the reset service and renders success', async () => {
      passwordResetService.resetPassword.mockResolvedValue({ ok: true });

      const html = await appController.submitResetPassword({
        token: 'reset-token',
        newPassword: 'Password2!',
        confirmPassword: 'Password2!',
      });

      expect(passwordResetService.resetPassword).toHaveBeenCalledWith(
        'reset-token',
        'Password2!',
      );
      expect(html).toContain('Đã đổi mật khẩu.');
      expect(html).not.toContain('name="newPassword"');
      expect(html).not.toContain('Password2!');
    });

    it('renders reset service errors without leaking password values', async () => {
      passwordResetService.resetPassword.mockRejectedValue(
        new BadRequestException(
          'Link đổi mật khẩu không hợp lệ hoặc đã hết hạn.',
        ),
      );

      const html = await appController.submitResetPassword({
        token: 'reset-token',
        newPassword: 'Password2!',
        confirmPassword: 'Password2!',
      });

      expect(html).toContain('Link đổi mật khẩu không hợp lệ hoặc đã hết hạn.');
      expect(html).not.toContain('Password2!');
      expect(html).not.toContain('name="newPassword"');
    });
  });
});
