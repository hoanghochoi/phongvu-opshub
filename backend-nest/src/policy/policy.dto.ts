import {
  IsArray,
  IsBoolean,
  IsObject,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export class AdminPolicyDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
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
  @MaxLength(80)
  category?: string;

  @IsOptional()
  @IsBoolean()
  defaultAllowed?: boolean;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class AdminPolicyRuleDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  policyCode?: string;

  @IsOptional()
  @IsBoolean()
  allowed?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  emailDomain?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  systemRole?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  departmentCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  jobRoleCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  workScopeType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  regionCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  areaCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  storeCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  userId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  scopeContains?: string;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  note?: string;
}

export class AdminPolicyRuleBatchDto extends AdminPolicyRuleDto {
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(120, { each: true })
  emailDomains?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  systemRoles?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  departmentCodes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  jobRoleCodes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  workScopeTypes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  regionCodes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  areaCodes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  storeCodes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  userIds?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(120, { each: true })
  scopeContainsValues?: string[];

}

export class AdminSettingDto {
  @IsOptional()
  @IsString()
  @MaxLength(120)
  key?: string;
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
  @MaxLength(80)
  category?: string;

  @IsOptional()
  @IsObject()
  value?: Record<string, unknown> | unknown[];
}
