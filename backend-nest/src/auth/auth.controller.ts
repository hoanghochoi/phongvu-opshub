import {
  Controller,
  Post,
  Body,
  UseGuards,
  Request,
  Get,
  Headers,
  HttpStatus,
  Response,
  Optional,
} from '@nestjs/common';
import type { Response as ExpressResponse } from 'express';
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
import { AuthBootstrapService } from './auth-bootstrap.service';
import { AuthContextService } from './auth-context.service';

@Controller('auth')
export class AuthController {
  constructor(
    private authService: AuthService,
    private readonly realtimeTicketService: RealtimeTicketService,
    private readonly authBootstrapService: AuthBootstrapService,
    @Optional() private readonly authContextService?: AuthContextService,
  ) {}

  @Post('login')
  @Throttle({
    principal: { ttl: 60_000, limit: 8 },
  })
  async login(@Body() body: PasswordLoginDto) {
    return this.authService.passwordLogin(body.email, body.password, body);
  }

  @Post('register')
  @Throttle({
    principal: { ttl: 60_000, limit: 5 },
  })
  async register(@Body() body: RegisterDto) {
    return this.authService.register(body);
  }

  @Post('verification-code')
  @Throttle({
    principal: { ttl: 60_000, limit: 5 },
  })
  async sendVerificationCode(@Body() body: SendEmailVerificationDto) {
    return this.authService.sendRegistrationVerificationCode(body.email);
  }

  @Post('forgot-password')
  @Throttle({
    principal: { ttl: 60_000, limit: 5 },
  })
  async forgotPassword(@Body() body: ForgotPasswordDto) {
    return this.authService.forgotPassword(body.email);
  }

  @Post('forgot-password/verify-code')
  @Throttle({
    principal: { ttl: 60_000, limit: 10 },
  })
  async verifyForgotPasswordCode(@Body() body: VerifyForgotPasswordCodeDto) {
    return this.authService.verifyForgotPasswordCode(body.email, body.code);
  }

  @Post('reset-password')
  @Throttle({
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
    return this.authContextService
      ? this.authContextService.profile(req.user)
      : this.authService.getUserData(req.user.email);
  }

  // GET /auth/me - convenience JWT-protected endpoint
  @Get('me')
  @UseGuards(AuthGuard('jwt'))
  async getMe(@Request() req: any) {
    return this.authContextService
      ? this.authContextService.profile(req.user)
      : this.authService.getUserData(req.user.email);
  }

  @Get('bootstrap')
  @UseGuards(AuthGuard('jwt'))
  async getBootstrap(
    @Request() req: any,
    @Headers('if-none-match') ifNoneMatch: string | undefined,
    @Response({ passthrough: true }) response: ExpressResponse,
  ) {
    const preflightEtag = this.authBootstrapService.etagForUser?.(req.user);
    if (
      preflightEtag &&
      this.authBootstrapService.matchesEtag(ifNoneMatch, preflightEtag)
    ) {
      response.setHeader('Cache-Control', 'private, no-cache');
      response.setHeader('ETag', preflightEtag);
      response.status(HttpStatus.NOT_MODIFIED);
      return undefined;
    }
    const result = await this.authBootstrapService.resolve(req.user);
    response.setHeader('Cache-Control', 'private, no-cache');
    response.setHeader('ETag', result.etag);
    if (this.authBootstrapService.matchesEtag(ifNoneMatch, result.etag)) {
      response.status(HttpStatus.NOT_MODIFIED);
      return undefined;
    }
    return result.body;
  }
}
