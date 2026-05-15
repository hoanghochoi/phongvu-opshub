import {
  IsEmail,
  IsOptional,
  IsString,
  Matches,
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
}

export class GetUserDto {
  @IsOptional()
  @IsString()
  user?: string;
}
