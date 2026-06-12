import {
  IsArray,
  IsEmail,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

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

  @IsOptional()
  @IsString()
  @MaxLength(40)
  departmentCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  jobRoleCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  workScopeType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  regionCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  areaCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  organizationNodeId?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  featureCodes?: string[];
}

export class AdminUserQueryDto {
  @IsOptional()
  @IsString()
  q?: string;

  @IsOptional()
  @IsString()
  domain?: string;

  @IsOptional()
  @IsString()
  orgNodeId?: string;

  @IsOptional()
  @IsString()
  featureCode?: string;

  @IsOptional()
  @IsString()
  role?: string;

  @IsOptional()
  @IsString()
  status?: string;
}

export class AdminResetPasswordDto {
  @IsString()
  @MinLength(1)
  newPassword!: string;
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

export class AdminPersonnelCatalogDto extends AdminRoleDto {
  @IsOptional()
  @IsString()
  @MaxLength(40)
  departmentCode?: string;

  @IsOptional()
  isActive?: boolean;
}

export class AdminRegionDto {
  @IsOptional()
  @IsString()
  @MaxLength(40)
  code?: string;

  @IsString()
  @MaxLength(80)
  displayName!: string;

  @IsString()
  @MaxLength(40)
  abbreviation!: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  description?: string;

  @IsOptional()
  isActive?: boolean;
}

export class AdminAreaDto extends AdminRegionDto {
  @IsString()
  @MaxLength(40)
  regionCode!: string;
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
  @MaxLength(40)
  areaCode?: string;

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

export class OrganizationNodeDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  code?: string;

  @IsString()
  @MaxLength(120)
  displayName!: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  businessCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  abbreviation?: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  description?: string;

  @IsString()
  @MaxLength(40)
  type!: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  parentId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  emailDomain?: string;

  @IsOptional()
  loginAllowed?: boolean;

  @IsOptional()
  isActive?: boolean;

  @IsOptional()
  sortOrder?: number;

  @IsOptional()
  @IsString()
  @MaxLength(80)
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
