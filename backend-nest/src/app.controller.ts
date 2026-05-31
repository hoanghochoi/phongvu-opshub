import { Controller, Get, Header } from '@nestjs/common';
import { resetPasswordPageHtml } from './auth/reset-password-page';
import { AppService } from './app.service';

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  getHello(): string {
    return this.appService.getHello();
  }
  @Get('reset-password')
  @Header('Content-Type', 'text/html; charset=utf-8')
  getResetPasswordPage(): string {
    return resetPasswordPageHtml();
  }

  @Get('health')
  getHealth() {
    return this.appService.getHealth();
  }
}
