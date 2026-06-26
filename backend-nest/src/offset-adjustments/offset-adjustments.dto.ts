import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export const OFFSET_ADJUSTMENT_TYPES = [
  'SINGLE_ORDER',
  'VNPAY_QROFF',
  'ZALOPAY',
  'SHOPEEPAY',
] as const;

export const OFFSET_ADJUSTMENT_STATUSES = [
  'PENDING_ACC',
  'APPROVED',
  'REJECTED_NEEDS_FIX',
] as const;
export const OFFSET_ADJUSTMENT_NOTIFICATION_STATUS = 'NOTIFICATION';

export const OFFSET_EDIT_CONTENT_KINDS = [
  'CUSTOMER_OFFSET',
  'TECHNICIAN_OFFSET',
] as const;

export class ListOffsetAdjustmentsDto {
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
  @IsIn(['ALL', ...OFFSET_ADJUSTMENT_TYPES])
  type?: string;

  @IsOptional()
  @IsString()
  @IsIn([
    'ALL',
    OFFSET_ADJUSTMENT_NOTIFICATION_STATUS,
    ...OFFSET_ADJUSTMENT_STATUSES,
  ])
  status?: string;

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

export class ExportOffsetAdjustmentsDto extends ListOffsetAdjustmentsDto {}

export class CreateOffsetAdjustmentDto {
  @IsString()
  @IsIn(OFFSET_ADJUSTMENT_TYPES)
  type!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  amount!: number;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  oldOrderCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  newOrderCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  orderCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  scanDate?: string;

  @IsOptional()
  @IsString()
  @IsIn(OFFSET_EDIT_CONTENT_KINDS)
  editContentKind?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  transactionCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

export class ResubmitOffsetAdjustmentDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  amount?: number;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  oldOrderCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  newOrderCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  orderCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  scanDate?: string;

  @IsOptional()
  @IsString()
  @IsIn(OFFSET_EDIT_CONTENT_KINDS)
  editContentKind?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  transactionCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

export class CompleteOffsetAdjustmentDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  ctCode?: string;
}

export class RejectOffsetAdjustmentDto {
  @IsString()
  @MaxLength(400)
  reason!: string;
}
