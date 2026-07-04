import { IsOptional, IsString, MaxLength } from 'class-validator';

export class GetHomeSummaryQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(10)
  date?: string;
}
