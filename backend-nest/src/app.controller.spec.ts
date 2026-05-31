import { Test, TestingModule } from '@nestjs/testing';
import { AppController } from './app.controller';
import { AppService } from './app.service';

describe('AppController', () => {
  let appController: AppController;

  beforeEach(async () => {
    const app: TestingModule = await Test.createTestingModule({
      controllers: [AppController],
      providers: [AppService],
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
    it('returns the backend-served reset form', () => {
      const html = appController.getResetPasswordPage();
      expect(html).toContain('/api/auth/reset-password');
      expect(html).toContain('/auth/reset-password');
    });
  });
});
