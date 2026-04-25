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

@Controller('auth')
export class AuthController {
  constructor(private authService: AuthService) {}

  // POST /auth/google-login — verify Google ID token and issue JWT
  @Post('google-login')
  async googleLogin(@Body() body: { idToken: string }) {
    return this.authService.googleLogin(body.idToken);
  }

  // POST /auth/get-user — mirrors pva-get-user
  @Post('get-user')
  @UseGuards(AuthGuard('jwt'))
  async getUserData(@Body() body: { user: string }) {
    return this.authService.getUserData(body.user);
  }

  // GET /auth/me — convenience JWT-protected endpoint
  @Get('me')
  @UseGuards(AuthGuard('jwt'))
  async getMe(@Request() req: any) {
    return this.authService.getUserData(req.user.email);
  }
}
