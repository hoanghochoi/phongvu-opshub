import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { PrismaModule } from '../prisma/prisma.module';
import { JwtStrategy } from './jwt.strategy';
import { EmailVerificationService } from './email-verification.service';
import { OpshubMailService } from './opshub-mail.service';
import { PasswordResetService } from './password-reset.service';
import { AuthSessionService } from './auth-session.service';
import { FeatureModule } from '../feature/feature.module';
import { RedisModule } from '../redis/redis.module';
import { RealtimeTicketService } from './realtime-ticket.service';

@Module({
  imports: [
    PrismaModule,
    RedisModule,
    FeatureModule,
    PassportModule,
    JwtModule.register({
      secret: process.env.JWT_SECRET,
      signOptions: { expiresIn: '7d' },
    }),
  ],
  controllers: [AuthController],
  providers: [
    AuthService,
    JwtStrategy,
    EmailVerificationService,
    OpshubMailService,
    PasswordResetService,
    AuthSessionService,
    RealtimeTicketService,
  ],
  exports: [JwtModule, OpshubMailService, PasswordResetService],
})
export class AuthModule {}
