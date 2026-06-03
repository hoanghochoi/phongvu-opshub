import {
  Controller,
  Post,
  Body,
  UseGuards,
  Request,
  Get,
} from '@nestjs/common';
import { AuthService } from './auth.service';
import { AuthGuard } from '@nestjs/passport';
import {
  ChangePasswordDto,
  ForgotPasswordDto,
  GetUserDto,
  PasswordLoginDto,
  RegisterDto,
  ResetPasswordDto,
  SendEmailVerificationDto,
  VerifyForgotPasswordCodeDto,
} from './auth.dto';

@Controller('auth')
export class AuthController {
  constructor(private authService: AuthService) {}

  @Post('login')
  async login(@Body() body: PasswordLoginDto) {
    return this.authService.passwordLogin(body.email, body.password, body);
  }

  @Post('register')
  async register(@Body() body: RegisterDto) {
    return this.authService.register(body);
  }

  @Post('verification-code')
  async sendVerificationCode(@Body() body: SendEmailVerificationDto) {
    return this.authService.sendRegistrationVerificationCode(body.email);
  }

  @Post('forgot-password')
  async forgotPassword(@Body() body: ForgotPasswordDto) {
    return this.authService.forgotPassword(body.email);
  }

  @Post('forgot-password/verify-code')
  async verifyForgotPasswordCode(@Body() body: VerifyForgotPasswordCodeDto) {
    return this.authService.verifyForgotPasswordCode(body.email, body.code);
  }

  @Post('reset-password')
  async resetPassword(@Body() body: ResetPasswordDto) {
    return this.authService.resetPassword(body.token, body.newPassword);
  }

  @Post('change-password')
  @UseGuards(AuthGuard('jwt'))
  async changePassword(@Request() req: any, @Body() body: ChangePasswordDto) {
    return this.authService.changePassword(
      req.user.id,
      body.currentPassword,
      body.newPassword,
      req.user.authSession,
    );
  }

  @Post('logout')
  @UseGuards(AuthGuard('jwt'))
  async logout(@Request() req: any) {
    return this.authService.logout(req.user);
  }

  // POST /auth/get-user
  @Post('get-user')
  @UseGuards(AuthGuard('jwt'))
  async getUserData(@Request() req: any, @Body() _body: GetUserDto) {
    return this.authService.getUserData(req.user.email);
  }

  // GET /auth/me - convenience JWT-protected endpoint
  @Get('me')
  @UseGuards(AuthGuard('jwt'))
  async getMe(@Request() req: any) {
    return this.authService.getUserData(req.user.email);
  }
}
