import { IsOptional, IsString, MaxLength } from 'class-validator';

export class QuickActionsQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  storeCode?: string;
}

export class UpdateQuickActionLinksDto {
  @IsOptional()
  @IsString()
  @MaxLength(2048)
  APP_DOWNLOAD?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(2048)
  CHECK_IN?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(2048)
  ZALO_OA?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(2048)
  GOOGLE_MAP?: string | null;
}
