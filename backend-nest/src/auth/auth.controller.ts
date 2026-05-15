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
import { GetUserDto, PasswordLoginDto, RegisterDto } from './auth.dto';

@Controller('auth')
export class AuthController {
  constructor(private authService: AuthService) {}

  @Post('login')
  async login(@Body() body: PasswordLoginDto) {
    return this.authService.passwordLogin(body.email, body.password);
  }

  @Post('register')
  async register(@Body() body: RegisterDto) {
    return this.authService.register(body);
  }

  // POST /auth/get-user
  @Post('get-user')
  @UseGuards(AuthGuard('jwt'))
  async getUserData(@Request() req: any, @Body() _body: GetUserDto) {
    return this.authService.getUserData(req.user.email);
  }

  // GET /auth/me — convenience JWT-protected endpoint
  @Get('me')
  @UseGuards(AuthGuard('jwt'))
  async getMe(@Request() req: any) {
    return this.authService.getUserData(req.user.email);
  }
}
