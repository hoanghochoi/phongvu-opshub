import { Type } from 'class-transformer';
import {
  IsInt,
  IsIn,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

class HomeSummaryScopeQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(10)
  date?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  startDate?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  endDate?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  scope?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  organizationNodeId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  salesProgressUserId?: string;
}

export class GetHomeSummaryQueryDto extends HomeSummaryScopeQueryDto {
  @IsOptional()
  @IsString({
    message: 'Tùy chọn chuỗi theo ngày chỉ nhận true hoặc false.',
  })
  @IsIn(['true', 'false'], {
    message: 'Tùy chọn chuỗi theo ngày chỉ nhận true hoặc false.',
  })
  includeDailySeries?: 'true' | 'false';
}

export class GetHomeSummaryDetailsQueryDto extends HomeSummaryScopeQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(500)
  limit?: number;
}

export const HOME_SUMMARY_DETAIL_V2_KINDS = [
  'NOT_PURCHASED',
  'UNREPORTED_ORDER',
  'INSTALLMENT_NEED',
] as const;

export class GetHomeSummaryDetailsV2QueryDto extends HomeSummaryScopeQueryDto {
  @IsString()
  @IsIn(HOME_SUMMARY_DETAIL_V2_KINDS)
  kind!: (typeof HOME_SUMMARY_DETAIL_V2_KINDS)[number];

  @IsOptional()
  @IsString()
  @MaxLength(300)
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}
