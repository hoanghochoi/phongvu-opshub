import {
  ArrayMaxSize,
  IsArray,
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';

export class SortTextDto {
  @IsString()
  text!: string;
}

export class FifoCheckDto extends SortTextDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(500)
  qty?: number;
}

export class SortCompletionReportDto {
  @IsArray()
  @ArrayMaxSize(500)
  sortedSKUs!: unknown[];

  @IsOptional()
  @IsISO8601()
  timestamp?: string;
}
