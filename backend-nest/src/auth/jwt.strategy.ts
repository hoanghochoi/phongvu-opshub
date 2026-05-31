import { ExtractJwt, Strategy } from 'passport-jwt';
import { PassportStrategy } from '@nestjs/passport';
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { getRequiredEnv } from '../config/env';
import { AuthSessionService } from './auth-session.service';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    private prisma: PrismaService,
    private authSessionService: AuthSessionService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: getRequiredEnv('JWT_SECRET'),
    });
  }

  async validate(payload: any) {
    const user = await this.prisma.user.findUnique({
      where: { id: payload.sub },
    });
    if (!user) {
      throw new UnauthorizedException();
    }
    if (user.status === 'no') {
      throw new UnauthorizedException();
    }
    const payloadTokenVersion = Number.isInteger(payload.tokenVersion)
      ? payload.tokenVersion
      : 0;
    if ((user.tokenVersion ?? 0) !== payloadTokenVersion) {
      throw new UnauthorizedException();
    }
    const authSession = await this.authSessionService.validateJwtSession(
      user.id,
      payload,
    );
    return { ...user, authSession };
  }
}
