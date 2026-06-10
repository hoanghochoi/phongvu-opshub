import {
  IsArray,
  IsBoolean,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export class AdminFeatureDto {
  @IsOptional()
  @IsString()
  @MaxLength(60)
  code?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  displayName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  description?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  parentCode?: string;

  @IsOptional()
  sortOrder?: number;

  @IsOptional()
  @IsBoolean()
  visibleInUserPicker?: boolean;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class AdminFeatureRuleDto {
  @IsOptional()
  @IsString()
  @MaxLength(60)
  featureCode?: string;

  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  emailDomain?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  systemRole?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  departmentCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  jobRoleCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  workScopeType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  regionCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  areaCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  organizationNodeId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  storeCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  userId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  note?: string;
}

export class AdminFeatureRuleBatchDto extends AdminFeatureRuleDto {
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  systemRoles?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(120, { each: true })
  emailDomains?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  departmentCodes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  jobRoleCodes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  workScopeTypes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  regionCodes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  areaCodes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  organizationNodeIds?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  storeCodes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  userIds?: string[];
}
