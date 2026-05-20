import { IsEmail, IsOptional, IsString, MaxLength } from 'class-validator';

export class UpdateProfileDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  firstName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  lastName?: string;
}

export class SelectStoreDto {
  @IsString()
  @MaxLength(40)
  storeId!: string;
}

export class AdminUserDto extends UpdateProfileDto {
  @IsOptional()
  @IsEmail()
  @MaxLength(255)
  email?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  role?: string;

  @IsOptional()
  @IsString()
  status?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  storeId?: string;
}

export class AdminRoleDto {
  @IsString()
  @MaxLength(40)
  code!: string;

  @IsString()
  @MaxLength(80)
  displayName!: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  description?: string;
}

export class AdminStoreDto {
  @IsOptional()
  @IsString()
  @MaxLength(40)
  storeId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  storeName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  transferAccountNumber?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  transferAccountName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  transferBankName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  transferBankBin?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  mapVietinUsername?: string;

  @IsOptional()
  @IsString()
  @MaxLength(255)
  mapVietinPassword?: string;
}
