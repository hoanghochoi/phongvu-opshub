import {
  Injectable,
  UnauthorizedException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { JwtService } from '@nestjs/jwt';
import { OAuth2Client } from 'google-auth-library';

@Injectable()
export class AuthService {
  private googleClient: OAuth2Client;

  constructor(
    private prisma: PrismaService,
    private jwtService: JwtService,
  ) {
    this.googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);
  }

  // -------------------------------------------------------
  // GOOGLE LOGIN: verify ID token, check domain, issue JWT
  // -------------------------------------------------------
  async googleLogin(idToken: string) {
    // 1. Verify Google ID Token
    let payload: any;
    try {
      const ticket = await this.googleClient.verifyIdToken({
        idToken,
        audience: process.env.GOOGLE_CLIENT_ID,
      });
      payload = ticket.getPayload();
    } catch (error) {
      throw new UnauthorizedException('Google token không hợp lệ');
    }

    if (!payload || !payload.email) {
      throw new UnauthorizedException('Không lấy được thông tin từ Google');
    }

    // 2. Check domain restriction
    const allowedDomains = (process.env.ALLOWED_DOMAIN || 'phongvu.vn')
      .split(',')
      .map((d) => d.trim())
      .filter((d) => d.length > 0);
    const emailDomain = payload.email.split('@')[1];
    if (!allowedDomains.includes(emailDomain)) {
      throw new ForbiddenException(
        `Chỉ cho phép đăng nhập bằng email @${allowedDomains.join(', @')}`,
      );
    }

    // 3. Find or create user
    let user = await this.prisma.user.findUnique({
      where: { email: payload.email },
      include: { store: true },
    });

    if (!user) {
      // Auto-create user on first Google login
      user = await this.prisma.user.create({
        data: {
          email: payload.email,
          password: '', // Not used for Google login
          firstName:
            payload.given_name || payload.name || payload.email.split('@')[0],
          lastName: payload.family_name || null,
          status: 'yes',
        },
        include: { store: true },
      });
    }

    // 4. Check if user is locked
    if (user.status === 'no') {
      throw new ForbiddenException('Tài khoản đã bị khóa. Liên hệ Quản lý.');
    }

    // 5. Issue JWT
    const jwtPayload = { email: user.email, sub: user.id, role: user.role };
    return {
      login: true,
      access_token: this.jwtService.sign(jwtPayload),
      email: user.email,
      name: user.firstName,
      firstName: user.firstName,
      storeId: user.store?.storeId ?? null,
      storeName: user.store?.storeName ?? null,
      role: user.role,
    };
  }

  // -------------------------------------------------------
  // GET USER DATA
  // -------------------------------------------------------
  async getUserData(email: string) {
    const user = await this.prisma.user.findUnique({
      where: { email },
      include: { store: true },
    });

    if (!user) throw new UnauthorizedException('User not found');

    return {
      name: user.firstName,
      firstName: user.firstName,
      storeId: user.store?.storeId ?? null,
      storeName: user.store?.storeName ?? null,
      role: user.role,
    };
  }
}
