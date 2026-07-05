import { Type } from 'class-transformer';
import {
  IsArray,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export class ListSalesTargetsDto {
  @IsString()
  @Matches(/^\d{4}-(0[1-9]|1[0-2])$/)
  month!: string;
}

export class SalesTargetItemDto {
  @IsString()
  @MaxLength(80)
  organizationNodeId!: string;

  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 0 })
  @Min(1)
  @Max(Number.MAX_SAFE_INTEGER)
  targetBeforeTax?: number | null;
}

export class UpdateSalesTargetsDto extends ListSalesTargetsDto {
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SalesTargetItemDto)
  targets!: SalesTargetItemDto[];
}
