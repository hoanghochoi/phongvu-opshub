import {
  IsEmail,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';

export class PasswordLoginDto {
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

export class SendEmailVerificationDto {
  @IsEmail()
  email!: string;
}

export class GetUserDto {
  @IsOptional()
  @IsString()
  user?: string;
}
