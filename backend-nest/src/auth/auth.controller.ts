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
import { Throttle } from '@nestjs/throttler';
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
import { RealtimeTicketRequestDto } from './realtime-ticket.dto';
import { RealtimeTicketService } from './realtime-ticket.service';

@Controller('auth')
export class AuthController {
  constructor(
    private authService: AuthService,
    private readonly realtimeTicketService: RealtimeTicketService,
  ) {}

  @Post('login')
  @Throttle({
    ip: { ttl: 60_000, limit: 20 },
    principal: { ttl: 60_000, limit: 8 },
  })
  async login(@Body() body: PasswordLoginDto) {
    return this.authService.passwordLogin(body.email, body.password, body);
  }

  @Post('register')
  @Throttle({
    ip: { ttl: 60_000, limit: 10 },
    principal: { ttl: 60_000, limit: 5 },
  })
  async register(@Body() body: RegisterDto) {
    return this.authService.register(body);
  }

  @Post('verification-code')
  @Throttle({
    ip: { ttl: 60_000, limit: 10 },
    principal: { ttl: 60_000, limit: 5 },
  })
  async sendVerificationCode(@Body() body: SendEmailVerificationDto) {
    return this.authService.sendRegistrationVerificationCode(body.email);
  }

  @Post('forgot-password')
  @Throttle({
    ip: { ttl: 60_000, limit: 10 },
    principal: { ttl: 60_000, limit: 5 },
  })
  async forgotPassword(@Body() body: ForgotPasswordDto) {
    return this.authService.forgotPassword(body.email);
  }

  @Post('forgot-password/verify-code')
  @Throttle({
    ip: { ttl: 60_000, limit: 20 },
    principal: { ttl: 60_000, limit: 10 },
  })
  async verifyForgotPasswordCode(@Body() body: VerifyForgotPasswordCodeDto) {
    return this.authService.verifyForgotPasswordCode(body.email, body.code);
  }

  @Post('reset-password')
  @Throttle({
    ip: { ttl: 60_000, limit: 20 },
    principal: { ttl: 60_000, limit: 10 },
  })
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

  @Post('realtime-ticket')
  @UseGuards(AuthGuard('jwt'))
  @Throttle({
    ip: { ttl: 60_000, limit: 120 },
    principal: { ttl: 60_000, limit: 30 },
  })
  async issueRealtimeTicket(
    @Request() req: any,
    @Body() body: RealtimeTicketRequestDto,
  ) {
    return this.realtimeTicketService.issueTicket(req.user, body?.storeCode);
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
