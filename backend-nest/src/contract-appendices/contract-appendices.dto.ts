import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

export const MANUAL_VAT_RATE_BPS = [0, 500, 800, 1000] as const;

export class ContractAppendixLineOverrideDto {
  @IsString()
  @MinLength(1)
  @MaxLength(160)
  sourceLineKey!: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(200)
  @IsString({ each: true })
  @MinLength(1, { each: true })
  @MaxLength(240, { each: true })
  sourceLineIdentities?: string[];

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  productName?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(30)
  unit?: string;

  @IsOptional()
  @IsInt()
  @IsIn(MANUAL_VAT_RATE_BPS)
  manualVatRateBps?: number;
}

export class PreviewContractAppendixDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(80)
  orderCode?: string;

  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(10)
  @IsString({ each: true })
  @MinLength(1, { each: true })
  @MaxLength(80, { each: true })
  orderCodes?: string[];

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => ContractAppendixLineOverrideDto)
  overrides?: ContractAppendixLineOverrideDto[];
}

export class CreateContractAppendixDto extends PreviewContractAppendixDto {
  @IsString()
  @Matches(/^[a-f0-9]{64}$/)
  quoteVersion!: string;
}

export class ListContractAppendicesDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  page: number = 0;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit: number = 20;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  query?: string;
}
