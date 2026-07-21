import { Type } from 'class-transformer';
import {
  IsArray,
  IsIn,
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
  @MaxLength(400)
  storeIds?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  allStores?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  afterFirstSeenAt?: string;

  @IsOptional()
  @IsString()
  @MaxLength(5)
  includeTotal?: string;

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
  @Type(() => Number)
  @IsInt()
  @Min(0)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}

export class ListMapVietinStatementsDto {
  @IsOptional()
  @IsString()
  @MaxLength(400)
  storeIds?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  allStores?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  statementNumber?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  order?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  amount?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  content?: string;

  @IsOptional()
  @IsString()
  @IsIn([
    'ALL',
    'HAS_ORDER',
    'MISSING_ORDER',
    'OFFSET_PENDING',
    'OFFSET_CONFIRMED',
  ])
  orderStatus?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  startDate?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  endDate?: string;

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
  limit?: number;
}

export class ExportMapVietinStatementsDto extends ListMapVietinStatementsDto {
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  transactionIds?: string[];
}

export class UpdateMapVietinStatementOrdersDto {
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  orders!: string[];

  @IsOptional()
  @IsString()
  @MaxLength(200)
  transactionKey?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  statementNumber?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  amount?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  order?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  content?: string;
}

export class UpdateMapVietinStatementIncomeTypeDto {
  @IsString()
  @IsIn(['SALES', 'PARTNER_INTERNAL'])
  incomeType!: string;
}

export class CreateMapVietinStatementOrderTransferRequestDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  transactionKey?: string;

  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  orders!: string[];
}

export class ReviewMapVietinStatementOrderTransferRequestDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

export class ListMapVietinStatementOrderTransferRequestsDto {
  @IsOptional()
  @IsString()
  @IsIn(['PENDING', 'APPROVED', 'REJECTED', 'EXPIRED', 'NOTIFICATION'])
  status?: string;

  @IsOptional()
  @IsString()
  @MaxLength(400)
  storeIds?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  allStores?: string;

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
  limit?: number;
}
