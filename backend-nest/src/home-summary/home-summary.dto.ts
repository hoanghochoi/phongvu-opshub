import { IsOptional, IsString, MaxLength } from 'class-validator';

export class GetHomeSummaryQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(10)
  date?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  scope?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  organizationNodeId?: string;
}
