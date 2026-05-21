import { Type } from 'class-transformer';
import {
  IsInt,
  IsOptional,
  IsString,
  Max,
  Min,
  MaxLength,
} from 'class-validator';

export class SearchMapVietinTransactionsDto {
  @IsOptional()
  @IsString()
  @MaxLength(40)
  storeId?: string;

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
  searchType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  searchInput?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  branchId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  terminalId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  paymentMethod?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  transactionStatus?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  amount?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  tranNumber?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  size?: number;
}

export class ListStoredMapVietinTransactionsDto {
  @IsOptional()
  @IsString()
  @MaxLength(40)
  storeId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  afterFirstSeenAt?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}
