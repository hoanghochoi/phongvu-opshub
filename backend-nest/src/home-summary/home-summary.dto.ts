import { Type } from 'class-transformer';
import {
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export class GetHomeSummaryQueryDto {
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

export class GetHomeSummaryDetailsQueryDto extends GetHomeSummaryQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(500)
  limit?: number;
}
