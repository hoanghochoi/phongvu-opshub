import {
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';
import { AUTH_PLATFORMS } from './auth-session.service';

class AuthDeviceDto {
  @IsIn(AUTH_PLATFORMS)
  platform!: string;

  @IsString()
  @MinLength(8)
  @MaxLength(128)
  deviceId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  deviceLabel?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  appVersion?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  buildNumber?: string;
}

export class PasswordLoginDto extends AuthDeviceDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8)
  @Matches(/[A-Z]/)
  @Matches(/[0-9]/)
  @Matches(/[!@#$%^&*(),.?":{}|<>]/)
  password!: string;
}

export class RegisterDto extends PasswordLoginDto {
  @IsString()
  @MinLength(1)
  firstName!: string;

  @IsOptional()
  @IsString()
  lastName?: string;

  @IsString()
  @MinLength(6)
  @MaxLength(6)
  @Matches(/^[0-9]{6}$/)
  verificationCode!: string;
}

export class ChangePasswordDto {
  @IsString()
  @MinLength(1)
  currentPassword!: string;

  @IsString()
  @MinLength(1)
  newPassword!: string;
}

export class ForgotPasswordDto {
  @IsEmail()
  email!: string;
}

export class VerifyForgotPasswordCodeDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(6)
  @MaxLength(6)
  @Matches(/^[0-9]{6}$/)
  code!: string;
}

export class ResetPasswordDto {
  @IsString()
  @MinLength(20)
  token!: string;

  @IsString()
  @MinLength(1)
  newPassword!: string;
}

export class SendEmailVerificationDto {
  @IsEmail()
  email!: string;
}

export class GetUserDto {
  @IsOptional()
  @IsString()
  user?: string;
}
